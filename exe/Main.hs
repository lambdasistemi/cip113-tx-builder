{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}

module Main (main) where

import Control.Applicative (optional, (<|>))
import Control.Concurrent.Async (withAsync)
import Control.Exception (IOException, displayException, try)
import Control.Monad (void)
import Data.Aeson qualified as Aeson
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32)
import Options.Applicative (
    Parser,
    ParserInfo,
    auto,
    command,
    customExecParser,
    fullDesc,
    header,
    help,
    helper,
    hsubparser,
    info,
    long,
    option,
    prefs,
    progDesc,
    showHelpOnError,
    strOption,
    switch,
    (<**>),
 )
import System.Exit (ExitCode (ExitFailure), exitWith)
import System.IO (hPutStrLn, stderr)

import Cardano.CIP113.CLI.Command.Freeze qualified as Freeze
import Cardano.CIP113.CLI.Command.Register qualified as Register
import Cardano.CIP113.CLI.Command.Seal qualified as Seal
import Cardano.CIP113.CLI.Command.Seize qualified as Seize
import Cardano.CIP113.CLI.Command.Sign qualified as Sign
import Cardano.CIP113.CLI.Command.Transfer qualified as Transfer
import Cardano.CIP113.CLI.Provider.Blockfrost (
    BlockfrostProviderConfig (..),
 )
import Cardano.CIP113.CLI.Provider.Kupo (
    KupoProviderConfig (..),
 )
import Cardano.CIP113.CLI.Provider.Node (
    NodeProviderConfig (..),
 )
import Cardano.CIP113.Deployment (CIP113Deployment)
import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.Provider qualified as Node
import Ouroboros.Network.Magic (NetworkMagic (..))
import System.Directory (doesPathExist)

-- Exit codes:
--   0 success
--   1 user error
--   2 unimplemented/internal

data CliOptions = CliOptions
    { cliJson :: !Bool
    , cliProviderOptions :: !ProviderOptions
    , cliCommand :: !Command
    }

data Command
    = Register !ProviderOptions !Register.Options
    | Transfer !ProviderOptions !Transfer.Options
    | Freeze !ProviderOptions !Freeze.Options
    | Seize !ProviderOptions !Seize.Options
    | Sign !Sign.Options
    | Seal !Seal.Options

data ProviderOptions = ProviderOptions
    { providerSocketPath :: !(Maybe FilePath)
    , providerNetworkMagic :: !(Maybe Word32)
    , providerBlockfrostProjectId :: !(Maybe Text)
    , providerKupoUrl :: !(Maybe Text)
    , providerDeploymentPath :: !(Maybe FilePath)
    }

main :: IO ()
main = do
    options <- customExecParser (prefs showHelpOnError) cliInfo
    runCli options

cliInfo :: ParserInfo CliOptions
cliInfo =
    info
        (cliParser <**> helper)
        ( fullDesc
            <> progDesc "Build unsigned CIP-113 transaction bodies"
            <> header "cip113-cli"
        )

cliParser :: Parser CliOptions
cliParser =
    CliOptions
        <$> switch
            ( long "json"
                <> help "Emit machine-readable JSON output"
            )
        <*> providerOptionsParser
        <*> hsubparser
            ( command
                "register"
                ( info
                    (Register <$> providerOptionsParser <*> Register.parser)
                    (progDesc "Register a CIP-113 policy")
                )
                <> command
                    "transfer"
                    ( info
                        (Transfer <$> providerOptionsParser <*> Transfer.parser)
                        (progDesc "Transfer CIP-113 tokens")
                    )
                <> command
                    "freeze"
                    ( info
                        (Freeze <$> providerOptionsParser <*> Freeze.parser)
                        (progDesc "Freeze CIP-113 tokens")
                    )
                <> command
                    "seize"
                    ( info
                        (Seize <$> providerOptionsParser <*> Seize.parser)
                        (progDesc "Seize CIP-113 tokens")
                    )
                <> command
                    "sign"
                    ( info
                        (Sign <$> Sign.parser)
                        ( progDesc
                            "Attach a vkey witness to a tx body (CBOR hex stdin to stdout)"
                        )
                    )
                <> command
                    "vault"
                    ( info
                        vaultParser
                        (progDesc "Manage age-encrypted signing key vaults")
                    )
            )

vaultParser :: Parser Command
vaultParser =
    hsubparser
        ( command
            "seal"
            ( info
                (Seal <$> Seal.parser)
                (progDesc "Encrypt a signing key into an age scrypt vault")
            )
        )

