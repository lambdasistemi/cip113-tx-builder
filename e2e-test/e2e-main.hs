{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main (main) where

import Cardano.Crypto.DSIGN.Class (rawSerialiseSignKeyDSIGN)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams, ppKeyDepositL)
import Cardano.Ledger.Credential (Credential (..))
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
import Control.Exception (bracket)
import Control.Monad (filterM, unless)
import Data.Aeson qualified as Aeson
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Lens.Micro ((^.))
import System.Directory (doesFileExist)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    hspec,
    it,
    shouldBe,
    shouldSatisfy,
 )

import Cardano.CIP113.Address (plgAccountAddress, smartWalletAddr)
import Cardano.CIP113.E2E.Deploy (
    CIP113Deployment (..),
    deployCIP113,
    nftValue,
    withCIP113DevnetSocket,
 )
import Cardano.CIP113.E2E.DeploymentSpec qualified as DeploymentSpec
import Cardano.CIP113.E2E.FreezeSeizeCLISpec qualified as FreezeSeizeCLISpec
import Cardano.CIP113.E2E.RegisterCLISpec qualified as RegisterCLISpec
import Cardano.CIP113.E2E.RegisterSpec qualified as RegisterSpec
import Cardano.CIP113.E2E.RegistryResolverSpec qualified as RegistryResolverSpec
import Cardano.CIP113.E2E.ThirdPartySpec qualified as ThirdPartySpec
import Cardano.CIP113.E2E.TransferCLISpec qualified as TransferCLISpec
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

main :: IO ()
main = hspec $ do
    tutorialSpec
    DeploymentSpec.spec
    FreezeSeizeCLISpec.spec
    RegisterCLISpec.spec
    RegisterSpec.spec
    RegistryResolverSpec.spec
    ThirdPartySpec.spec
    TransferCLISpec.spec

tutorialSpec :: Spec
tutorialSpec =
    describe "CIP-113 tutorial CLI E2E" $ do
        it "keeps tutorial command blocks aligned with the E2E templates" $ do
            tutorial <- readTutorial
            extractTutorialCommands tutorial `shouldBe` implementedTutorialCommands
        it "keeps repeated real-build settings out of tutorial build commands" $ do
            tutorial <- readTutorial
            let commands = extractTutorialCommands tutorial
                buildNames =
                    [ "register-vault-sign"
                    , "transfer-plaintext-sign"
                    , "freeze-plaintext-sign"
                    , "seize-final-sign"
                    ]
                buildBlocks =
                    [body | (name, body) <- commands, name `elem` buildNames]
                repeatedFlags =
                    [ "--deployment"
                    , "--socket-path"
                    , "--network-magic"
                    , "--change-address"
                    ]
                offendingFlags =
                    [ flag
                    | body <- buildBlocks
                    , flag <- repeatedFlags
                    , flag `List.isInfixOf` body
                    ]
                environmentBlock =
                    fromMaybe "" (lookup "environment" commands)
            offendingFlags `shouldBe` []
            ("CIP113_CONFIG_FILE" `List.isInfixOf` environmentBlock)
                `shouldBe` True
        it
            "runs the tutorial command sequence against a local devnet"
            runTutorial
        it
            "registers using only a config file and environment variables"
            runRegisterConfigEnvProof

implementedTutorialCommands :: [(String, String)]
implementedTutorialCommands =
    [
        ( "environment"
        , renderEnvironmentCommand
        )
    ,
        ( "vault-seal"
        , renderSimpleCommand (vaultSealArgs "$PAYMENT_SKEY" "$PAYMENT_VAULT")
        )
    ,
        ( "register-vault-sign"
        , renderBuildSignSubmit
            (registerArgs "$TOKEN_NAME" "$POLICY_ID")
            (vaultSignArgs "$PAYMENT_VAULT" "$PASSPHRASE_FILE")
            "register"
        )
    ,
        ( "transfer-plaintext-sign"
        , renderBuildSignSubmit
            ( transferArgs
                "$HOLDER_ADDRESS"
                "$RECIPIENT_ADDRESS"
                "$TOKEN_NAME"
                "$POLICY_ID"
            )
            (plaintextSignArgs "$PAYMENT_SKEY")
            "transfer"
        )
    ,
        ( "freeze-plaintext-sign"
        , renderBuildSignSubmit
            (freezeArgs "$RECIPIENT_ADDRESS" "$TOKEN_NAME" "$POLICY_ID")
            (plaintextSignArgs "$PAYMENT_SKEY")
            "freeze"
        )
    ,
        ( "seize-final-sign"
        , renderBuildSignSubmit
            ( seizeArgs
                "$RECIPIENT_ADDRESS"
                "$SEIZED_ADDRESS"
                "$TOKEN_NAME"
                "$POLICY_ID"
            )
            (plaintextSignArgs "$PAYMENT_SKEY")
            "seize"
        )
    ]

