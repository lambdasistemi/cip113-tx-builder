{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.CIP113.CLI.Command.Register (
    Options (..),
    parser,
    runWithNodeProvider,
) where

import Control.Applicative (optional)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Lens.Micro ((^.))
import OptEnvConf (Parser)
import System.Exit (ExitCode (ExitFailure), exitWith)
import System.IO (hPutStrLn, stderr)

import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerLow)
import Cardano.Ledger.TxIn (TxIn)

import Cardano.CIP113.Address (plgAccountAddress)
import Cardano.CIP113.CLI.Settings (
    changeAddressAddrSetting,
    policyIdSetting,
    tokenNameSetting,
 )
import Cardano.CIP113.Deployment (CIP113Deployment (..))
import Cardano.CIP113.Register (registerTx)
import Cardano.CIP113.Registry (RegistryNodeUtxo (..), findInsertionPoint)
import Cardano.CIP113.Scripts (scriptHashBytes)
import Cardano.CIP113.Types (
    CIP113Credential (..),
    PLGRedeemer (..),
    RegistrationMode (..),
    RegistryNode (..),
    RegistryRedeemer (..),
 )
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Provider qualified as Node
import Cardano.Tx.Build (
    InterpretIO (..),
    TxBuild,
    attachScript,
    build,
    collateral,
    mkPParamsBound,
    reference,
    withdrawScript,
 )

data Options = Options
    { optionsTokenName :: !Text
    , optionsPolicyId :: !Text
    , optionsChangeAddress :: !(Maybe Addr)
    }
    deriving (Show, Eq)

parser :: Parser Options
parser =
    Options
        <$> tokenNameSetting
        <*> policyIdSetting
        <*> optional changeAddressAddrSetting

runWithNodeProvider :: CIP113Deployment -> Node.Provider IO -> Bool -> Options -> IO ()
runWithNodeProvider deployment provider jsonOutput options = do
    txHex <- buildRegisterNodeTxHex deployment provider options
    if jsonOutput
        then putStrLn ("{\"tx\":\"" <> txHex <> "\"}")
        else putStrLn txHex

buildRegisterNodeTxHex :: CIP113Deployment -> Node.Provider IO -> Options -> IO String
buildRegisterNodeTxHex deployment@CIP113Deployment{..} provider options = do
    changeAddr <-
        case optionsChangeAddress options of
            Just address ->
                pure address
            Nothing ->
                dieUser "real register requires --change-address"
    newPolicyKey <- decodePolicyKey (optionsPolicyId options)
    predecessor <-
        either
            (dieUser . ("failed to resolve registry predecessor: " <>) . show)
            pure
            =<< findInsertionPoint deployment provider newPolicyKey
    let RegistryNodeUtxo{rnuTxIn, rnuTxOut, rnuNode = predecessorNode} =
            predecessor
        predecessorValue = rnuTxOut ^. valueTxOutL
        mintingCred = ScriptCredential (scriptHashBytes dPlgHash)
        updatedPredecessor =
            predecessorNode
                { rnNext = newPolicyKey
                }
        newNode =
            RegistryNode
                { rnKey = newPolicyKey
                , rnNext = rnNext predecessorNode
                , rnMintingLogicScript = mintingCred
                , rnTransferLogicScript = mintingCred
                , rnThirdPartyTransferLogicScript = mintingCred
                , rnGlobalStateCs = mempty
                , rnProtectedPrefixes = []
                }
        insertRdmr =
            RegistryInsert
                { riKey = newPolicyKey
                , riMintingLogicScript = mintingCred
                , riMode = RegisterOnly
                }
    pp <- queryProtocolParams provider
    fundingUtxos <- queryUTxOs provider changeAddr
    registryUtxos <- queryUTxOs provider dRegistryAddr
    lockedUtxos <- queryUTxOs provider dAlwaysFailAddr
    collateralIn <-
        case largeFeeUtxos fundingUtxos of
            (txIn, _) : _ ->
                pure txIn
            [] ->
                dieUser "no funding UTxOs available at --change-address"
    let insertTx :: TxBuild NoQ NoErr ()
        insertTx = do
            attachScript dPlgScript
            collateral collateralIn
            mapM_ (reference . fst) lockedUtxos
            withdrawScript
                (plgAccountAddress Testnet dPlgHash)
                (Coin 0)
                (TransferAct [])
            registerTx
                dRegistrySpendScript
                dRegistryMintScript
                dRegistryPolicy
                rnuTxIn
                predecessorValue
                dRegistryAddr
                updatedPredecessor
                newNode
                insertRdmr
                Nothing
        interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
        inputUtxos =
            largeFeeUtxos fundingUtxos <> predecessorInput registryUtxos predecessor
    tx <-
        either (dieUser . ("failed to build register transaction: " <>) . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                inputUtxos
                lockedUtxos
                changeAddr
                insertTx
    pure (Text.unpack (hexText (serialize' (eraProtVerLow @ConwayEra) tx)))

data NoQ a
data NoErr deriving (Show)

largeFeeUtxos :: [(txIn, TxOut ConwayEra)] -> [(txIn, TxOut ConwayEra)]
largeFeeUtxos utxos =
    case filter ((>= Coin 10_000_000) . (^. coinTxOutL) . snd) utxos of
        [] -> utxos
        large -> large

predecessorInput ::
    [(TxIn, TxOut ConwayEra)] ->
    RegistryNodeUtxo ->
    [(TxIn, TxOut ConwayEra)]
predecessorInput registryUtxos RegistryNodeUtxo{rnuTxIn, rnuTxOut} =
    case filter ((== rnuTxIn) . fst) registryUtxos of
        [] -> [(rnuTxIn, rnuTxOut)]
        matches -> matches

decodePolicyKey :: Text -> IO BS.ByteString
decodePolicyKey =
    decodeHexText "policy id"

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

dieUser :: String -> IO a
dieUser message = do
    hPutStrLn stderr ("register: " <> message)
    exitWith (ExitFailure 1)
