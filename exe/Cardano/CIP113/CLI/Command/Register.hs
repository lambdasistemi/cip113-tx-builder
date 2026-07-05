{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.CIP113.CLI.Command.Register (
    Options (..),
    parser,
    run,
    runWithNodeProvider,
    runWithProvider,
) where

import Control.Applicative (optional)
import Control.Exception (IOException, displayException, try)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Char (isHexDigit, ord)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Word (Word8)
import Lens.Micro ((^.))
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

import Cardano.Ledger.Address (Addr, decodeAddrEither)
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerLow)
import Cardano.Ledger.TxIn (TxIn)

import Cardano.CIP113.Address (plgAccountAddress)
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
import Cardano.CIP113.Deployment (CIP113Deployment (..))
import Cardano.CIP113.Register (registerTx)
import Cardano.CIP113.Registry (RegistryNodeUtxo (..), findInsertionPoint)
import Cardano.CIP113.Scripts (scriptHashBytes)
import Cardano.CIP113.Types (
    CIP113Credential (..),
    PLGRedeemer (..),
    RegistrationMode (..),
    RegistryNode (..),
    RegistryRedeemer (..),
 )
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Provider qualified as Node
import Cardano.Tx.Build (
    InterpretIO (..),
    TxBuild,
    attachScript,
    build,
    collateral,
    mkPParamsBound,
    reference,
    withdrawScript,
 )
import Codec.Binary.Bech32 qualified as Bech32

