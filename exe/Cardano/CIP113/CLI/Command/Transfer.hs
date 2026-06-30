{-# LANGUAGE OverloadedStrings #-}

module Cardano.CIP113.CLI.Command.Transfer (
    Options (..),
    parser,
    run,
    runWithProvider,
) where

import Control.Applicative (optional)
import Control.Exception (IOException, displayException, try)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.Char (isHexDigit, ord)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
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
    UTxOProvider (queryUTxOsByAddress),
    UTxORef (..),
    UTxOValue (..),
 )
import Cardano.CIP113.CLI.Provider.Offline (
    OfflineUTxOProvider,
    loadOfflineUTxOProvider,
 )

data Options = Options
    { optionsUtxoFile :: !(Maybe FilePath)
    , optionsFromAddress :: !Text
    , optionsToAddress :: !Text
    , optionsTokenName :: !Text
    , optionsPolicyId :: !Text
    , optionsAmount :: !Integer
    }
    deriving (Show, Eq)

parser :: Parser Options
parser =
    Options
        <$> optional
            ( strOption
                ( long "utxo-file"
                    <> metavar "FILE"
                    <> help "Offline cardano-cli UTxO JSON file"
                )
            )
        <*> option
            (eitherReader parseAddressArgument)
            ( long "from-address"
                <> metavar "ADDR"
                <> help "Sender address"
            )
        <*> option
            (eitherReader parseAddressArgument)
            ( long "to-address"
                <> metavar "ADDR"
                <> help "Recipient address"
            )
        <*> option
            (eitherReader parseTokenNameArgument)
            ( long "token-name"
                <> metavar "NAME"
                <> help "Token name"
            )
        <*> option
            (eitherReader parsePolicyIdArgument)
            ( long "policy-id"
                <> metavar "HEX"
                <> help "56-character token policy id"
            )
        <*> option
            (eitherReader parseAmountArgument)
            ( long "amount"
                <> metavar "INT"
                <> help "Positive token amount to transfer"
            )

run :: Bool -> Options -> IO ()
run jsonOutput options = do
    provider <-
        case optionsUtxoFile options of
            Just path ->
                loadProviderOrExit path
            Nothing ->
                dieUser "offline mode requires --utxo-file"
    runWithProvider provider jsonOutput options

runWithProvider :: (UTxOProvider provider) => provider -> Bool -> Options -> IO ()
runWithProvider provider jsonOutput options = do
    senderUtxOs <- queryUTxOsByAddress provider (optionsFromAddress options)
    selectedUtxOs <- selectTransferInputs options senderUtxOs
    let txHex = buildTransferTxHex options selectedUtxOs
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

selectTransferInputs :: Options -> [UTxO] -> IO [UTxO]
selectTransferInputs options senderUtxOs = do
    case matchingUtxOs of
        [] ->
            dieUser "no UTxOs carry the requested token"
        _
            | totalAvailable < requiredAmount ->
                dieUser
                    ( "insufficient token balance: available "
                        <> show totalAvailable
                        <> ", required "
                        <> show requiredAmount
                    )
        _ ->
            pure (fst <$> takeUntilAtLeast requiredAmount matchingUtxOs)
  where
    requiredAmount = optionsAmount options
    matchingUtxOs =
        [ (utxo, amount)
        | utxo <- senderUtxOs
        , let amount = matchingAssetAmount options utxo
        , amount > 0
        ]
    totalAvailable =
        sum (snd <$> matchingUtxOs)

takeUntilAtLeast :: Integer -> [(UTxO, Integer)] -> [(UTxO, Integer)]
takeUntilAtLeast required =
    go 0 []
  where
    go _ selected [] =
        reverse selected
    go total selected (utxoWithAmount@(_, amount) : rest)
        | total >= required =
            reverse selected
        | otherwise =
            go (total + amount) (utxoWithAmount : selected) rest

matchingAssetAmount :: Options -> UTxO -> Integer
matchingAssetAmount options utxo =
    assetAmount
        (utxoAssets (utxoValue utxo))
        (optionsPolicyId options)
        (optionsTokenName options)

assetAmount :: Map.Map Text (Map.Map Text Integer) -> Text -> Text -> Integer
assetAmount assets policyId tokenName =
    fromMaybe 0 (Map.lookup policyId assets >>= Map.lookup tokenName)

buildTransferTxHex :: Options -> [UTxO] -> String
buildTransferTxHex options selectedUtxOs =
    hexEncode
        ( encodeMap
            [ ("operation", encodeText "transfer")
            , ("from_address", encodeText (optionsFromAddress options))
            , ("to_address", encodeText (optionsToAddress options))
            , ("policy_id", encodeText (optionsPolicyId options))
            , ("token_name", encodeText (optionsTokenName options))
            , ("amount", encodeUnsigned (optionsAmount options))
            , ("inputs", encodeArray (encodeSelectedInput options <$> selectedUtxOs))
            ]
        )

encodeSelectedInput :: Options -> UTxO -> [Word8]
encodeSelectedInput options utxo =
    encodeMap
        [ ("tx_id", encodeText (utxoTxId (utxoRef utxo)))
        , ("index", encodeUnsigned (toInteger (utxoIndex (utxoRef utxo))))
        , ("amount", encodeUnsigned (matchingAssetAmount options utxo))
        ]

parseAddressArgument :: String -> Either String Text
parseAddressArgument raw
    | Text.null address = Left "address must not be empty"
    | otherwise = Right address
  where
    address = Text.pack raw

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

parseAmountArgument :: String -> Either String Integer
parseAmountArgument raw =
    case readMaybe raw of
        Just amount
            | amount > 0 ->
                Right amount
            | otherwise ->
                Left "amount must be positive"
        Nothing ->
            Left "amount must be a positive decimal integer"

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
    hPutStrLn stderr ("transfer: " <> message)
    exitWith (ExitFailure 1)