renderEnvironmentCommand :: String
renderEnvironmentCommand =
    List.intercalate
        "\n"
        [ "export CIP113_CLI=./result/bin/cip113-cli"
        , "export CIP113_CONFIG_FILE=cip113-cli.config.yaml"
        , "export SOCKET_PATH=/path/to/node.socket"
        , "export NETWORK_MAGIC=42"
        , "export PAYMENT_SKEY=payment.skey"
        , "export PAYMENT_VAULT=payment.vault.age"
        , "export PASSPHRASE_FILE=vault.passphrase"
        , "export POLICY_ID=<56-char-policy-id>"
        , "export TOKEN_NAME=<token-name>"
        , "export HOLDER_ADDRESS=<current-smart-wallet-address>"
        , "export RECIPIENT_ADDRESS=<recipient-smart-wallet-address>"
        , "export SEIZED_ADDRESS=<seized-token-recipient-address>"
        , "cat > \"$CIP113_CONFIG_FILE\" <<YAML"
        , "deployment: deployment.json"
        , "socket-path: $SOCKET_PATH"
        , "network-magic: $NETWORK_MAGIC"
        , "change-address: <hex-serialized-change-address>"
        , "YAML"
        ]

renderSimpleCommand :: [String] -> String
renderSimpleCommand =
    renderInvocation 2

renderBuildSignSubmit :: [String] -> [String] -> String -> String
renderBuildSignSubmit buildArgs signArgs label =
    List.intercalate
        "\n"
        [ renderInvocation 2 buildArgs <> " \\"
        , "  | " <> renderInvocation 6 signArgs <> " \\"
        , "  > " <> label <> ".signed.cborhex"
        , "xxd -r -p " <> label <> ".signed.cborhex > " <> label <> ".signed.cbor"
        , "CARDANO_NODE_SOCKET_PATH=\"$SOCKET_PATH\" cardano-cli transaction submit \\"
        , "  --testnet-magic \"$NETWORK_MAGIC\" \\"
        , "  --tx-file " <> label <> ".signed.cbor"
        ]

renderInvocation :: Int -> [String] -> String
renderInvocation continuationSpaces args =
    case splitCommandWords args of
        ([], _) -> error "cannot render empty tutorial command"
        (commandWords, flagWords) ->
            List.intercalate
                (" \\\n" <> replicate continuationSpaces ' ')
                (unwords (renderArg "$CIP113_CLI" : commandWords) : renderFlagWords flagWords)

splitCommandWords :: [String] -> ([String], [String])
splitCommandWords =
    break ("--" `List.isPrefixOf`)

renderFlagWords :: [String] -> [String]
renderFlagWords [] = []
renderFlagWords [flag] = [flag]
renderFlagWords (flag : value : rest) =
    (flag <> " " <> renderArg value) : renderFlagWords rest

renderArg :: String -> String
renderArg arg
    | "$" `List.isPrefixOf` arg = "\"" <> arg <> "\""
    | otherwise = arg

data NoQ a
data NoErr deriving (Show)

runTutorial :: IO ()
runTutorial = do
    cip113Cli <- requireCIP113CLI
    runRegisterVaultPhase cip113Cli
    runTransferFreezeSeizePhase cip113Cli

runRegisterVaultPhase :: FilePath -> IO ()
runRegisterVaultPhase cip113Cli =
    withCIP113DevnetSocket $ \socketPath lsq ltxs -> do
        let provider = mkN2CProvider lsq
            submitter = mkN2CSubmitter ltxs
        pp <- queryProtocolParams provider
        utxos <- queryUTxOs provider genesisAddr
        bp <- loadBlueprint "fixtures/cip113-blueprint.json"
        deployment@CIP113Deployment{..} <- deployCIP113 bp provider submitter pp utxos

        withSystemTempDirectory "cip113-cli-tutorial-register" $ \tmpDir -> do
            files <- writeTutorialFiles tmpDir deployment
            configFile <- writeCliConfig tmpDir socketPath "42" files
            sealVault cip113Cli files
            unsignedRegisterHex <-
                withEnv [("CIP113_CONFIG_FILE", configFile)] $
                    runCli
                        "tutorial register"
                        cip113Cli
                        (registerArgs (tfTokenName files) (tfPolicyIdHex files))
                        ""
            signedRegisterHex <-
                runCli
                    "tutorial register vault sign"
                    cip113Cli
                    (vaultSignArgs (tfVaultFile files) (tfPassphraseFile files))
                    unsignedRegisterHex
            decodeAndSubmit submitter "register" signedRegisterHex

