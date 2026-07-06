{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.CIP113.CLI.Settings
Description : opt-env-conf settings shared by the CIP-113 CLI
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Reusable settings for command-line options, environment variables, and
YAML configuration keys used by @cip113-cli@.
-}
module Cardano.CIP113.CLI.Settings (
    addressTextSetting,
    changeAddressSetting,
    deploymentSetting,
    nodeConnectionSetting,
    policyIdSetting,
    positiveAmountSetting,
    tokenNameSetting,
    utxoFileSetting,
    utxoRefSetting,
) where

import Cardano.CIP113.CLI.Provider (UTxORef (..))
import Cardano.CIP113.CLI.Provider.Node (NodeProviderConfig (..))
import Cardano.CIP113.Deployment (CIP113Deployment)
import Cardano.Ledger.Address (Addr, decodeAddrEither)
import Codec.Binary.Bech32 qualified as Bech32
import Control.Applicative (optional)
import Control.Exception (IOException, displayException, try)
import Data.Aeson qualified as Aeson
import Data.ByteString.Base16 qualified as Base16
import Data.Char (isHexDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Word (Word32)
import OptEnvConf (
    Parser,
    checkMapEither,
    checkMapIO,
    eitherReader,
    help,
    metavar,
    name,
    reader,
    setting,
    str,
 )
import Text.Read (readMaybe)

-- | Deployment descriptor loaded from JSON.
deploymentSetting :: Parser CIP113Deployment
deploymentSetting =
    checkMapIO loadDeployment $
        setting
            [ name "deployment"
            , reader str
            , metavar "FILE"
            , help "CIP-113 deployment descriptor JSON file"
            ]

-- | Node connection settings required for real transaction building.
nodeConnectionSetting :: Parser NodeProviderConfig
nodeConnectionSetting =
    NodeProviderConfig
        <$> setting
            [ name "socket-path"
            , reader str
            , metavar "PATH"
            , help "Cardano node socket path"
            ]
        <*> setting
            [ name "network-magic"
            , reader (eitherReader parseNetworkMagic)
            , metavar "INT"
            , help "Cardano network magic"
            ]

-- | Funding and change address for node-backed transaction builds.
changeAddressSetting :: Parser Text
changeAddressSetting =
    checkMapEither parseAddressArgument $
        setting
            [ name "change-address"
            , reader str
            , metavar "ADDR"
            , help "Funding and change address for real node transaction builds"
            ]

-- | Optional plain address setting for bridge command parsers.
addressTextSetting :: String -> String -> Parser Text
addressTextSetting settingName settingHelp =
    checkMapEither parseAddressArgument $
        setting
            [ name settingName
            , reader str
            , metavar "ADDR"
            , help settingHelp
            ]

-- | Non-empty token name text.
tokenNameSetting :: Parser Text
tokenNameSetting =
    checkMapEither parseTokenNameArgument $
        setting
            [ name "token-name"
            , reader str
            , metavar "NAME"
            , help "Token name"
            ]

-- | Lower-case 56-character policy id.
policyIdSetting :: Parser Text
policyIdSetting =
    checkMapEither parsePolicyIdArgument $
        setting
            [ name "policy-id"
            , reader str
            , metavar "HEX"
            , help "56-character token policy id"
            ]

-- | Optional offline UTxO JSON file path.
utxoFileSetting :: Parser (Maybe FilePath)
utxoFileSetting =
    optional $
        setting
            [ name "utxo-file"
            , reader str
            , metavar "FILE"
            , help "Offline cardano-cli UTxO JSON file"
            ]

-- | Optional legacy registry UTxO reference.
utxoRefSetting :: Parser (Maybe UTxORef)
utxoRefSetting =
    optional $
        checkMapEither parseUTxORefArgument $
            setting
                [ name "registry-utxo"
                , reader str
                , metavar "TXID#IX"
                , help "Legacy offline registry UTxO reference"
                ]

-- | Positive token amount.
positiveAmountSetting :: Parser Integer
positiveAmountSetting =
    checkMapEither parseAmountArgument $
        setting
            [ name "amount"
            , reader str
            , metavar "INT"
            , help "Positive token amount to transfer"
            ]

loadDeployment :: FilePath -> IO (Either String CIP113Deployment)
loadDeployment path = do
    loaded <-
        try
            ( Aeson.eitherDecodeFileStrict' path ::
                IO (Either String CIP113Deployment)
            )
    pure $
        case loaded of
            Left err ->
                Left $
                    "failed to read deployment file "
                        <> show path
                        <> ": "
                        <> displayException (err :: IOException)
            Right (Left err) ->
                Left $
                    "failed to decode deployment file "
                        <> show path
                        <> ": "
                        <> err
            Right (Right deployment) ->
                Right deployment

parseNetworkMagic :: String -> Either String Word32
parseNetworkMagic raw =
    case readMaybe raw of
        Just magic ->
            Right magic
        Nothing ->
            Left "network magic must be a decimal Word32"

parseAddressArgument :: Text -> Either String Text
parseAddressArgument raw
    | Text.null raw = Left "address must not be empty"
    | otherwise =
        case parseCardanoAddress raw of
            Right _ ->
                Right raw
            Left err ->
                Left err

parseCardanoAddress :: Text -> Either String Addr
parseCardanoAddress raw =
    case decodeBech32Address raw of
        Right address ->
            Right address
        Left bech32Err ->
            case Base16.decode (Text.encodeUtf8 raw) of
                Right bytes ->
                    case decodeAddrEither bytes of
                        Right address ->
                            Right address
                        Left ledgerErr ->
                            Left $
                                "failed to decode base16 serialized Cardano address: "
                                    <> ledgerErr
                Left hexErr ->
                    Left $
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

parseUTxORefArgument :: Text -> Either String UTxORef
parseUTxORefArgument raw =
    case Text.splitOn "#" raw of
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

parseTokenNameArgument :: Text -> Either String Text
parseTokenNameArgument tokenName
    | Text.null tokenName = Left "token name must not be empty"
    | otherwise = Right tokenName

parsePolicyIdArgument :: Text -> Either String Text
parsePolicyIdArgument policyId
    | Text.length policyId /= 56 = Left "policy id must be 56 hex characters"
    | not (Text.all isHexDigit policyId) = Left "policy id must be hex"
    | otherwise = Right (Text.toLower policyId)

parseAmountArgument :: Text -> Either String Integer
parseAmountArgument raw =
    case readMaybe (Text.unpack raw) of
        Just amount
            | amount > 0 ->
                Right amount
            | otherwise ->
                Left "amount must be positive"
        Nothing ->
            Left "amount must be a positive decimal integer"
