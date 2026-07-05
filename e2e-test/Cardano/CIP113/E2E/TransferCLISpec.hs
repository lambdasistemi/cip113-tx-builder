{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.E2E.TransferCLISpec (spec) where

import Cardano.Crypto.DSIGN.Class (rawSerialiseSignKeyDSIGN)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams, ppKeyDepositL)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (originalBytes)
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.E2E.Setup (
    addKeyWitness,
    genesisAddr,
    genesisSignKey,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (submitTx))
import Cardano.Tx.Build (
    CertWitness (..),
    InterpretIO (..),
    TxBuild,
    attachScript,
    build,
    collateral,
    mint,
    mkPParamsBound,
    payTo,
    payTo',
    reference,
    registerAndVoteAbstain,
    spendScript,
    withdrawScript,
 )
import Cardano.Tx.Diff (decodeConwayTxInput)
import Control.Concurrent (threadDelay)
import Control.Monad (unless)
import Data.Aeson qualified as Aeson
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Lens.Micro ((^.))
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec

import Cardano.CIP113.Address (plgAccountAddress, smartWalletAddr)
import Cardano.CIP113.E2E.Deploy (
    CIP113Deployment (..),
    deployCIP113,
    nftValue,
    withCIP113DevnetSocket,
 )
import Cardano.CIP113.Scripts (loadBlueprint, scriptHashBytes)
import Cardano.CIP113.Types (
    CIP113Credential (..),
    MintingRegistryProof (..),
    PLGRedeemer (..),
    RegistrationMode (..),
    RegistryNode (..),
    RegistryRedeemer (..),
    originNode,
    sentinelNext,
 )

spec :: Spec
spec =
    describe "CIP-113 transfer CLI subprocess smoke" $
        it
            "registers a policy, transfers a smart-wallet token, signs, submits, and accepts it"
            runSmoke

data NoQ a
data NoErr deriving (Show)

runSmoke :: IO ()
runSmoke = do
    cip113Cli <- requireCIP113CLI
    withCIP113DevnetSocket $ \socketPath lsq ltxs -> do
        let provider = mkN2CProvider lsq
            submitter = mkN2CSubmitter ltxs
        pp <- queryProtocolParams provider
        utxos <- queryUTxOs provider genesisAddr
        bp <- loadBlueprint "fixtures/cip113-blueprint.json"
        deployment@CIP113Deployment{..} <- deployCIP113 bp provider submitter pp utxos

        withSystemTempDirectory "cip113-cli-transfer-smoke" $ \tmpDir -> do
            let deploymentFile = tmpDir </> "deployment.json"
                signingKeyFile = tmpDir </> "genesis.skey"
                changeAddressHex = hex (serialiseAddr genesisAddr)
                tokenName = "cli-transfer"
                policyIdHex = case dIssuancePolicy of
                    PolicyID h -> hex (scriptHashBytes h)
                smartWallet =
                    smartWalletAddr
                        Testnet
                        dPlbHash
                        genesisStakeCredential
                recipientWallet =
                    smartWalletAddr
                        Testnet
                        dPlbHash
                        (ScriptHashObj dPlgHash)
                smartWalletHex = hex (serialiseAddr smartWallet)
                recipientWalletHex = hex (serialiseAddr recipientWallet)
            BSL.writeFile deploymentFile (Aeson.encode deployment)
            BSL.writeFile signingKeyFile genesisSigningKeyTextEnvelope

            registerTransferAccount provider submitter pp
            threadDelay 5_000_000
            registeredNodeIn <- registerTransferToken provider submitter pp deployment
            threadDelay 5_000_000
            fundSmartWallet provider submitter pp deployment registeredNodeIn tokenName smartWallet
            threadDelay 5_000_000

            unsignedTransferHex <-
                runCli
                    "transfer"
                    cip113Cli
                    [ "--socket-path"
                    , socketPath
                    , "--network-magic"
                    , "42"
                    , "transfer"
                    , "--deployment"
                    , deploymentFile
                    , "--change-address"
                    , changeAddressHex
                    , "--from-address"
                    , smartWalletHex
                    , "--to-address"
                    , recipientWalletHex
                    , "--token-name"
                    , tokenName
                    , "--policy-id"
                    , policyIdHex
                    , "--amount"
                    , "1"
                    ]
                    ""
            signAndSubmit cip113Cli signingKeyFile submitter "transfer" unsignedTransferHex

registerTransferAccount ::
    Provider IO ->
    Submitter IO ->
    PParams ConwayEra ->
    IO ()
