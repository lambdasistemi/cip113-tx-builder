module Cardano.CIP113.CLI.Command.Sign (
    Options (..),
    parser,
    run,
) where

import Cardano.Crypto.Hash.Class (Hash, hashToBytes)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TopTx, TxBody)
import Cardano.Ledger.Hashes (EraIndependentTxBody, HASH, extractHash, hashAnnotated)
import Cardano.Tx.Ledger (ConwayTx)
import Cardano.Tx.Sign.AttachWitness qualified as Structured
import Cardano.Wallet.Tools.Cli.Vault (
    SigningKeySource,
    loadSignerFromSource,
    signingKeySourceParser,
 )
import Cardano.Wallet.Tools.Sign (
    TxBodyBytes (..),
 )
import Cardano.Wallet.Tools.Sign qualified as WalletSign
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as B16
import Data.Set qualified as Set
import Lens.Micro ((^.))
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
    txHex <- readCborHexInput
    writeCborHexInput =<< attachStructured signer txHex

attachStructured :: WalletSign.Signer IO -> ByteString -> IO ByteString
attachStructured signer txHex = do
    tx <-
        either (die . ("cannot decode unsigned tx: " <>) . show) pure $
            Structured.decodeUnsignedTxHex txHex
    witness <- WalletSign.signTxBody signer (TxBodyBytes (bodyHashBytes tx))
    ledgerWitness <-
        either (die . ("cannot decode structured witness: " <>) . show) pure $
            Structured.decodeVKeyWitnessHex
                1
                (B16.encode (WalletSign.encodeDetachedWitness witness))
    pure $
        Structured.encodeSignedTxHex $
            Structured.attachWitnesses (Set.singleton ledgerWitness) tx

bodyHashBytes :: ConwayTx -> ByteString
bodyHashBytes tx =
    hashToBytes bodyHash
  where
    body :: TxBody TopTx ConwayEra
    body = tx ^. bodyTxL

    bodyHash :: Hash HASH EraIndependentTxBody
    bodyHash = extractHash (hashAnnotated body)

readCborHexInput :: IO ByteString
readCborHexInput =
    stripPipeWhitespace <$> BS.getContents

writeCborHexInput :: ByteString -> IO ()
writeCborHexInput =
    BS.putStr

stripPipeWhitespace :: ByteString -> ByteString
stripPipeWhitespace =
    BS.dropWhileEnd (\c -> c == 10 || c == 13 || c == 32)

die :: String -> IO a
die message = do
    hPutStrLn stderr message
    exitFailure