providerOptionsParser :: Parser ProviderOptions
providerOptionsParser =
    ProviderOptions
        <$> optional
            ( strOption
                ( long "socket-path"
                    <> help "Cardano node socket path"
                )
            )
        <*> optional
            ( option
                auto
                ( long "network-magic"
                    <> help "Cardano network magic"
                )
            )
        <*> optional
            ( Text.pack
                <$> strOption
                    ( long "blockfrost-project-id"
                        <> help "Blockfrost project id"
                    )
            )
        <*> optional
            ( Text.pack
                <$> strOption
                    ( long "kupo-url"
                        <> help "Kupo base URL"
                    )
            )
        <*> optional
            ( strOption
                ( long "deployment"
                    <> help "CIP-113 deployment descriptor JSON file"
                )
            )

runCli :: CliOptions -> IO ()
runCli options =
    case cliCommand options of
        Register commandProviderOptions registerOptions ->
            runRegister options commandProviderOptions registerOptions
        Transfer commandProviderOptions transferOptions ->
            runTransfer options commandProviderOptions transferOptions
        Freeze commandProviderOptions freezeOptions ->
            runFreeze options commandProviderOptions freezeOptions
        Seize commandProviderOptions seizeOptions ->
            runSeize options commandProviderOptions seizeOptions
        Sign signOptions ->
            Sign.run signOptions
        Seal sealOptions ->
            Seal.run sealOptions

runRegister :: CliOptions -> ProviderOptions -> Register.Options -> IO ()
runRegister cliOptions commandProviderOptions registerOptions = do
    maybeDeployment <- loadSelectedDeployment cliOptions commandProviderOptions
    deployment <-
        case maybeDeployment of
            Just deployment ->
                pure deployment
            Nothing ->
                dieUser "register requires --deployment FILE"
    case selectProviderConfig cliOptions commandProviderOptions of
        UseNodeProvider nodeConfig ->
            withRegisterNodeProvider nodeConfig $ \provider ->
                Register.runWithNodeProvider
                    deployment
                    provider
                    (cliJson cliOptions)
                    registerOptions
        UseOfflineProvider ->
            dieUser registerRequiresNodeMessage
        UseBlockfrostProvider _ ->
            dieUser registerRequiresNodeMessage
        UseKupoProvider _ ->
            dieUser registerRequiresNodeMessage
        InvalidNodeProvider ->
            dieUser "node provider requires both --socket-path and --network-magic"

runTransfer :: CliOptions -> ProviderOptions -> Transfer.Options -> IO ()
runTransfer cliOptions commandProviderOptions transferOptions = do
    maybeDeployment <- loadSelectedDeployment cliOptions commandProviderOptions
    deployment <-
        case maybeDeployment of
            Just deployment ->
                pure deployment
            Nothing ->
                dieUser "transfer requires --deployment FILE"
    case selectProviderConfig cliOptions commandProviderOptions of
        UseNodeProvider nodeConfig ->
            withRegisterNodeProvider nodeConfig $ \provider ->
                Transfer.runWithNodeProvider
                    deployment
                    provider
                    (cliJson cliOptions)
                    transferOptions
        UseOfflineProvider ->
            dieUser transferRequiresNodeMessage
        UseBlockfrostProvider _ ->
            dieUser transferRequiresNodeMessage
        UseKupoProvider _ ->
            dieUser transferRequiresNodeMessage
        InvalidNodeProvider ->
            dieUser "node provider requires both --socket-path and --network-magic"

runFreeze :: CliOptions -> ProviderOptions -> Freeze.Options -> IO ()
runFreeze cliOptions commandProviderOptions freezeOptions = do
    maybeDeployment <- loadSelectedDeployment cliOptions commandProviderOptions
    deployment <-
        case maybeDeployment of
            Just deployment ->
                pure deployment
            Nothing ->
                dieUser "freeze requires --deployment FILE"
    case selectProviderConfig cliOptions commandProviderOptions of
        UseNodeProvider nodeConfig ->
            withRegisterNodeProvider nodeConfig $ \provider ->
                Freeze.runWithNodeProvider
                    deployment
                    provider
                    (cliJson cliOptions)
                    freezeOptions
        UseOfflineProvider ->
            dieUser freezeRequiresNodeMessage
        UseBlockfrostProvider _ ->
            dieUser freezeRequiresNodeMessage
        UseKupoProvider _ ->
            dieUser freezeRequiresNodeMessage
        InvalidNodeProvider ->
            dieUser "node provider requires both --socket-path and --network-magic"