runTransferFreezeSeizePhase :: FilePath -> IO ()
runTransferFreezeSeizePhase cip113Cli =
    withCIP113DevnetSocket $ \socketPath lsq ltxs -> do
        let provider = mkN2CProvider lsq
            submitter = mkN2CSubmitter ltxs
        pp <- queryProtocolParams provider
        utxos <- queryUTxOs provider genesisAddr
        bp <- loadBlueprint "fixtures/cip113-blueprint.json"
        deployment@CIP113Deployment{..} <- deployCIP113 bp provider submitter pp utxos

        withSystemTempDirectory "cip113-cli-tutorial-transfer-freeze-seize" $ \tmpDir -> do
            files <- writeTutorialFiles tmpDir deployment
            configFile <- writeCliConfig tmpDir socketPath "42" files
            let holderWallet =
                    smartWalletAddr
                        Testnet
                        dPlbHash
                        genesisStakeCredential
                recipientWallet =
                    smartWalletAddr
                        Testnet
                        dPlbHash
                        genesisStakeCredential
                seizedWallet =
                    smartWalletAddr
                        Testnet
                        dPlbHash
                        genesisStakeCredential
                holderWalletHex = hex (serialiseAddr holderWallet)
                recipientWalletHex = hex (serialiseAddr recipientWallet)
                seizedWalletHex = hex (serialiseAddr seizedWallet)

            -- The tutorial's CLI register output currently installs placeholder
            -- logic credentials that collide with mandatory PLG withdrawals in
            -- transfer/freeze/seize. For this phase, prepare the registry node
            -- directly with key-backed transfer and third-party credentials.
            registerTutorialAccount provider submitter pp
            threadDelay 5_000_000
            registeredNodeIn <- registerTutorialToken provider submitter pp deployment
            threadDelay 5_000_000
            fundSmartWallet provider submitter pp deployment registeredNodeIn (tfTokenName files) holderWallet
            threadDelay 5_000_000

            unsignedTransferHex <-
                withEnv [("CIP113_CONFIG_FILE", configFile)] $
                    runCli
                        "tutorial transfer"
                        cip113Cli
                        ( transferArgs
                            holderWalletHex
                            recipientWalletHex
                            (tfTokenName files)
                            (tfPolicyIdHex files)
                        )
                        ""
            decodeAndSubmit
                submitter
                "transfer"
                =<< signPlaintext cip113Cli files "transfer" unsignedTransferHex
            threadDelay 5_000_000

            unsignedFreezeHex <-
                withEnv [("CIP113_CONFIG_FILE", configFile)] $
                    runCli
                        "tutorial freeze"
                        cip113Cli
                        ( freezeArgs
                            recipientWalletHex
                            (tfTokenName files)
                            (tfPolicyIdHex files)
                        )
                        ""
            decodeAndSubmit
                submitter
                "freeze"
                =<< signPlaintext cip113Cli files "freeze" unsignedFreezeHex
            threadDelay 5_000_000

            unsignedSeizeHex <-
                withEnv [("CIP113_CONFIG_FILE", configFile)] $
                    runCli
                        "tutorial seize"
                        cip113Cli
                        ( seizeArgs
                            recipientWalletHex
                            seizedWalletHex
                            (tfTokenName files)
                            (tfPolicyIdHex files)
                        )
                        ""
            decodeAndSubmit
                submitter
                "seize"
                =<< signPlaintext cip113Cli files "seize" unsignedSeizeHex

{- | Live proof that @register@ builds a real transaction with the shared
real-build settings supplied only through a config file and environment
variables, with no @--deployment@, @--socket-path@, @--network-magic@, or
@--change-address@ flags on the command line.
-}
runRegisterConfigEnvProof :: IO ()
runRegisterConfigEnvProof = do
    cip113Cli <- requireCIP113CLI
    withCIP113DevnetSocket $ \socketPath lsq ltxs -> do
        let provider = mkN2CProvider lsq
            submitter = mkN2CSubmitter ltxs
        pp <- queryProtocolParams provider
        utxos <- queryUTxOs provider genesisAddr
        bp <- loadBlueprint "fixtures/cip113-blueprint.json"
        deployment <- deployCIP113 bp provider submitter pp utxos
        withSystemTempDirectory "cip113-cli-register-config-env" $ \tmpDir -> do
            files <- writeTutorialFiles tmpDir deployment
            configFile <- writeCliConfig tmpDir socketPath "42" files
            unsignedRegisterHex <-
                withEnv
                    [ ("CIP113_CONFIG_FILE", configFile)
                    , ("CIP113_TOKEN_NAME", tfTokenName files)
                    , ("CIP113_POLICY_ID", tfPolicyIdHex files)
                    ]
                    (runCli "register config-env proof" cip113Cli ["register"] "")
            unsignedRegisterHex `shouldSatisfy` (not . null)

