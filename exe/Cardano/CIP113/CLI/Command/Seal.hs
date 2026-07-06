module Cardano.CIP113.CLI.Command.Seal (
    Options (..),
    parser,
    run,
) where

import Cardano.Wallet.Tools.Cli.Vault (promptPassphrase)
import Cardano.Wallet.Tools.Vault (
    defaultWorkFactor,
    encryptVault,
    mkVaultPassphrase,
    renderVaultError,
 )
import Control.Monad (when)
import Data.ByteString qualified as BS
import Data.Text qualified as Text
import OptEnvConf (
    Parser,
    help,
    metavar,
    name,
    reader,
    setting,
    str,
 )
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

data Options = Options
    { optionsSigningKey :: !FilePath
    , optionsOut :: !FilePath
    }
    deriving (Show, Eq)

parser :: Parser Options
parser =
    Options
        <$> setting
            [ name "signing-key"
            , reader str
            , metavar "FILE"
            , help "Plaintext .skey TextEnvelope to encrypt"
            ]
        <*> setting
            [ name "out"
            , reader str
            , metavar "FILE"
            , help "Output .age vault file"
            ]

run :: Options -> IO ()
run options = do
    keyBytes <- BS.readFile (optionsSigningKey options)
    passphrase <- promptPassphrase "vault passphrase: "
    confirmation <- promptPassphrase "confirm passphrase: "
    when (passphrase /= confirmation) $
        die "passphrases do not match"
    vaultPassphrase <-
        either (die . Text.unpack . renderVaultError) pure $
            mkVaultPassphrase passphrase
    ciphertext <-
        encryptVault defaultWorkFactor vaultPassphrase keyBytes
            >>= either (die . Text.unpack . renderVaultError) pure
    BS.writeFile (optionsOut options) ciphertext

die :: String -> IO a
die message = do
    hPutStrLn stderr message
    exitFailure
