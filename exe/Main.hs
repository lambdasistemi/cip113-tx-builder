{-# LANGUAGE NamedFieldPuns #-}

module Main (main) where

import Cardano.CIP113.CLI.Command.Freeze qualified as Freeze
import Cardano.CIP113.CLI.Command.Register qualified as Register
import Cardano.CIP113.CLI.Command.Seal qualified as Seal
import Cardano.CIP113.CLI.Command.Seize qualified as Seize
import Cardano.CIP113.CLI.Command.Sign qualified as Sign
import Cardano.CIP113.CLI.Command.Transfer qualified as Transfer
import Cardano.CIP113.CLI.Provider.Node (
    NodeProviderConfig (..),
 )
import Cardano.CIP113.CLI.Settings (
    addressTextSetting,
    changeAddressSetting,
    deploymentSetting,
    nodeConnectionSetting,
    policyIdSetting,
    positiveAmountSetting,
    tokenNameSetting,
    utxoFileSetting,
 )
import Cardano.CIP113.Deployment (CIP113Deployment)
import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.Provider qualified as Node
import Control.Applicative (optional)
import Control.Concurrent.Async (withAsync)
import Control.Monad (void)
import OptEnvConf (
    Parser,
    command,
    commands,
    help,
    long,
    runParser,
    setting,
    subEnv,
    switch,
    value,
    withConfigurableYamlConfig,
    xdgYamlConfigFile,
 )
import Ouroboros.Network.Magic (NetworkMagic (..))
import Paths_cip113_tx_builder (version)
import System.Directory (doesPathExist)
import System.Exit (ExitCode (ExitFailure), exitWith)
import System.IO (hPutStrLn, stderr)

-- Exit codes:
--   0 success
--   1 user error
--   2 unimplemented/internal

data CliOptions = CliOptions
    { cliJson :: !Bool
    , cliCommand :: !Command
    }

data Command
    = Register !RealTxSettings !Register.Options
    | Transfer !RealTxSettings !Transfer.Options
    | Freeze !RealTxSettings !Freeze.Options
    | Seize !RealTxSettings !Seize.Options
    | Sign !Sign.Options
    | Seal !Seal.Options

data RealTxSettings = RealTxSettings
    { realDeployment :: !CIP113Deployment
    , realNodeConfig :: !NodeProviderConfig
    }

main :: IO ()
main =
    runCli
        =<< runParser
            version
            "Build unsigned CIP-113 transaction bodies"
            parser

parser :: Parser CliOptions
parser =
    subEnv "CIP113_" $
        withConfigurableYamlConfig (xdgYamlConfigFile "cip113-cli") $
            CliOptions
                <$> setting
                    [ long "json"
                    , switch True
                    , value False
                    , help "Emit machine-readable JSON output"
                    ]
                <*> commandParser

commandParser :: Parser Command
commandParser =
    commands
        [ command "register" "Register a CIP-113 policy" $
            Register <$> realTxSettingsParser <*> Register.parser
        , command "transfer" "Transfer CIP-113 tokens" $
            Transfer <$> realTxSettingsParser <*> transferOptionsParser
        , command "freeze" "Freeze CIP-113 tokens" $
            Freeze <$> realTxSettingsParser <*> freezeOptionsParser
        , command "seize" "Seize CIP-113 tokens" $
            Seize <$> realTxSettingsParser <*> seizeOptionsParser
        , command "sign" signHelp $
            Sign <$> Sign.parser
        , command "vault" "Manage age-encrypted signing key vaults" vaultParser
        ]

vaultParser :: Parser Command
vaultParser =
    commands
        [ command "seal" "Encrypt a signing key into an age scrypt vault" $
            Seal <$> Seal.parser
        ]

signHelp :: String
signHelp =
    "Attach a vkey witness to a tx body (CBOR hex stdin to stdout)"

realTxSettingsParser :: Parser RealTxSettings
realTxSettingsParser =
    RealTxSettings
        <$> deploymentSetting
        <*> nodeConnectionSetting

transferOptionsParser :: Parser Transfer.Options
transferOptionsParser =
    Transfer.Options
        <$> utxoFileSetting
        <*> addressTextSetting "from-address" "Sender address"
        <*> addressTextSetting "to-address" "Recipient address"
        <*> tokenNameSetting
        <*> policyIdSetting
        <*> positiveAmountSetting
        <*> optional changeAddressSetting

freezeOptionsParser :: Parser Freeze.Options
freezeOptionsParser =
    Freeze.Options
        <$> utxoFileSetting
        <*> addressTextSetting "target-address" "Target address"
        <*> tokenNameSetting
        <*> policyIdSetting
        <*> optional changeAddressSetting

seizeOptionsParser :: Parser Seize.Options
seizeOptionsParser =
    Seize.Options
        <$> utxoFileSetting
        <*> addressTextSetting "target-address" "Target address"
        <*> addressTextSetting "to-address" "Destination address"
        <*> tokenNameSetting
        <*> policyIdSetting
        <*> optional changeAddressSetting

runCli :: CliOptions -> IO ()
runCli CliOptions{cliJson, cliCommand} =
    case cliCommand of
        Register realTxSettings registerOptions ->
            runRegister cliJson realTxSettings registerOptions
        Transfer realTxSettings transferOptions ->
            runTransfer cliJson realTxSettings transferOptions
        Freeze realTxSettings freezeOptions ->
            runFreeze cliJson realTxSettings freezeOptions
        Seize realTxSettings seizeOptions ->
            runSeize cliJson realTxSettings seizeOptions
        Sign signOptions ->
            Sign.run signOptions
        Seal sealOptions ->
            Seal.run sealOptions

runRegister :: Bool -> RealTxSettings -> Register.Options -> IO ()
runRegister jsonOutput RealTxSettings{realDeployment, realNodeConfig} options =
    withRegisterNodeProvider realNodeConfig $ \provider ->
        Register.runWithNodeProvider
            realDeployment
            provider
            jsonOutput
            options

runTransfer :: Bool -> RealTxSettings -> Transfer.Options -> IO ()
runTransfer jsonOutput RealTxSettings{realDeployment, realNodeConfig} options =
    withRegisterNodeProvider realNodeConfig $ \provider ->
        Transfer.runWithNodeProvider
            realDeployment
            provider
            jsonOutput
            options

runFreeze :: Bool -> RealTxSettings -> Freeze.Options -> IO ()
runFreeze jsonOutput RealTxSettings{realDeployment, realNodeConfig} options =
    withRegisterNodeProvider realNodeConfig $ \provider ->
        Freeze.runWithNodeProvider
            realDeployment
            provider
            jsonOutput
            options

runSeize :: Bool -> RealTxSettings -> Seize.Options -> IO ()
runSeize jsonOutput RealTxSettings{realDeployment, realNodeConfig} options =
    withRegisterNodeProvider realNodeConfig $ \provider ->
        Seize.runWithNodeProvider
            realDeployment
            provider
            jsonOutput
            options

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
        else dieUser ("node socket path does not exist: " <> nodeSocketPath)

dieUser :: String -> IO a
dieUser message = do
    hPutStrLn stderr ("cip113-cli: " <> message)
    exitWith (ExitFailure 1)