registerTransferAccount provider submitter pp = do
    genesisUtxos <- queryUTxOs provider genesisAddr
    let registerTx :: TxBuild NoQ NoErr ()
        registerTx = do
            _ <-
                registerAndVoteAbstain
                    genesisStakeCredential
                    (pp ^. ppKeyDepositL)
                    PubKeyCert
            pure ()
        interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
    tx <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                (largeFeeUtxos genesisUtxos)
                []
                genesisAddr
                registerTx
    result <- submitTx submitter (addKeyWitness genesisSignKey tx)
    case result of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "transfer account registration rejected: " <> show reason

registerTransferToken ::
    Provider IO ->
    Submitter IO ->
    PParams ConwayEra ->
    CIP113Deployment ->
    IO TxIn
registerTransferToken provider submitter pp CIP113Deployment{..} = do
    registryUtxos <- queryUTxOs provider dRegistryAddr
    (originIn, originOut) <- case registryUtxos of
        u : _ -> pure u
        [] -> fail "no registry UTxOs"
    genesisUtxos <- queryUTxOs provider genesisAddr
    lockedUtxos <- queryUTxOs provider dAlwaysFailAddr
    collateralIn <- case genesisUtxos of
        (txIn, _) : _ -> pure txIn
        [] -> fail "no genesis UTxOs for registry insert collateral"
    let testPolicyKey = case dIssuancePolicy of
            PolicyID h -> scriptHashBytes h
        mintingCred = ScriptCredential (scriptHashBytes dPlgHash)
        transferCred = case genesisStakeCredential of
            KeyHashObj (KeyHash h) -> VKeyCredential (originalBytes h)
            ScriptHashObj h -> ScriptCredential (scriptHashBytes h)
        updatedOrigin =
            originNode
                { rnNext = testPolicyKey
                }
        newNode =
            RegistryNode
                { rnKey = testPolicyKey
                , rnNext = sentinelNext
                , rnMintingLogicScript = mintingCred
                , rnTransferLogicScript = transferCred
                , rnThirdPartyTransferLogicScript = transferCred
                , rnGlobalStateCs = mempty
                , rnProtectedPrefixes = []
                }
        insertRdmr =
            RegistryInsert
                { riKey = testPolicyKey
                , riMintingLogicScript = mintingCred
                , riMode = RegisterOnly
                }
        interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
        insertTx :: TxBuild NoQ NoErr ()
        insertTx = do
            attachScript dRegistrySpendScript
            attachScript dRegistryMintScript
            attachScript dPlgScript
            collateral collateralIn
            mapM_ (reference . fst) lockedUtxos
            _ <- spendScript originIn insertRdmr
            withdrawScript
                (plgAccountAddress Testnet dPlgHash)
                (Coin 0)
                (TransferAct [])
            _ <-
                mint
                    dRegistryPolicy
                    (Map.singleton (AssetName (SBS.toShort testPolicyKey)) 1)
                    insertRdmr
            _ <- payTo' dRegistryAddr (originOut ^. valueTxOutL) updatedOrigin
            _ <-
                payTo'
                    dRegistryAddr
                    (nftValue dRegistryPolicy (AssetName (SBS.toShort testPolicyKey)) 2_000_000)
                    newNode
            pure ()
    tx <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                (largeFeeUtxos genesisUtxos <> registryUtxos)
                lockedUtxos
                genesisAddr
                insertTx
    result <- submitTx submitter (addKeyWitness genesisSignKey tx)
    case result of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "registry insert rejected: " <> show reason
    threadDelay 5_000_000
    registryUtxosAfter <- queryUTxOs provider dRegistryAddr
    let registryAsset = AssetName (SBS.toShort testPolicyKey)
    case filter (hasToken dRegistryPolicy registryAsset . snd) registryUtxosAfter of
        (registeredNodeIn, _) : _ -> pure registeredNodeIn
        [] -> fail "no registry UTxO for registered policy after insert"

fundSmartWallet ::
    Provider IO ->
    Submitter IO ->
    PParams ConwayEra ->
    CIP113Deployment ->
    TxIn ->
    String ->
    Addr ->
    IO ()