data Options = Options
    { optionsUtxoFile :: !(Maybe FilePath)
    , optionsRegistryUtxo :: !(Maybe UTxORef)
    , optionsTokenName :: !Text
    , optionsPolicyId :: !Text
    , optionsChangeAddress :: !(Maybe Text)
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
        <*> optional
            ( option
                (eitherReader parseUTxORefArgument)
                ( long "registry-utxo"
                    <> metavar "TXID#IX"
                    <> help "Legacy offline registry UTxO reference"
                )
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
        <*> optional
            ( Text.pack
                <$> strOption
                    ( long "change-address"
                        <> metavar "ADDR"
                        <> help "Funding and change address for real node transaction builds"
                    )
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
    registryRef <-
        case optionsRegistryUtxo options of
            Just ref ->
                pure ref
            Nothing ->
                dieUser "offline register requires --registry-utxo"
    maybeRegistryUtxo <- queryUTxOByRef provider registryRef
    registryUtxo <-
        case maybeRegistryUtxo of
            Just utxo ->
                pure utxo
            Nothing ->
                dieUser
                    ( "registry UTxO not found in offline file: "
                        <> formatUTxORef registryRef
                    )
    txHex <- buildRegisterTxHex options registryUtxo
    if jsonOutput
        then putStrLn ("{\"tx\":\"" <> txHex <> "\"}")
        else putStrLn txHex

runWithNodeProvider :: CIP113Deployment -> Node.Provider IO -> Bool -> Options -> IO ()
runWithNodeProvider deployment provider jsonOutput options = do
    txHex <- buildRegisterNodeTxHex deployment provider options
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
    registryRef <-
        case optionsRegistryUtxo options of
            Just ref ->
                pure ref
            Nothing ->
                dieUser "offline register requires --registry-utxo"
    pure
        ( hexEncode
            ( encodeMap
                [ ("lovelace", encodeUnsigned lovelace)
                , ("operation", encodeText "register")
                , ("policy_id", encodeText (optionsPolicyId options))
                , ("registry_utxo", encodeRegistryUtxORef registryRef)
                , ("token_name", encodeText (optionsTokenName options))
                ]
            )
        )

buildRegisterNodeTxHex :: CIP113Deployment -> Node.Provider IO -> Options -> IO String
buildRegisterNodeTxHex deployment@CIP113Deployment{..} provider options = do
    changeAddressText <-
        case optionsChangeAddress options of
            Just address ->
                pure address
            Nothing ->
                dieUser "real register requires --change-address"
    changeAddr <- parseCardanoAddress changeAddressText
    newPolicyKey <- decodePolicyKey (optionsPolicyId options)
    predecessor <-
        either
            (dieUser . ("failed to resolve registry predecessor: " <>) . show)
            pure
            =<< findInsertionPoint deployment provider newPolicyKey
    let RegistryNodeUtxo{rnuTxIn, rnuTxOut, rnuNode = predecessorNode} =
            predecessor
        predecessorValue = rnuTxOut ^. valueTxOutL
        mintingCred = ScriptCredential (scriptHashBytes dPlgHash)
        updatedPredecessor =
            predecessorNode
                { rnNext = newPolicyKey
                }
        newNode =
            RegistryNode
                { rnKey = newPolicyKey
                , rnNext = rnNext predecessorNode
                , rnMintingLogicScript = mintingCred
                , rnTransferLogicScript = mintingCred
                , rnThirdPartyTransferLogicScript = mintingCred
                , rnGlobalStateCs = mempty
                , rnProtectedPrefixes = []
                }
        insertRdmr =
            RegistryInsert
                { riKey = newPolicyKey
                , riMintingLogicScript = mintingCred
                , riMode = RegisterOnly
                }
    pp <- queryProtocolParams provider
    fundingUtxos <- queryUTxOs provider changeAddr
    registryUtxos <- queryUTxOs provider dRegistryAddr
    lockedUtxos <- queryUTxOs provider dAlwaysFailAddr
    collateralIn <-
        case largeFeeUtxos fundingUtxos of
            (txIn, _) : _ ->
                pure txIn
            [] ->
                dieUser "no funding UTxOs available at --change-address"
    let insertTx :: TxBuild NoQ NoErr ()
        insertTx = do
            attachScript dPlgScript
            collateral collateralIn
            mapM_ (reference . fst) lockedUtxos
            withdrawScript
                (plgAccountAddress Testnet dPlgHash)
                (Coin 0)
                (TransferAct [])
            registerTx
                dRegistrySpendScript
                dRegistryMintScript
                dRegistryPolicy
                rnuTxIn
                predecessorValue
                dRegistryAddr
                updatedPredecessor
                newNode
                insertRdmr
                Nothing
        interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
        inputUtxos =
            largeFeeUtxos fundingUtxos <> predecessorInput registryUtxos predecessor
    tx <-
        either (dieUser . ("failed to build register transaction: " <>) . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                inputUtxos
                lockedUtxos
                changeAddr
                insertTx
    pure (Text.unpack (hexText (serialize' (eraProtVerLow @ConwayEra) tx)))

registryLovelaceOrExit :: UTxO -> IO Integer
registryLovelaceOrExit registryUtxo
    | lovelace >= 0 = pure lovelace
    | otherwise = dieUser "registry UTxO has negative lovelace"
  where
    lovelace = utxoLovelace (utxoValue registryUtxo)

data NoQ a
data NoErr deriving (Show)

largeFeeUtxos :: [(txIn, TxOut ConwayEra)] -> [(txIn, TxOut ConwayEra)]
largeFeeUtxos utxos =
    case filter ((>= Coin 10_000_000) . (^. coinTxOutL) . snd) utxos of
        [] -> utxos
        large -> large

predecessorInput ::
    [(TxIn, TxOut ConwayEra)] ->
    RegistryNodeUtxo ->
    [(TxIn, TxOut ConwayEra)]
predecessorInput registryUtxos RegistryNodeUtxo{rnuTxIn, rnuTxOut} =
    case filter ((== rnuTxIn) . fst) registryUtxos of
        [] -> [(rnuTxIn, rnuTxOut)]
        matches -> matches

decodePolicyKey :: Text -> IO BS.ByteString
decodePolicyKey =
    decodeHexText "policy id"

parseCardanoAddress :: Text -> IO Addr
parseCardanoAddress raw =
    case decodeBech32Address raw of
        Right address ->
            pure address
        Left bech32Err ->
            case Base16.decode (Text.encodeUtf8 raw) of
                Right bytes ->
                    case decodeAddrEither bytes of
                        Right address ->
                            pure address
                        Left ledgerErr ->
                            fail $
                                "failed to decode base16 serialized Cardano address: "
                                    <> ledgerErr
                Left hexErr ->
                    fail $
                        "failed to parse change address as bech32 Cardano address ("
                            <> bech32Err
                            <> ") or base16 serialized address ("
                            <> hexErr
                            <> ")"

decodeBech32Address :: Text -> Either String Addr
decodeBech32Address raw =
    case Bech32.decodeLenient raw of
        Left err ->
            Left ("bech32 decode failed: " <> show err)
        Right (_hrp, dataPart) ->
            case Bech32.dataPartToBytes dataPart of
                Nothing ->
                    Left "bech32 data-part not byte-aligned"
                Just bytes ->
                    case decodeAddrEither bytes of
                        Left err ->
                            Left ("ledger address decode failed: " <> err)
                        Right address ->
                            Right address

decodeHexText :: String -> Text -> IO BS.ByteString
decodeHexText label raw =
    case Base16.decode (Text.encodeUtf8 raw) of
        Right bytes ->
            pure bytes
        Left err ->
            fail ("invalid " <> label <> " base16: " <> err)

hexText :: BS.ByteString -> Text
hexText =
    Text.decodeUtf8 . Base16.encode

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
    | value <= 0xFFFF_FFFF = (majorTag .|. 26) : integerBytes 4 value
    | value <= 0xFFFF_FFFF_FFFF_FFFF = (majorTag .|. 27) : integerBytes 8 value
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
