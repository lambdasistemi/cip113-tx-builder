{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.CIP113.CLI.Command.Transfer (
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
    positiveAmountSetting,
    tokenNameSetting,
 )
import Cardano.CIP113.Deployment (CIP113Deployment (..))
import Cardano.CIP113.Registry (RegistryNodeUtxo (..), ResolvedRegistryNode (..), findNode)
import Cardano.CIP113.Transfer (TransferInput (..), transferTx)
import Cardano.CIP113.Types (RegistryProof (..))
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
    { optionsFromAddress :: !Addr
    , optionsToAddress :: !Addr
    , optionsTokenName :: !Text
    , optionsPolicyId :: !Text
    , optionsAmount :: !Integer
    , optionsChangeAddress :: !(Maybe Addr)
    }
    deriving (Show, Eq)

parser :: Parser Options
parser =
    Options
        <$> addressAddrSetting "from-address" "Sender address"
        <*> addressAddrSetting "to-address" "Recipient address"
        <*> tokenNameSetting
        <*> policyIdSetting
        <*> positiveAmountSetting
        <*> optional changeAddressAddrSetting

runWithNodeProvider :: CIP113Deployment -> Node.Provider IO -> Bool -> Options -> IO ()
runWithNodeProvider deployment provider jsonOutput options = do
    txHex <- buildTransferNodeTxHex deployment provider options
    if jsonOutput
        then putStrLn ("{\"tx\":\"" <> txHex <> "\"}")
        else putStrLn txHex

buildTransferNodeTxHex :: CIP113Deployment -> Node.Provider IO -> Options -> IO String
buildTransferNodeTxHex deployment@CIP113Deployment{..} provider options = do
    changeAddr <-
        case optionsChangeAddress options of
            Just address ->
                pure address
            Nothing ->
                dieUser "real transfer requires --change-address"
    policyKey <- decodePolicyKey (optionsPolicyId options)
    policyId <- decodePolicyId (optionsPolicyId options)
    let tokenName = AssetName (SBS.toShort (Text.encodeUtf8 (optionsTokenName options)))
        fromAddr = optionsFromAddress options
        toAddr = optionsToAddress options
    pp <- queryProtocolParams provider
    fundingUtxos <- queryUTxOs provider changeAddr
    senderUtxos <- queryUTxOs provider fromAddr
    registryUtxos <- queryUTxOs provider dRegistryAddr
    lockedUtxos <- queryUTxOs provider dAlwaysFailAddr
    collateralIn <-
        case largeFeeUtxos fundingUtxos of
            (txIn, _) : _ ->
                pure txIn
            [] ->
                dieUser "no funding UTxOs available at --change-address"
    selectedInputs <- selectNodeTransferInputs options policyId tokenName senderUtxos
    resolvedNode <-
        either
            (dieUser . ("failed to resolve registered token: " <>) . show)
            (maybe (dieUser "registered token not found in registry") pure)
            =<< findNode deployment provider (map fst lockedUtxos) policyKey
    let ResolvedRegistryNode{rrnUtxo, rrnReferenceInputIndex} = resolvedNode
        RegistryNodeUtxo{rnuTxIn = registryNodeIn} = rrnUtxo
        proof = TokenExists rrnReferenceInputIndex
    (requiredSigner, sourceAccount) <-
        either dieUser pure (sourceAuthorization fromAddr)
    let totalSelected =
            sum
                [ txOutAssetAmount policyId tokenName txOut
                | (_, txOut) <- selectedInputs
                ]
        requested = optionsAmount options
        pairedOutputs =
            [ (fromAddr, removeAssetAmount policyId tokenName amount (txOut ^. valueTxOutL))
            | (_, txOut) <- selectedInputs
            , let amount = txOutAssetAmount policyId tokenName txOut
            ]
        outputs =
            pairedOutputs
                <> [(toAddr, tokenValue policyId tokenName requested)]
                <> [ (fromAddr, tokenValue policyId tokenName (totalSelected - requested))
                   | totalSelected > requested
                   ]
        transferBuild :: TxBuild NoQ NoErr ()
        transferBuild = do
            collateral collateralIn
            requireSignature requiredSigner
            transferTx
                (plgAccountAddress Testnet dPlgHash)
                dPlbScript
                dPlgScript
                [ TransferInput txIn proof
                | (txIn, _) <- selectedInputs
                ]
                [registryNodeIn]
                []
                outputs
            withdraw sourceAccount (Coin 0)
            mapM_ (reference . fst) lockedUtxos
        interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
    tx <-
        either (dieUser . ("failed to build transfer transaction: " <>) . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                (largeFeeUtxos fundingUtxos <> selectedInputs)
                (registryUtxos <> lockedUtxos)
                changeAddr
                transferBuild
    pure (Text.unpack (hexText (serialize' (eraProtVerLow @ConwayEra) tx)))

data NoQ a
data NoErr deriving (Show)

sourceAuthorization :: Addr -> Either String (KeyHash Guard, AccountAddress)
sourceAuthorization = \case
    Addr _ _ (StakeRefBase (KeyHashObj (KeyHash h))) ->
        Right (KeyHash h, AccountAddress Testnet (AccountId (KeyHashObj (KeyHash h))))
    Addr _ _ StakeRefNull ->
        Left "source smart wallet must use a key-backed staking credential"
    Addr _ _ (StakeRefBase (ScriptHashObj _)) ->
        Left "source smart wallet script staking credentials are not supported by transfer CLI signing yet"
    Addr _ _ (StakeRefPtr _) ->
        Left "source smart wallet stake pointers are not supported by transfer CLI signing"
    AddrBootstrap _ ->
        Left "source smart wallet must be a Shelley-era address"

selectNodeTransferInputs ::
    Options ->
    PolicyID ->
    AssetName ->
    [(TxIn, TxOut ConwayEra)] ->
    IO [(TxIn, TxOut ConwayEra)]
selectNodeTransferInputs options policyId tokenName senderUtxos = do
    case matchingUtxOs of
        [] ->
            dieUser "no UTxOs carry the requested token"
        _
            | totalAvailable < requiredAmount ->
                dieUser
                    ( "insufficient token balance: available "
                        <> show totalAvailable
                        <> ", required "
                        <> show requiredAmount
                    )
        _ ->
            pure (fst <$> takeUntilAtLeast requiredAmount matchingUtxOs)
  where
    requiredAmount = optionsAmount options
    matchingUtxOs =
        [ (utxo, amount)
        | utxo@(_, txOut) <- senderUtxos
        , let amount = txOutAssetAmount policyId tokenName txOut
        , amount > 0
        ]
    totalAvailable =
        sum (snd <$> matchingUtxOs)

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

hexText :: BS.ByteString -> Text
hexText =
    Text.decodeUtf8 . Base16.encode

takeUntilAtLeast :: Integer -> [(a, Integer)] -> [(a, Integer)]
takeUntilAtLeast required =
    go 0 []
  where
    go _ selected [] =
        reverse selected
    go total selected (utxoWithAmount@(_, amount) : rest)
        | total >= required =
            reverse selected
        | otherwise =
            go (total + amount) (utxoWithAmount : selected) rest

dieUser :: String -> IO a
dieUser message = do
    hPutStrLn stderr ("transfer: " <> message)
    exitWith (ExitFailure 1)
