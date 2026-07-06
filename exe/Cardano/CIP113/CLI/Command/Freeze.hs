{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.CIP113.CLI.Command.Freeze (
    Options (..),
    parser,
    runWithNodeProvider,
) where

import Control.Applicative (optional)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Lens.Micro ((^.))
import OptEnvConf (Parser)
import System.Exit (ExitCode (ExitFailure), exitWith)
import System.IO (hPutStrLn, stderr)

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.Ledger.Address (AccountAddress (..), AccountId (..), Addr (..))
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerLow)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxIn)

import Cardano.CIP113.Address (plgAccountAddress)
import Cardano.CIP113.CLI.Settings (
    addressAddrSetting,
    changeAddressAddrSetting,
    policyIdSetting,
    tokenNameSetting,
 )
import Cardano.CIP113.Deployment (CIP113Deployment (..))
import Cardano.CIP113.Registry (RegistryNodeUtxo (..), ResolvedRegistryNode (..), findNode)
import Cardano.CIP113.ThirdParty (ThirdPartyInput (..), thirdPartyTx)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Provider qualified as Node
import Cardano.Tx.Build (
    InterpretIO (..),
    TxBuild,
    build,
    collateral,
    mkPParamsBound,
    reference,
    requireSignature,
    withdraw,
 )

data Options = Options
    { optionsTargetAddress :: !Addr
    , optionsTokenName :: !Text
    , optionsPolicyId :: !Text
    , optionsChangeAddress :: !(Maybe Addr)
    }
    deriving (Show, Eq)

parser :: Parser Options
parser =
    Options
        <$> addressAddrSetting "target-address" "Target address"
        <*> tokenNameSetting
        <*> policyIdSetting
        <*> optional changeAddressAddrSetting

runWithNodeProvider :: CIP113Deployment -> Node.Provider IO -> Bool -> Options -> IO ()
runWithNodeProvider deployment provider jsonOutput options = do
    txHex <- buildFreezeNodeTxHex deployment provider options
    if jsonOutput
        then putStrLn ("{\"tx\":\"" <> txHex <> "\"}")
        else putStrLn txHex

