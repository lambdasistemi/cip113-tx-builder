{-# LANGUAGE RankNTypes #-}

module Main (main) where

import Control.Applicative (optional, (<|>))
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
import Cardano.CIP113.CLI.Command.Seize qualified as Seize
import Cardano.CIP113.CLI.Command.Transfer qualified as Transfer
import Cardano.CIP113.CLI.Provider (UTxOProvider)
import Cardano.CIP113.CLI.Provider.Blockfrost (
    BlockfrostProviderConfig (..),
    withBlockfrostProvider,
 )
import Cardano.CIP113.CLI.Provider.Kupo (
    KupoProviderConfig (..),
    withKupoProvider,
 )
import Cardano.CIP113.CLI.Provider.Node (
    NodeProviderConfig (..),
    withNodeProvider,
 )

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

data ProviderOptions = ProviderOptions
    { providerSocketPath :: !(Maybe FilePath)
    , providerNetworkMagic :: !(Maybe Word32)
    , providerBlockfrostProjectId :: !(Maybe Text)
    , providerKupoUrl :: !(Maybe Text)
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

runCli :: CliOptions -> IO ()
runCli options =
    case cliCommand options of
        Register commandProviderOptions registerOptions ->
            runWithSelectedProvider
                options
                commandProviderOptions
                Register.run
                Register.runWithProvider
                registerOptions
        Transfer commandProviderOptions transferOptions ->
            runWithSelectedProvider
                options
                commandProviderOptions
                Transfer.run
                Transfer.runWithProvider
                transferOptions
        Freeze commandProviderOptions freezeOptions ->
            runWithSelectedProvider
                options
                commandProviderOptions
                Freeze.run
                Freeze.runWithProvider
                freezeOptions
        Seize commandProviderOptions seizeOptions ->
            runWithSelectedProvider
                options
                commandProviderOptions
                Seize.run
                Seize.runWithProvider
                seizeOptions

runWithSelectedProvider ::
    CliOptions ->
    ProviderOptions ->
    (Bool -> commandOptions -> IO ()) ->
    (forall provider. (UTxOProvider provider) => provider -> Bool -> commandOptions -> IO ()) ->
    commandOptions ->
    IO ()
runWithSelectedProvider
    cliOptions
    commandProviderOptions
    runOffline
    runNode
    commandOptions =
        case selectProviderConfig cliOptions commandProviderOptions of
            UseOfflineProvider ->
                runOffline (cliJson cliOptions) commandOptions
            UseNodeProvider nodeConfig ->
                withNodeProvider nodeConfig $ \provider ->
                    runNode provider (cliJson cliOptions) commandOptions
            UseBlockfrostProvider blockfrostConfig ->
                withBlockfrostProvider blockfrostConfig $ \provider ->
                    runNode provider (cliJson cliOptions) commandOptions
            UseKupoProvider kupoConfig ->
                withKupoProvider kupoConfig $ \provider ->
                    runNode provider (cliJson cliOptions) commandOptions
            InvalidNodeProvider ->
                dieUser
                    "node provider requires both --socket-path and --network-magic"

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
