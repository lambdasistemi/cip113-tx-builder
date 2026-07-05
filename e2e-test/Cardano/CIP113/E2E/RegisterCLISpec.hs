{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.E2E.RegisterCLISpec (spec) where

import Cardano.Crypto.DSIGN.Class (rawSerialiseSignKeyDSIGN)
import Cardano.Ledger.Address (serialiseAddr)
import Cardano.Ledger.Mary.Value (PolicyID (..))
import Cardano.Node.Client.E2E.Setup (
    genesisAddr,
    genesisSignKey,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (submitTx))
import Cardano.Tx.Diff (decodeConwayTxInput)
import Control.Monad (unless)
import Data.Aeson qualified as Aeson
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BSL
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec

import Cardano.CIP113.E2E.Deploy (
    CIP113Deployment (..),
    deployCIP113,
    withCIP113DevnetSocket,
 )
import Cardano.CIP113.Scripts (loadBlueprint, scriptHashBytes)

spec :: Spec
spec =
    describe "CIP-113 register CLI subprocess smoke" $
        it
            "builds, signs, decodes, submits, and accepts a real register transaction"
            runSmoke

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

        withSystemTempDirectory "cip113-cli-register-smoke" $ \tmpDir -> do
            let deploymentFile = tmpDir </> "deployment.json"
                signingKeyFile = tmpDir </> "genesis.skey"
                changeAddressHex = hex (serialiseAddr genesisAddr)
                policyIdHex = case dIssuancePolicy of
                    PolicyID h -> hex (scriptHashBytes h)
            BSL.writeFile deploymentFile (Aeson.encode deployment)
            BSL.writeFile signingKeyFile genesisSigningKeyTextEnvelope

            unsignedHex <-
                runCli
                    "register"
                    cip113Cli
                    [ "--socket-path"
                    , socketPath
                    , "--network-magic"
                    , "42"
                    , "register"
                    , "--deployment"
                    , deploymentFile
                    , "--change-address"
                    , changeAddressHex
                    , "--token-name"
                    , "cli-smoke"
                    , "--policy-id"
                    , policyIdHex
                    ]
                    ""
            signedHex <-
                runCli
                    "sign"
                    cip113Cli
                    [ "sign"
                    , "--signing-key"
                    , signingKeyFile
                    ]
                    unsignedHex
            signedTx <- case decodeConwayTxInput (BS8.pack signedHex) of
                Left err -> fail ("signed CLI tx did not decode: " <> show err)
                Right tx -> pure tx
            result <- submitTx submitter signedTx
            case result of
                Submitted _ -> pure ()
                Rejected reason ->
                    expectationFailure ("signed CLI register tx rejected: " <> show reason)

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
