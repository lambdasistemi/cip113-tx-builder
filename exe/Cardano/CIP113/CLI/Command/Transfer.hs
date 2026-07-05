{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.CIP113.CLI.Command.Transfer (
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
import Data.ByteString.Short qualified as SBS
import Data.Char (isHexDigit, ord)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
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

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.Ledger.Address (AccountAddress (..), AccountId (..), Addr (..), decodeAddrEither)
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerLow)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxIn)

import Cardano.CIP113.Address (plgAccountAddress)
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
import Cardano.CIP113.Deployment (CIP113Deployment (..))
import Cardano.CIP113.Registry (RegistryNodeUtxo (..), ResolvedRegistryNode (..), findNode)
import Cardano.CIP113.Transfer (TransferInput (..), transferTx)
import Cardano.CIP113.Types (RegistryProof (..))
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Provider qualified as Node
import Cardano.Tx.Build (
    InterpretIO (..),
    TxBuild,
    build,
    collateral,
    mkPParamsBound,
    reference,
    requireSignature,
    withdraw,
 )
import Codec.Binary.Bech32 qualified as Bech32

data Options = Options
    { optionsUtxoFile :: !(Maybe FilePath)
    , optionsFromAddress :: !Text
    , optionsToAddress :: !Text
    , optionsTokenName :: !Text
    , optionsPolicyId :: !Text
    , optionsAmount :: !Integer
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
    senderUtxOs <- queryUTxOsByAddress provider (optionsFromAddress options)
    selectedUtxOs <- selectTransferInputs options senderUtxOs
    let txHex = buildTransferTxHex options selectedUtxOs
    if jsonOutput
        then putStrLn ("{\"tx\":\"" <> txHex <> "\"}")
        else putStrLn txHex

runWithNodeProvider :: CIP113Deployment -> Node.Provider IO -> Bool -> Options -> IO ()
runWithNodeProvider deployment provider jsonOutput options = do
    txHex <- buildTransferNodeTxHex deployment provider options
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

buildTransferNodeTxHex :: CIP113Deployment -> Node.Provider IO -> Options -> IO String
buildTransferNodeTxHex deployment@CIP113Deployment{..} provider options = do
    changeAddressText <-
        case optionsChangeAddress options of
            Just address ->
                pure address
            Nothing ->
                dieUser "real transfer requires --change-address"
    changeAddr <- parseCardanoAddress changeAddressText
    fromAddr <- parseCardanoAddress (optionsFromAddress options)
    toAddr <- parseCardanoAddress (optionsToAddress options)
    policyKey <- decodePolicyKey (optionsPolicyId options)
    policyId <- decodePolicyId (optionsPolicyId options)
    let tokenName = AssetName (SBS.toShort (Text.encodeUtf8 (optionsTokenName options)))
    pp <- queryProtocolParams provider
    fundingUtxos <- queryUTxOs provider changeAddr
    senderUtxos <- queryUTxOs provider fromAddr
    registryUtxos <- queryUTxOs provider dRegistryAddr
    lockedUtxos <- queryUTxOs provider dAlwaysFailAddr
    collateralIn <-
        case largeFeeUtxos fundingUtxos of
            (txIn, _) : _ ->
                pure txIn
            [] ->
                dieUser "no funding UTxOs available at --change-address"
    selectedInputs <- selectNodeTransferInputs options policyId tokenName senderUtxos
    resolvedNode <-
        either
            (dieUser . ("failed to resolve registered token: " <>) . show)
            (maybe (dieUser "registered token not found in registry") pure)
            =<< findNode deployment provider (map fst lockedUtxos) policyKey
    let ResolvedRegistryNode{rrnUtxo, rrnReferenceInputIndex} = resolvedNode
        RegistryNodeUtxo{rnuTxIn = registryNodeIn} = rrnUtxo
        proof = TokenExists rrnReferenceInputIndex
    (requiredSigner, sourceAccount) <-
        either dieUser pure (sourceAuthorization fromAddr)
    let totalSelected =
            sum
                [ txOutAssetAmount policyId tokenName txOut
                | (_, txOut) <- selectedInputs
                ]
        requested = optionsAmount options
        pairedOutputs =
            [ (fromAddr, removeAssetAmount policyId tokenName amount (txOut ^. valueTxOutL))
            | (_, txOut) <- selectedInputs
            , let amount = txOutAssetAmount policyId tokenName txOut
            ]
        outputs =
            pairedOutputs
                <> [(toAddr, tokenValue policyId tokenName requested)]
                <> [ (fromAddr, tokenValue policyId tokenName (totalSelected - requested))
                   | totalSelected > requested
                   ]
        transferBuild :: TxBuild NoQ NoErr ()
        transferBuild = do
            collateral collateralIn
            requireSignature requiredSigner
            transferTx
                (plgAccountAddress Testnet dPlgHash)
                dPlbScript
                dPlgScript
                [ TransferInput txIn proof
                | (txIn, _) <- selectedInputs
                ]
                [registryNodeIn]
                []
                outputs
            withdraw sourceAccount (Coin 0)
            mapM_ (reference . fst) lockedUtxos
        interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
    tx <-
        either (dieUser . ("failed to build transfer transaction: " <>) . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                (largeFeeUtxos fundingUtxos <> selectedInputs)
                (registryUtxos <> lockedUtxos)
                changeAddr
                transferBuild
    pure (Text.unpack (hexText (serialize' (eraProtVerLow @ConwayEra) tx)))

data NoQ a
data NoErr deriving (Show)

sourceAuthorization :: Addr -> Either String (KeyHash Guard, AccountAddress)
sourceAuthorization = \case
    Addr _ _ (StakeRefBase (KeyHashObj (KeyHash h))) ->
        Right (KeyHash h, AccountAddress Testnet (AccountId (KeyHashObj (KeyHash h))))
    Addr _ _ StakeRefNull ->
        Left "source smart wallet must use a key-backed staking credential"
    Addr _ _ (StakeRefBase (ScriptHashObj _)) ->
        Left "source smart wallet script staking credentials are not supported by transfer CLI signing yet"
    Addr _ _ (StakeRefPtr _) ->
        Left "source smart wallet stake pointers are not supported by transfer CLI signing"
    AddrBootstrap _ ->
        Left "source smart wallet must be a Shelley-era address"

selectNodeTransferInputs ::
    Options ->
    PolicyID ->
    AssetName ->
    [(TxIn, TxOut ConwayEra)] ->
    IO [(TxIn, TxOut ConwayEra)]
selectNodeTransferInputs options policyId tokenName senderUtxos = do
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
        | utxo@(_, txOut) <- senderUtxos
        , let amount = txOutAssetAmount policyId tokenName txOut
        , amount > 0
        ]
    totalAvailable =
        sum (snd <$> matchingUtxOs)

txOutAssetAmount :: PolicyID -> AssetName -> TxOut ConwayEra -> Integer
txOutAssetAmount policyId tokenName txOut =
    maryValueAssetAmount policyId tokenName (txOut ^. valueTxOutL)

maryValueAssetAmount :: PolicyID -> AssetName -> MaryValue -> Integer
maryValueAssetAmount policyId tokenName (MaryValue _ (MultiAsset assets)) =
    Map.findWithDefault 0 tokenName (Map.findWithDefault Map.empty policyId assets)

removeAssetAmount :: PolicyID -> AssetName -> Integer -> MaryValue -> MaryValue
removeAssetAmount policyId tokenName amount (MaryValue coin (MultiAsset assets)) =
    MaryValue coin (MultiAsset (Map.update prunePolicy policyId assets))
  where
    prunePolicy inner =
        let inner' = Map.update pruneAsset tokenName inner
         in if Map.null inner'
                then Nothing
                else Just inner'
    pruneAsset n =
        let n' = n - amount
         in if n' <= 0
                then Nothing
                else Just n'

tokenValue :: PolicyID -> AssetName -> Integer -> MaryValue
tokenValue policyId tokenName amount =
    MaryValue
        (Coin 0)
        (MultiAsset (Map.singleton policyId (Map.singleton tokenName amount)))

largeFeeUtxos :: [(txIn, TxOut ConwayEra)] -> [(txIn, TxOut ConwayEra)]
largeFeeUtxos utxos =
    case filter ((>= Coin 10_000_000) . (^. coinTxOutL) . snd) utxos of
        [] -> utxos
        large -> large

decodePolicyKey :: Text -> IO BS.ByteString
decodePolicyKey =
    decodeHexText "policy id"

decodePolicyId :: Text -> IO PolicyID
decodePolicyId raw = do
    bytes <- decodePolicyKey raw
    case hashFromBytes bytes of
        Just hash ->
            pure (PolicyID (ScriptHash hash))
        Nothing ->
            dieUser "policy id must decode to a 28-byte script hash"

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
                        "failed to parse address as bech32 Cardano address ("
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

takeUntilAtLeast :: Integer -> [(a, Integer)] -> [(a, Integer)]
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
    hPutStrLn stderr ("transfer: " <> message)
    exitWith (ExitFailure 1)