runSeize :: CliOptions -> ProviderOptions -> Seize.Options -> IO ()
runSeize cliOptions commandProviderOptions seizeOptions = do
    maybeDeployment <- loadSelectedDeployment cliOptions commandProviderOptions
    deployment <-
        case maybeDeployment of
            Just deployment ->
                pure deployment
            Nothing ->
                dieUser "seize requires --deployment FILE"
    case selectProviderConfig cliOptions commandProviderOptions of
        UseNodeProvider nodeConfig ->
            withRegisterNodeProvider nodeConfig $ \provider ->
                Seize.runWithNodeProvider
                    deployment
                    provider
                    (cliJson cliOptions)
                    seizeOptions
        UseOfflineProvider ->
            dieUser seizeRequiresNodeMessage
        UseBlockfrostProvider _ ->
            dieUser seizeRequiresNodeMessage
        UseKupoProvider _ ->
            dieUser seizeRequiresNodeMessage
        InvalidNodeProvider ->
            dieUser "node provider requires both --socket-path and --network-magic"

loadSelectedDeployment :: CliOptions -> ProviderOptions -> IO (Maybe CIP113Deployment)
loadSelectedDeployment cliOptions commandProviderOptions =
    case deploymentPath of
        Nothing ->
            pure Nothing
        Just path -> do
            loaded <-
                try
                    ( Aeson.eitherDecodeFileStrict' path ::
                        IO (Either String CIP113Deployment)
                    )
            case loaded of
                Left err ->
                    dieUser
                        ( "failed to read deployment file "
                            <> show path
                            <> ": "
                            <> displayException (err :: IOException)
                        )
                Right (Left err) ->
                    dieUser
                        ( "failed to decode deployment file "
                            <> show path
                            <> ": "
                            <> err
                        )
                Right (Right deployment) ->
                    deployment `seq` pure (Just deployment)
  where
    globalProviderOptions = cliProviderOptions cliOptions
    deploymentPath =
        providerDeploymentPath commandProviderOptions
            <|> providerDeploymentPath globalProviderOptions

withRegisterNodeProvider ::
    NodeProviderConfig ->
    (Node.Provider IO -> IO a) ->
    IO a
withRegisterNodeProvider NodeProviderConfig{nodeSocketPath, nodeNetworkMagic} k = do
    socketExists <- doesPathExist nodeSocketPath
    if socketExists
        then do
            lsqCh <- newLSQChannel 64
            ltxsCh <- newLTxSChannel 64
            withAsync
                ( void $
                    runNodeClient
                        (NetworkMagic nodeNetworkMagic)
                        nodeSocketPath
                        lsqCh
                        ltxsCh
                )
                $ \_ ->
                    k (mkN2CProvider lsqCh)
        else fail ("node socket path does not exist: " <> nodeSocketPath)

registerRequiresNodeMessage :: String
registerRequiresNodeMessage =
    "real register transaction building currently requires the node backend"

transferRequiresNodeMessage :: String
transferRequiresNodeMessage =
    "real transfer transaction building currently requires the node backend"

freezeRequiresNodeMessage :: String
freezeRequiresNodeMessage =
    "real freeze transaction building currently requires the node backend"

seizeRequiresNodeMessage :: String
seizeRequiresNodeMessage =
    "real seize transaction building currently requires the node backend"

data SelectedProvider
    = UseOfflineProvider
    | UseNodeProvider !NodeProviderConfig
    | UseBlockfrostProvider !BlockfrostProviderConfig
    | UseKupoProvider !KupoProviderConfig
    | InvalidNodeProvider

selectProviderConfig :: CliOptions -> ProviderOptions -> SelectedProvider
selectProviderConfig cliOptions commandProviderOptions =
    case (socketPath, networkMagic) of
        (Nothing, Nothing) ->
            case blockfrostProjectId of
                Just projectId ->
                    UseBlockfrostProvider
                        BlockfrostProviderConfig
                            { blockfrostProjectId = projectId
                            }
                Nothing ->
                    case kupoUrl of
                        Just url ->
                            UseKupoProvider
                                KupoProviderConfig
                                    { kupoBaseUrl = url
                                    }
                        Nothing ->
                            UseOfflineProvider
        (Just path, Just magic) ->
            UseNodeProvider
                NodeProviderConfig
                    { nodeSocketPath = path
                    , nodeNetworkMagic = magic
                    }
        _ ->
            InvalidNodeProvider
  where
    globalProviderOptions = cliProviderOptions cliOptions
    socketPath =
        providerSocketPath commandProviderOptions
            <|> providerSocketPath globalProviderOptions
    networkMagic =
        providerNetworkMagic commandProviderOptions
            <|> providerNetworkMagic globalProviderOptions
    blockfrostProjectId =
        providerBlockfrostProjectId commandProviderOptions
            <|> providerBlockfrostProjectId globalProviderOptions
    kupoUrl =
        providerKupoUrl commandProviderOptions
            <|> providerKupoUrl globalProviderOptions

dieUser :: String -> IO a
dieUser message = do
    hPutStrLn stderr ("cip113-cli: " <> message)
    exitWith (ExitFailure 1)
