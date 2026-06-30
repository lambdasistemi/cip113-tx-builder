module Main (main) where

import Options.Applicative (
    Parser,
    ParserInfo,
    command,
    customExecParser,
    fullDesc,
    header,
    help,
    helper,
    hsubparser,
    info,
    long,
    prefs,
    progDesc,
    showHelpOnError,
    switch,
    (<**>),
 )

import Cardano.CIP113.CLI.Command.Freeze qualified as Freeze
import Cardano.CIP113.CLI.Command.Register qualified as Register
import Cardano.CIP113.CLI.Command.Seize qualified as Seize
import Cardano.CIP113.CLI.Command.Transfer qualified as Transfer

-- Exit codes:
--   0 success
--   1 user error
--   2 unimplemented/internal

data CliOptions = CliOptions
    { cliJson :: !Bool
    , cliCommand :: !Command
    }

data Command
    = Register !Register.Options
    | Transfer !Transfer.Options
    | Freeze !Freeze.Options
    | Seize !Seize.Options

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
        <*> hsubparser
            ( command
                "register"
                (info (Register <$> Register.parser) (progDesc "Register a CIP-113 policy"))
                <> command
                    "transfer"
                    (info (Transfer <$> Transfer.parser) (progDesc "Transfer CIP-113 tokens"))
                <> command
                    "freeze"
                    (info (Freeze <$> Freeze.parser) (progDesc "Freeze CIP-113 tokens"))
                <> command
                    "seize"
                    (info (Seize <$> Seize.parser) (progDesc "Seize CIP-113 tokens"))
            )

runCli :: CliOptions -> IO ()
runCli options =
    case cliCommand options of
        Register registerOptions ->
            Register.run (cliJson options) registerOptions
        Transfer transferOptions ->
            Transfer.run (cliJson options) transferOptions
        Freeze freezeOptions ->
            Freeze.run (cliJson options) freezeOptions
        Seize seizeOptions ->
            Seize.run (cliJson options) seizeOptions