fundSmartWallet provider submitter pp CIP113Deployment{..} registeredNodeIn tokenName smartWallet = do
    registryUtxos <- queryUTxOs provider dRegistryAddr
    lockedUtxos <- queryUTxOs provider dAlwaysFailAddr
    genesisUtxos <- queryUTxOs provider genesisAddr
    collateralIn <- case genesisUtxos of
        (txIn, _) : _ -> pure txIn
        [] -> fail "no genesis UTxOs for fund collateral"
    let fundRefInputs = registeredNodeIn : map fst lockedUtxos
        registeredNodeRefIdx =
            case List.elemIndex registeredNodeIn (List.sort fundRefInputs) of
                Just ix -> ix
                Nothing -> error "registered policy node missing from fund reference inputs"
        tokenAsset = AssetName (SBS.toShort (BS8.pack tokenName))
        fundValue = nftValue dIssuancePolicy tokenAsset 5_000_000
        interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
        fundTx :: TxBuild NoQ NoErr ()
        fundTx = do
            attachScript dIssuanceMintScript
            attachScript dPlgScript
            collateral collateralIn
            reference registeredNodeIn
            mapM_ (reference . fst) lockedUtxos
            withdrawScript
                (plgAccountAddress Testnet dPlgHash)
                (Coin 0)
                (TransferAct [])
            mint dIssuancePolicy (Map.singleton tokenAsset 1) (RefInputProof registeredNodeRefIdx)
            _ <- payTo smartWallet fundValue
            pure ()
    tx <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                (largeFeeUtxos genesisUtxos)
                (registryUtxos <> lockedUtxos)
                genesisAddr
                fundTx
    result <- submitTx submitter (addKeyWitness genesisSignKey tx)
    case result of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "fund smart wallet rejected: " <> show reason

signAndSubmit ::
    FilePath ->
    FilePath ->
    Submitter IO ->
    String ->
    String ->
    IO ()
signAndSubmit cip113Cli signingKeyFile submitter label unsignedHex = do
    signedHex <-
        runCli
            (label <> " sign")
            cip113Cli
            [ "sign"
            , "--signing-key"
            , signingKeyFile
            ]
            unsignedHex
    signedTx <- case decodeConwayTxInput (BS8.pack signedHex) of
        Left err -> fail ("signed CLI " <> label <> " tx did not decode: " <> show err)
        Right tx -> pure tx
    result <- submitTx submitter signedTx
    case result of
        Submitted _ -> pure ()
        Rejected reason ->
            expectationFailure ("signed CLI " <> label <> " tx rejected: " <> show reason)

requireCIP113CLI :: IO FilePath
requireCIP113CLI = do
    path <- lookupEnv "CIP113_CLI"
    case path of
        Nothing ->
            fail "CIP113_CLI is not set; gate.sh must pass the built cip113-cli path"
        Just cli -> do
            exists <- doesFileExist cli
            unless exists $
                expectationFailure ("CIP113_CLI does not point to a file: " <> cli)
            pure cli

runCli :: String -> FilePath -> [String] -> String -> IO String
runCli label cli args stdin = do
    (code, stdout, stderr) <- readProcessWithExitCode cli args stdin
    case code of
        ExitSuccess -> pure stdout
        ExitFailure n ->
            fail $
                "cip113-cli "
                    <> label
                    <> " failed with exit "
                    <> show n
                    <> "\nstderr:\n"
                    <> stderr
                    <> "\nstdout:\n"
                    <> stdout

genesisStakeCredential :: Credential Staking
genesisStakeCredential =
    case genesisAddr of
        Addr _ (KeyHashObj (KeyHash h)) _ ->
            KeyHashObj (KeyHash h)
        _ -> error "genesisAddr is not a key hash address"

largeFeeUtxos :: [(txIn, TxOut ConwayEra)] -> [(txIn, TxOut ConwayEra)]
largeFeeUtxos utxos =
    case filter ((>= Coin 10_000_000) . (^. coinTxOutL) . snd) utxos of
        [] -> utxos
        large -> large

hasToken :: PolicyID -> AssetName -> TxOut ConwayEra -> Bool
hasToken policy asset txOut =
    case txOut ^. valueTxOutL of
        MaryValue _ multiAsset ->
            assetAmount policy asset multiAsset == 1

assetAmount :: PolicyID -> AssetName -> MultiAsset -> Integer
assetAmount policy asset (MultiAsset assets) =
    Map.findWithDefault 0 asset (Map.findWithDefault Map.empty policy assets)

genesisSigningKeyTextEnvelope :: BSL.ByteString
genesisSigningKeyTextEnvelope =
    Aeson.encode $
        Aeson.object
            [ "type" Aeson..= ("GenesisUTxOSigningKey_ed25519" :: Text.Text)
            , "description" Aeson..= ("Genesis UTxO signing key" :: Text.Text)
            , "cborHex" Aeson..= ("5820" <> hex (rawSerialiseSignKeyDSIGN genesisSignKey))
            ]

hex :: BS8.ByteString -> String
hex =
    Text.unpack . TE.decodeUtf8 . Base16.encode
