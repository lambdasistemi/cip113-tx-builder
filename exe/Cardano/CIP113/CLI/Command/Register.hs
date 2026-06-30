{-# LANGUAGE OverloadedStrings #-}

module Cardano.CIP113.CLI.Command.Register (
    Options (..),
    parser,
    run,
) where

import Control.Exception (IOException, displayException, try)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.Char (isHexDigit, ord)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import Numeric (showHex)
import Options.Applicative (
    Parser,
    eitherReader,
    help,
    long,
    metavar,
    option,
    strOption,
 )
import System.Exit (ExitCode (ExitFailure), exitWith)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

import Cardano.CIP113.CLI.Provider (
    UTxO (..),
    UTxOProvider (queryUTxOByRef),
    UTxORef (..),
    UTxOValue (..),
 )
import Cardano.CIP113.CLI.Provider.Offline (
    OfflineUTxOProvider,
    loadOfflineUTxOProvider,
 )

data Options = Options
    { optionsUtxoFile :: !FilePath
    , optionsRegistryUtxo :: !UTxORef
    , optionsTokenName :: !Text
    , optionsPolicyId :: !Text
    }
    deriving (Show, Eq)

parser :: Parser Options
parser =
    Options
        <$> strOption
            ( long "utxo-file"
                <> metavar "FILE"
                <> help "Offline cardano-cli UTxO JSON file"
            )
        <*> option
            (eitherReader parseUTxORefArgument)
            ( long "registry-utxo"
                <> metavar "TXID#IX"
                <> help "Registry UTxO reference to use as the source of truth"
            )
        <*> option
            (eitherReader parseTokenNameArgument)
            ( long "token-name"
                <> metavar "NAME"
                <> help "Registered token name"
            )
        <*> option
            (eitherReader parsePolicyIdArgument)
            ( long "policy-id"
                <> metavar "HEX"
                <> help "56-character registered token policy id"
            )

run :: Bool -> Options -> IO ()
run jsonOutput options = do
    provider <- loadProviderOrExit (optionsUtxoFile options)
    maybeRegistryUtxo <- queryUTxOByRef provider (optionsRegistryUtxo options)
    registryUtxo <-
        case maybeRegistryUtxo of
            Just utxo ->
                pure utxo
            Nothing ->
                dieUser
                    ( "registry UTxO not found in offline file: "
                        <> formatUTxORef (optionsRegistryUtxo options)
                    )
    txHex <- buildRegisterTxHex options registryUtxo
    if jsonOutput
        then putStrLn ("{\"tx\":\"" <> txHex <> "\"}")
        else putStrLn txHex

loadProviderOrExit :: FilePath -> IO OfflineUTxOProvider
loadProviderOrExit path = do
    loaded <- try (loadOfflineUTxOProvider path)
    case loaded of
        Right provider ->
            pure provider
        Left err ->
            dieUser ("failed to load UTxO file: " <> displayException (err :: IOException))

buildRegisterTxHex :: Options -> UTxO -> IO String
buildRegisterTxHex options registryUtxo = do
    lovelace <- registryLovelaceOrExit registryUtxo
    pure
        ( hexEncode
            ( encodeMap
                [ ("lovelace", encodeUnsigned lovelace)
                , ("operation", encodeText "register")
                , ("policy_id", encodeText (optionsPolicyId options))
                , ("registry_utxo", encodeRegistryUtxORef (optionsRegistryUtxo options))
                , ("token_name", encodeText (optionsTokenName options))
                ]
            )
        )

registryLovelaceOrExit :: UTxO -> IO Integer
registryLovelaceOrExit registryUtxo
    | lovelace >= 0 = pure lovelace
    | otherwise = dieUser "registry UTxO has negative lovelace"
  where
    lovelace = utxoLovelace (utxoValue registryUtxo)

parseUTxORefArgument :: String -> Either String UTxORef
parseUTxORefArgument raw =
    case Text.splitOn "#" (Text.pack raw) of
        [txId, indexText] -> do
            validateTxId txId
            index <- parseIndex indexText
            pure
                UTxORef
                    { utxoTxId = Text.toLower txId
                    , utxoIndex = index
                    }
        _ ->
            Left "expected TXID#IX"

validateTxId :: Text -> Either String ()
validateTxId txId
    | Text.length txId /= 64 = Left "TXID must be 64 hex characters"
    | not (Text.all isHexDigit txId) = Left "TXID must be hex"
    | otherwise = Right ()

parseIndex :: Text -> Either String Word
parseIndex indexText
    | Text.null indexText = Left "UTxO index is required"
    | otherwise =
        case readMaybe (Text.unpack indexText) of
            Just index ->
                Right index
            Nothing ->
                Left "UTxO index must be a non-negative decimal integer"

parseTokenNameArgument :: String -> Either String Text
parseTokenNameArgument raw
    | Text.null tokenName = Left "token name must not be empty"
    | otherwise = Right tokenName
  where
    tokenName = Text.pack raw

parsePolicyIdArgument :: String -> Either String Text
parsePolicyIdArgument raw
    | Text.length policyId /= 56 = Left "policy id must be 56 hex characters"
    | not (Text.all isHexDigit policyId) = Left "policy id must be hex"
    | otherwise = Right (Text.toLower policyId)
  where
    policyId = Text.pack raw

formatUTxORef :: UTxORef -> String
formatUTxORef ref =
    Text.unpack (utxoTxId ref) <> "#" <> show (utxoIndex ref)

encodeRegistryUtxORef :: UTxORef -> [Word8]
encodeRegistryUtxORef ref =
    encodeArray
        [ encodeText (utxoTxId ref)
        , encodeUnsigned (toInteger (utxoIndex ref))
        ]

encodeMap :: [(Text, [Word8])] -> [Word8]
encodeMap entries =
    encodeTypeAndLength 5 (toInteger (length entries))
        <> concatMap encodeEntry entries
  where
    encodeEntry (key, value) =
        encodeText key <> value

encodeArray :: [[Word8]] -> [Word8]
encodeArray items =
    encodeTypeAndLength 4 (toInteger (length items))
        <> concat items

encodeText :: Text -> [Word8]
encodeText text =
    encodeTypeAndLength 3 (toInteger (length bytes))
        <> bytes
  where
    bytes = utf8Encode text

encodeUnsigned :: Integer -> [Word8]
encodeUnsigned =
    encodeTypeAndLength 0

encodeTypeAndLength :: Word8 -> Integer -> [Word8]
encodeTypeAndLength major value
    | value < 0 = error "CBOR length cannot be negative"
    | value < 24 = [majorTag .|. fromInteger value]
    | value <= 0xFF = [majorTag .|. 24, fromInteger value]
    | value <= 0xFFFF = (majorTag .|. 25) : integerBytes 2 value
    | value <= 0xFFFFFFFF = (majorTag .|. 26) : integerBytes 4 value
    | value <= 0xFFFFFFFFFFFFFFFF = (majorTag .|. 27) : integerBytes 8 value
    | otherwise = error "CBOR value too large"
  where
    majorTag = major `shiftL` 5

integerBytes :: Int -> Integer -> [Word8]
integerBytes width value =
    [ fromInteger ((value `shiftR` bitOffset) .&. 0xFF)
    | bitOffset <- reverse [0, 8 .. (width * 8 - 8)]
    ]

utf8Encode :: Text -> [Word8]
utf8Encode =
    concatMap encodeChar . Text.unpack

encodeChar :: Char -> [Word8]
encodeChar char
    | code <= 0x7F =
        [fromIntegral code]
    | code <= 0x7FF =
        [ 0xC0 .|. fromIntegral (code `shiftR` 6)
        , 0x80 .|. fromIntegral (code .&. 0x3F)
        ]
    | code <= 0xFFFF =
        [ 0xE0 .|. fromIntegral (code `shiftR` 12)
        , 0x80 .|. fromIntegral ((code `shiftR` 6) .&. 0x3F)
        , 0x80 .|. fromIntegral (code .&. 0x3F)
        ]
    | otherwise =
        [ 0xF0 .|. fromIntegral (code `shiftR` 18)
        , 0x80 .|. fromIntegral ((code `shiftR` 12) .&. 0x3F)
        , 0x80 .|. fromIntegral ((code `shiftR` 6) .&. 0x3F)
        , 0x80 .|. fromIntegral (code .&. 0x3F)
        ]
  where
    code = ord char

hexEncode :: [Word8] -> String
hexEncode =
    concatMap hexByte

hexByte :: Word8 -> String
hexByte byte
    | byte < 16 = '0' : hex
    | otherwise = hex
  where
    hex = showHex byte ""

dieUser :: String -> IO a
dieUser message = do
    hPutStrLn stderr ("register: " <> message)
    exitWith (ExitFailure 1)