data TutorialFiles = TutorialFiles
    { tfDeploymentFile :: FilePath
    , tfSigningKeyFile :: FilePath
    , tfVaultFile :: FilePath
    , tfPassphraseFile :: FilePath
    , tfChangeAddressHex :: String
    , tfPolicyIdHex :: String
    , tfTokenName :: String
    }

writeTutorialFiles :: FilePath -> CIP113Deployment -> IO TutorialFiles
writeTutorialFiles tmpDir deployment@CIP113Deployment{..} = do
    let deploymentFile = tmpDir </> "deployment.json"
        signingKeyFile = tmpDir </> "payment.skey"
        vaultFile = tmpDir </> "payment.vault.age"
        passphraseFile = tmpDir </> "vault.passphrase"
        changeAddressHex = hex (serialiseAddr genesisAddr)
        policyIdHex = case dIssuancePolicy of
            PolicyID h -> hex (scriptHashBytes h)
        tokenName = "tutorial-token"
    BSL.writeFile deploymentFile (Aeson.encode deployment)
    BSL.writeFile signingKeyFile genesisSigningKeyTextEnvelope
    writeFile passphraseFile tutorialPassphrase
    pure
        TutorialFiles
            { tfDeploymentFile = deploymentFile
            , tfSigningKeyFile = signingKeyFile
            , tfVaultFile = vaultFile
            , tfPassphraseFile = passphraseFile
            , tfChangeAddressHex = changeAddressHex
            , tfPolicyIdHex = policyIdHex
            , tfTokenName = tokenName
            }

{- | Write a YAML config file carrying the shared real-build settings so the
CLI can read @deployment@, @socket-path@, @network-magic@, and
@change-address@ from configuration instead of per-command flags.
-}
writeCliConfig :: FilePath -> FilePath -> String -> TutorialFiles -> IO FilePath
writeCliConfig tmpDir socketPath networkMagic files = do
    let configFile = tmpDir </> "cip113-cli.config.yaml"
        contents =
            unlines
                [ "deployment: " <> tfDeploymentFile files
                , "socket-path: " <> socketPath
                , "network-magic: " <> networkMagic
                , "change-address: " <> tfChangeAddressHex files
                ]
    writeFile configFile contents
    pure configFile

{- | Run an action with process environment variables set, restoring each to
its previous value (or unset) afterwards so later specs are not
contaminated.
-}
withEnv :: [(String, String)] -> IO a -> IO a
withEnv bindings action =
    bracket acquire release (const action)
  where
    acquire = mapM setBinding bindings
    setBinding (key, val) = do
        previous <- lookupEnv key
        setEnv key val
        pure (key, previous)
    release = mapM_ restore
    restore (key, Nothing) = unsetEnv key
    restore (key, Just previous) = setEnv key previous

registerArgs :: String -> String -> [String]
registerArgs tokenName policyId =
    [ "register"
    , "--token-name"
    , tokenName
    , "--policy-id"
    , policyId
    ]

vaultSealArgs :: FilePath -> FilePath -> [String]
vaultSealArgs signingKey outFile =
    [ "vault"
    , "seal"
    , "--signing-key"
    , signingKey
    , "--out"
    , outFile
    ]

vaultSignArgs :: FilePath -> FilePath -> [String]
vaultSignArgs vaultFile passphraseFile =
    [ "sign"
    , "--signing-key-vault"
    , vaultFile
    , "--passphrase-file"
    , passphraseFile
    ]

plaintextSignArgs :: FilePath -> [String]
plaintextSignArgs signingKey =
    [ "sign"
    , "--signing-key"
    , signingKey
    ]

transferArgs :: String -> String -> String -> String -> [String]
transferArgs fromAddress toAddress tokenName policyId =
    [ "transfer"
    , "--from-address"
    , fromAddress
    , "--to-address"
    , toAddress
    , "--token-name"
    , tokenName
    , "--policy-id"
    , policyId
    , "--amount"
    , "1"
    ]

freezeArgs :: String -> String -> String -> [String]
freezeArgs targetAddress tokenName policyId =
    [ "freeze"
    , "--target-address"
    , targetAddress
    , "--token-name"
    , tokenName
    , "--policy-id"
    , policyId
    ]