buildFreezeNodeTxHex :: CIP113Deployment -> Node.Provider IO -> Options -> IO String
buildFreezeNodeTxHex deployment@CIP113Deployment{..} provider options = do
    changeAddr <-
        case optionsChangeAddress options of
            Just address ->
                pure address
            Nothing ->
                dieUser "real freeze requires --change-address"
    policyKey <- decodePolicyKey (optionsPolicyId options)
    policyId <- decodePolicyId (optionsPolicyId options)
    let tokenName = AssetName (SBS.toShort (Text.encodeUtf8 (optionsTokenName options)))
        targetAddr = optionsTargetAddress options
    pp <- queryProtocolParams provider
    fundingUtxos <- queryUTxOs provider changeAddr
    targetUtxos <- queryUTxOs provider targetAddr
    registryUtxos <- queryUTxOs provider dRegistryAddr
    lockedUtxos <- queryUTxOs provider dAlwaysFailAddr
    collateralIn <-
        case largeFeeUtxos fundingUtxos of
            (txIn, _) : _ ->
                pure txIn
            [] ->
                dieUser "no funding UTxOs available at --change-address"
    selectedInputs <- selectNodeMatchingInputs policyId tokenName targetUtxos
    resolvedNode <-
        either
            (dieUser . ("failed to resolve registered token: " <>) . show)
            (maybe (dieUser "registered token not found in registry") pure)
            =<< findNode deployment provider (map fst lockedUtxos) policyKey
    let ResolvedRegistryNode{rrnUtxo, rrnReferenceInputIndex} = resolvedNode
        RegistryNodeUtxo{rnuTxIn = registryNodeIn} = rrnUtxo
    (requiredSigner, thirdPartyAccount) <-
        either dieUser pure (targetAuthorization targetAddr)
    let outputPairs =
            [ ( targetAddr
              , removeAssetAmount policyId tokenName amount (txOut ^. valueTxOutL)
              , targetAddr
              , tokenValue policyId tokenName amount
              )
            | (_, txOut) <- selectedInputs
            , let amount = txOutAssetAmount policyId tokenName txOut
            ]
        outputs =
            concat
                [ [(pairedAddr, pairedValue), (lockedAddr, lockedValue)]
                | (pairedAddr, pairedValue, lockedAddr, lockedValue) <- outputPairs
                ]
        freezeInputs =
            [ ThirdPartyInput
                { tpTxIn = txIn
                , tpRegistryNodeIdx = rrnReferenceInputIndex
                , tpOutputsStartIdx = ix * 2
                }
            | (ix, (txIn, _)) <- zip [0 ..] selectedInputs
            ]
        freezeBuild :: TxBuild NoQ NoErr ()
        freezeBuild = do
            collateral collateralIn
            requireSignature requiredSigner
            thirdPartyTx
                (plgAccountAddress Testnet dPlgHash)
                dPlbScript
                dPlgScript
                freezeInputs
                [registryNodeIn]
                []
                outputs
            withdraw thirdPartyAccount (Coin 0)
            mapM_ (reference . fst) lockedUtxos
        interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
    tx <-
        either (dieUser . ("failed to build freeze transaction: " <>) . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                (largeFeeUtxos fundingUtxos <> selectedInputs)
                (registryUtxos <> lockedUtxos)
                changeAddr
                freezeBuild
    pure (Text.unpack (Text.decodeUtf8 (Base16.encode (serialize' (eraProtVerLow @ConwayEra) tx))))

data NoQ a
data NoErr deriving (Show)

targetAuthorization :: Addr -> Either String (KeyHash Guard, AccountAddress)
targetAuthorization = \case
    Addr _ _ (StakeRefBase (KeyHashObj (KeyHash h))) ->
        Right (KeyHash h, AccountAddress Testnet (AccountId (KeyHashObj (KeyHash h))))
    Addr _ _ StakeRefNull ->
        Left "target smart wallet must use a key-backed staking credential"
    Addr _ _ (StakeRefBase (ScriptHashObj _)) ->
        Left "target smart wallet script staking credentials are not supported by freeze CLI signing yet"
    Addr _ _ (StakeRefPtr _) ->
        Left "target smart wallet stake pointers are not supported by freeze CLI signing"
    AddrBootstrap _ ->
        Left "target smart wallet must be a Shelley-era address"

selectNodeMatchingInputs ::
    PolicyID ->
    AssetName ->
    [(TxIn, TxOut ConwayEra)] ->
    IO [(TxIn, TxOut ConwayEra)]
selectNodeMatchingInputs policyId tokenName targetUtxos =
    case matchingUtxOs of
        [] ->
            dieUser "no UTxOs carry the requested token"
        _ ->
            pure matchingUtxOs
  where
    matchingUtxOs =
        [ utxo
        | utxo@(_, txOut) <- targetUtxos
        , txOutAssetAmount policyId tokenName txOut > 0
        ]

txOutAssetAmount :: PolicyID -> AssetName -> TxOut ConwayEra -> Integer
txOutAssetAmount policyId tokenName txOut =
    maryValueAssetAmount policyId tokenName (txOut ^. valueTxOutL)

maryValueAssetAmount :: PolicyID -> AssetName -> MaryValue -> Integer
maryValueAssetAmount policyId tokenName (MaryValue _ (MultiAsset assets)) =
    Map.findWithDefault 0 tokenName (Map.findWithDefault Map.empty policyId assets)

removeAssetAmount :: PolicyID -> AssetName -> Integer -> MaryValue -> MaryValue
removeAssetAmount policyId tokenName amount (MaryValue coin (MultiAsset assets)) =
    MaryValue coin (MultiAsset (Map.update prunePolicy policyId assets))
  where
    prunePolicy inner =
        let inner' = Map.update pruneAsset tokenName inner
         in if Map.null inner'
                then Nothing
                else Just inner'
    pruneAsset n =
        let n' = n - amount
         in if n' <= 0
                then Nothing
                else Just n'

tokenValue :: PolicyID -> AssetName -> Integer -> MaryValue
tokenValue policyId tokenName amount =
    MaryValue
        (Coin 0)
        (MultiAsset (Map.singleton policyId (Map.singleton tokenName amount)))

largeFeeUtxos :: [(txIn, TxOut ConwayEra)] -> [(txIn, TxOut ConwayEra)]
largeFeeUtxos utxos =
    case filter ((>= Coin 10_000_000) . (^. coinTxOutL) . snd) utxos of
        [] -> utxos
        large -> large

decodePolicyKey :: Text -> IO BS.ByteString
decodePolicyKey =
    decodeHexText "policy id"

decodePolicyId :: Text -> IO PolicyID
decodePolicyId raw = do
    bytes <- decodePolicyKey raw
    case hashFromBytes bytes of
        Just hash ->
            pure (PolicyID (ScriptHash hash))
        Nothing ->
            dieUser "policy id must decode to a 28-byte script hash"

decodeHexText :: String -> Text -> IO BS.ByteString
decodeHexText label raw =
    case Base16.decode (Text.encodeUtf8 raw) of
        Right bytes ->
            pure bytes
        Left err ->
            fail ("invalid " <> label <> " base16: " <> err)

dieUser :: String -> IO a
dieUser message = do
    hPutStrLn stderr ("freeze: " <> message)
    exitWith (ExitFailure 1)
