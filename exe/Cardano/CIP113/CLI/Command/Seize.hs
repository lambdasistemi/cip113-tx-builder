{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.CIP113.CLI.Command.Seize (
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
import Cardano.CIP113.ThirdParty (ThirdPartyInput (..), thirdPartyTx)
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
    , optionsTargetAddress :: !Text
    , optionsToAddress :: !Text
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
        <*> option
            (eitherReader parseAddressArgument)
            ( long "target-address"
                <> metavar "ADDR"
                <> help "Target address"
            )
        <*> option
            (eitherReader parseAddressArgument)
            ( long "to-address"
                <> metavar "ADDR"
                <> help "Destination address"
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
    targetUtxOs <- queryUTxOsByAddress provider (optionsTargetAddress options)
    selectedUtxOs <- selectMatchingInputs options targetUtxOs
    let txHex = buildSeizeTxHex options selectedUtxOs
    if jsonOutput
        then putStrLn ("{\"tx\":\"" <> txHex <> "\"}")
        else putStrLn txHex

runWithNodeProvider :: CIP113Deployment -> Node.Provider IO -> Bool -> Options -> IO ()
runWithNodeProvider deployment provider jsonOutput options = do
    txHex <- buildSeizeNodeTxHex deployment provider options
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

buildSeizeNodeTxHex :: CIP113Deployment -> Node.Provider IO -> Options -> IO String
buildSeizeNodeTxHex deployment@CIP113Deployment{..} provider options = do
    changeAddressText <-
        case optionsChangeAddress options of
            Just address ->
                pure address
            Nothing ->
                dieUser "real seize requires --change-address"
    changeAddr <- parseCardanoAddress changeAddressText
    targetAddr <- parseCardanoAddress (optionsTargetAddress options)
    toAddr <- parseCardanoAddress (optionsToAddress options)
    policyKey <- decodePolicyKey (optionsPolicyId options)
    policyId <- decodePolicyId (optionsPolicyId options)
    let tokenName = AssetName (SBS.toShort (Text.encodeUtf8 (optionsTokenName options)))
    pp <- queryProtocolParams provider
    fundingUtxos <- queryUTxOs provider changeAddr
    targetUtxos <- queryUTxOs provider targetAddr
    registryUtxos <- queryUTxOs provider dRegistryAddr
    lockedUtxos <- queryUTxOs provider dAlwaysFailAddr
    collateralIn <-
        case largeFeeUtxos fundingUtxos of
            (txIn, _) : _ ->
                pure txIn
            [] ->
                dieUser "no funding UTxOs available at --change-address"
    selectedInputs <- selectNodeMatchingInputs policyId tokenName targetUtxos
    resolvedNode <-
        either
            (dieUser . ("failed to resolve registered token: " <>) . show)
            (maybe (dieUser "registered token not found in registry") pure)
            =<< findNode deployment provider (map fst lockedUtxos) policyKey
    let ResolvedRegistryNode{rrnUtxo, rrnReferenceInputIndex} = resolvedNode
        RegistryNodeUtxo{rnuTxIn = registryNodeIn} = rrnUtxo
    (requiredSigner, thirdPartyAccount) <-
        either dieUser pure (targetAuthorization targetAddr)
    let outputPairs =
            [ ( targetAddr
              , removeAssetAmount policyId tokenName amount (txOut ^. valueTxOutL)
              , toAddr
              , tokenValue policyId tokenName amount
              )
            | (_, txOut) <- selectedInputs
            , let amount = txOutAssetAmount policyId tokenName txOut
            ]
        outputs =
            concat
                [ [(pairedAddr, pairedValue), (destinationAddr, seizedValue)]
                | (pairedAddr, pairedValue, destinationAddr, seizedValue) <- outputPairs
                ]
        seizeInputs =
            [ ThirdPartyInput
                { tpTxIn = txIn
                , tpRegistryNodeIdx = rrnReferenceInputIndex
                , tpOutputsStartIdx = ix * 2
                }
            | (ix, (txIn, _)) <- zip [0 ..] selectedInputs
            ]
        seizeBuild :: TxBuild NoQ NoErr ()
        seizeBuild = do
            collateral collateralIn
            requireSignature requiredSigner
            thirdPartyTx
                (plgAccountAddress Testnet dPlgHash)
                dPlbScript
                dPlgScript
                seizeInputs
                [registryNodeIn]
                []
                outputs
            withdraw thirdPartyAccount (Coin 0)
            mapM_ (reference . fst) lockedUtxos
        interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
    tx <-
        either (dieUser . ("failed to build seize transaction: " <>) . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                (largeFeeUtxos fundingUtxos <> selectedInputs)
                (registryUtxos <> lockedUtxos)
                changeAddr
                seizeBuild
    pure (Text.unpack (hexText (serialize' (eraProtVerLow @ConwayEra) tx)))

data NoQ a
data NoErr deriving (Show)

targetAuthorization :: Addr -> Either String (KeyHash Guard, AccountAddress)
targetAuthorization = \case
    Addr _ _ (StakeRefBase (KeyHashObj (KeyHash h))) ->
        Right (KeyHash h, AccountAddress Testnet (AccountId (KeyHashObj (KeyHash h))))
    Addr _ _ StakeRefNull ->
        Left "target smart wallet must use a key-backed staking credential"
    Addr _ _ (StakeRefBase (ScriptHashObj _)) ->
        Left "target smart wallet script staking credentials are not supported by seize CLI signing yet"
    Addr _ _ (StakeRefPtr _) ->
        Left "target smart wallet stake pointers are not supported by seize CLI signing"
    AddrBootstrap _ ->
        Left "target smart wallet must be a Shelley-era address"

selectNodeMatchingInputs ::
    PolicyID ->
    AssetName ->
    [(TxIn, TxOut ConwayEra)] ->
    IO [(TxIn, TxOut ConwayEra)]
selectNodeMatchingInputs policyId tokenName targetUtxos =
    case matchingUtxOs of
        [] ->
            dieUser "no UTxOs carry the requested token"
        _ ->
            pure matchingUtxOs
  where
    matchingUtxOs =
        [ utxo
        | utxo@(_, txOut) <- targetUtxos
        , txOutAssetAmount policyId tokenName txOut > 0
        ]

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

selectMatchingInputs :: Options -> [UTxO] -> IO [UTxO]
selectMatchingInputs options targetUtxOs =
    case matchingUtxOs of
        [] ->
            dieUser "no UTxOs carry the requested token"
        _ ->
            pure matchingUtxOs
  where
    matchingUtxOs =
        [ utxo
        | utxo <- targetUtxOs
        , matchingAssetAmount options utxo > 0
        ]

matchingAssetAmount :: Options -> UTxO -> Integer
matchingAssetAmount options utxo =
    assetAmount
        (utxoAssets (utxoValue utxo))
        (optionsPolicyId options)
        (optionsTokenName options)

assetAmount :: Map.Map Text (Map.Map Text Integer) -> Text -> Text -> Integer
assetAmount assets policyId tokenName =
    fromMaybe 0 (Map.lookup policyId assets >>= Map.lookup tokenName)

buildSeizeTxHex :: Options -> [UTxO] -> String
buildSeizeTxHex options selectedUtxOs =
    hexEncode
        ( encodeMap
            [ ("operation", encodeText "seize")
            , ("target_address", encodeText (optionsTargetAddress options))
            , ("to_address", encodeText (optionsToAddress options))
            , ("policy_id", encodeText (optionsPolicyId options))
            , ("token_name", encodeText (optionsTokenName options))
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
    hPutStrLn stderr ("seize: " <> message)
    exitWith (ExitFailure 1)