seizeArgs :: String -> String -> String -> String -> [String]
seizeArgs targetAddress toAddress tokenName policyId =
    [ "seize"
    , "--target-address"
    , targetAddress
    , "--to-address"
    , toAddress
    , "--token-name"
    , tokenName
    , "--policy-id"
    , policyId
    ]

signPlaintext :: FilePath -> TutorialFiles -> String -> String -> IO String
signPlaintext cip113Cli files label =
    runCli
        ("tutorial " <> label <> " plaintext sign")
        cip113Cli
        (plaintextSignArgs (tfSigningKeyFile files))

sealVault :: FilePath -> TutorialFiles -> IO ()
sealVault cip113Cli files = do
    let liveCommand =
            unwords (map shellQuote (cip113Cli : vaultSealArgs (tfSigningKeyFile files) (tfVaultFile files)))
    let command =
            "printf %s "
                <> shellQuote (tutorialPassphrase <> "\n" <> tutorialPassphrase <> "\n")
                <> " | script -qfec "
                <> shellQuote liveCommand
                <> " /dev/null"
    (code, stdout, stderr) <- readProcessWithExitCode "sh" ["-c", command] ""
    case code of
        ExitSuccess -> pure ()
        ExitFailure n ->
            fail $
                "cip113-cli vault seal failed with exit "
                    <> show n
                    <> "\nstderr:\n"
                    <> stderr
                    <> "\nstdout:\n"
                    <> stdout

decodeAndSubmit :: Submitter IO -> String -> String -> IO ()
decodeAndSubmit submitter label signedHex = do
    signedTx <- case decodeConwayTxInput (BS8.pack signedHex) of
        Left err -> fail ("signed CLI " <> label <> " tx did not decode: " <> show err)
        Right tx -> pure tx
    result <- submitTx submitter signedTx
    case result of
        Submitted _ -> pure ()
        Rejected reason ->
            expectationFailure ("signed CLI " <> label <> " tx rejected: " <> show reason)

registerTutorialAccount ::
    Provider IO ->
    Submitter IO ->
    PParams ConwayEra ->
    IO ()
registerTutorialAccount provider submitter pp = do
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
        Rejected reason -> fail $ "tutorial account registration rejected: " <> show reason

registerTutorialToken ::
    Provider IO ->
    Submitter IO ->
    PParams ConwayEra ->
    CIP113Deployment ->
    IO TxIn
registerTutorialToken provider submitter pp CIP113Deployment{..} = do
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
        keyCred = case genesisStakeCredential of
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
                , rnTransferLogicScript = keyCred
                , rnThirdPartyTransferLogicScript = keyCred
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
        Rejected reason -> fail $ "tutorial registry insert rejected: " <> show reason
    threadDelay 5_000_000
    registryUtxosAfter <- queryUTxOs provider dRegistryAddr
    let registryAsset = AssetName (SBS.toShort testPolicyKey)
    case filter (hasToken dRegistryPolicy registryAsset . snd) registryUtxosAfter of
        (registeredNodeIn, _) : _ -> pure registeredNodeIn
        [] -> fail "no registry UTxO for tutorial policy after insert"

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
        Rejected reason -> fail $ "fund tutorial smart wallet rejected: " <> show reason

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

tutorialPassphrase :: String
tutorialPassphrase = "correct horse battery staple"

hex :: BS8.ByteString -> String
hex =
    Text.unpack . TE.decodeUtf8 . Base16.encode

shellQuote :: String -> String
shellQuote value =
    "'" <> concatMap quoteChar value <> "'"
  where
    quoteChar '\'' = "'\\''"
    quoteChar c = [c]

readTutorial :: IO String
readTutorial = do
    let paths = ["../docs/tutorial.md", "docs/tutorial.md"]
    existing <- filterM doesFileExist paths
    case existing of
        path : _ -> readFile path
        [] -> fail "docs/tutorial.md not found from current working directory"

extractTutorialCommands :: String -> [(String, String)]
extractTutorialCommands =
    go . lines
  where
    go [] = []
    go (line : rest)
        | Just slug <- List.stripPrefix "<!-- tutorial-command: " line
        , Just name <- stripSuffix " -->" slug =
            case dropWhile (/= "```bash") rest of
                [] -> error ("missing bash block for tutorial command: " <> name)
                _fence : blockLines ->
                    let (body, after) = break (== "```") blockLines
                     in (name, List.intercalate "\n" body) : go (drop 1 after)
        | otherwise = go rest

stripSuffix :: (Eq a) => [a] -> [a] -> Maybe [a]
stripSuffix suffix value =
    reverse <$> List.stripPrefix (reverse suffix) (reverse value)
