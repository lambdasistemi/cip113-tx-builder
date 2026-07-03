module Cardano.CIP113.CLI.Command.Sign (
    Options (..),
    parser,
    run,
) where

import Cardano.Wallet.Tools.Cli.Vault (
    SigningKeySource,
    loadSignerFromSource,
    signingKeySourceParser,
 )
import Cardano.Wallet.Tools.Sign (
    attachWitnesses,
    signTxBody,
    transactionBodyBytes,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as B16
import Options.Applicative (Parser)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

newtype Options = Options
    { optionsSigningKeySource :: SigningKeySource
    }

parser :: Parser Options
parser =
    Options <$> signingKeySourceParser

run :: Options -> IO ()
run options = do
    signer <- loadSignerFromSource (optionsSigningKeySource options)
    txBytes <- readCborHex
    body <-
        either (die . ("cannot extract tx body: " <>) . show) pure $
            transactionBodyBytes txBytes
    witness <- signTxBody signer body
    signedTx <-
        either (die . ("cannot attach witness: " <>) . show) pure $
            attachWitnesses [witness] txBytes
    writeCborHex signedTx

readCborHex :: IO ByteString
readCborHex = do
    input <- stripPipeWhitespace <$> BS.getContents
    either (die . ("invalid CBOR hex: " <>)) pure $
        B16.decode input

writeCborHex :: ByteString -> IO ()
writeCborHex =
    BS.putStr . B16.encode

stripPipeWhitespace :: ByteString -> ByteString
stripPipeWhitespace =
    BS.dropWhileEnd (\c -> c == 10 || c == 13 || c == 32)

die :: String -> IO a
die message = do
    hPutStrLn stderr message
    exitFailure
