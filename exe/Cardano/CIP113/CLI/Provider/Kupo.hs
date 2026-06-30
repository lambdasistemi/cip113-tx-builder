{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.CIP113.CLI.Provider.Kupo (
    KupoProviderConfig (..),
    KupoProvider,
    withKupoProvider,
) where

import Cardano.CIP113.CLI.Provider (
    UTxO (..),
    UTxOProvider (..),
    UTxORef (..),
    UTxOValue (..),
 )
import Control.Applicative ((<|>))
import Control.Exception (displayException, try)
import Data.Aeson (
    FromJSON (parseJSON),
    eitherDecode',
    withObject,
    withText,
    (.:),
    (.:?),
 )
import Data.Aeson.Types ((.!=))
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Network.HTTP.Client (
    HttpException,
    Manager,
    Request (..),
    Response,
    httpLbs,
    newManager,
    parseRequest,
    responseBody,
    responseStatus,
 )
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status qualified as Status
import Network.HTTP.Types.URI (Query, renderQuery)
import Text.Read (readMaybe)

newtype KupoProviderConfig = KupoProviderConfig
    { kupoBaseUrl :: Text
    }
    deriving (Show, Eq)

data KupoProvider = KupoProvider
    { kupoManager :: !Manager
    , kupoBaseRequest :: !Request
    }

data KupoMatch = KupoMatch
    { kupoTransactionId :: !Text
    , kupoOutputIndex :: !Word
    , kupoAddress :: !Text
    , kupoValue :: !KupoValue
    }
    deriving (Show, Eq)

data KupoValue = KupoValue
    { kupoCoins :: !Integer
    , kupoAssets :: !(Map Text Integer)
    }
    deriving (Show, Eq)

newtype Quantity = Quantity
    { unQuantity :: Integer
    }

withKupoProvider :: KupoProviderConfig -> (KupoProvider -> IO a) -> IO a
withKupoProvider KupoProviderConfig{kupoBaseUrl} k = do
    baseRequest <- parseProviderRequest "Kupo" (normalizeBaseUrl kupoBaseUrl)
    manager <- newManager tlsManagerSettings
    k
        KupoProvider
            { kupoManager = manager
            , kupoBaseRequest = baseRequest
            }

instance UTxOProvider KupoProvider where
    queryUTxOsByAddress provider address = do
        matches <- kupoGetJSON provider ("/matches/" <> address) [("unspent", Nothing)]
        traverse convertKupoMatch matches

    queryUTxOByRef provider UTxORef{utxoTxId, utxoIndex} = do
        matches <-
            kupoGetJSON
                provider
                ( "/matches/"
                    <> Text.pack (show utxoIndex)
                    <> "@"
                    <> utxoTxId
                )
                [("unspent", Nothing)]
        case matches of
            [] ->
                pure Nothing
            match : _ ->
                Just <$> convertKupoMatch match

normalizeBaseUrl :: Text -> Text
normalizeBaseUrl =
    Text.dropWhileEnd (== '/')

parseProviderRequest :: String -> Text -> IO Request
parseProviderRequest providerName url = do
    result <- try (parseRequest (Text.unpack url)) :: IO (Either HttpException Request)
    case result of
        Left err ->
            fail $
                providerName
                    <> " base URL is invalid: "
                    <> Text.unpack url
                    <> ": "
                    <> displayException err
        Right request ->
            pure request

kupoGetJSON :: (FromJSON a) => KupoProvider -> Text -> Query -> IO a
kupoGetJSON provider endpoint query =
    kupoRequest provider endpoint query
        >>= decodeProviderJSON "Kupo" (endpointText endpoint query)

kupoRequest ::
    KupoProvider ->
    Text ->
    Query ->
    IO (Response LBS.ByteString)
kupoRequest KupoProvider{kupoManager, kupoBaseRequest} endpoint query = do
    let request = buildRequest kupoBaseRequest endpoint query
    result <-
        try (httpLbs request kupoManager) ::
            IO (Either HttpException (Response LBS.ByteString))
    case result of
        Left err ->
            fail $
                "Kupo HTTP request failed for "
                    <> requestEndpoint request
                    <> ": "
                    <> displayException err
        Right response -> do
            requireSuccessStatus "Kupo" response
            pure response

buildRequest :: Request -> Text -> Query -> Request
buildRequest baseRequest endpoint query =
    baseRequest
        { path = appendPath (path baseRequest) (Text.encodeUtf8 endpoint)
        , queryString = renderQuery True query
        }

appendPath :: BSC.ByteString -> BSC.ByteString -> BSC.ByteString
appendPath basePath endpoint =
    normalizedBasePath <> endpoint
  where
    normalizedBasePath
        | basePath == "" || basePath == "/" = ""
        | otherwise = BSC.dropWhileEnd (== '/') basePath

requireSuccessStatus :: String -> Response body -> IO ()
requireSuccessStatus providerName response = do
    let status = responseStatus response
        code = Status.statusCode status
    if code >= 200 && code < 300
        then pure ()
        else
            fail $
                providerName
                    <> " HTTP request failed with status "
                    <> show code
                    <> " "
                    <> BSC.unpack (Status.statusMessage status)

decodeProviderJSON :: (FromJSON a) => String -> String -> Response LBS.ByteString -> IO a
decodeProviderJSON providerName endpoint response =
    case eitherDecode' (responseBody response) of
        Left err ->
            fail $
                providerName
                    <> " JSON parse failed for "
                    <> endpoint
                    <> ": "
                    <> err
        Right decoded ->
            pure decoded

endpointText :: Text -> Query -> String
endpointText endpoint query =
    Text.unpack endpoint <> BSC.unpack (renderQuery True query)

requestEndpoint :: Request -> String
requestEndpoint request =
    BSC.unpack (path request <> queryString request)

convertKupoMatch :: KupoMatch -> IO UTxO
convertKupoMatch KupoMatch{kupoTransactionId, kupoOutputIndex, kupoAddress, kupoValue} = do
    value <- convertValue kupoValue
    pure
        UTxO
            { utxoRef =
                UTxORef
                    { utxoTxId = kupoTransactionId
                    , utxoIndex = kupoOutputIndex
                    }
            , utxoAddress = kupoAddress
            , utxoValue = value
            }

convertValue :: KupoValue -> IO UTxOValue
convertValue KupoValue{kupoCoins, kupoAssets} = do
    assets <- foldMapAssets kupoAssets
    pure
        UTxOValue
            { utxoLovelace = kupoCoins
            , utxoAssets = assets
            }

foldMapAssets :: Map Text Integer -> IO (Map Text (Map Text Integer))
foldMapAssets =
    Map.foldlWithKey' insertAsset (pure Map.empty)

insertAsset ::
    IO (Map Text (Map Text Integer)) ->
    Text ->
    Integer ->
    IO (Map Text (Map Text Integer))
insertAsset accumulated raw quantity = do
    assets <- accumulated
    (policyId, assetNameHex) <- parseAssetKey raw
    tokenName <- decodeAssetNameHex assetNameHex
    pure $
        Map.insertWith
            (Map.unionWith (+))
            policyId
            (Map.singleton tokenName quantity)
            assets

parseAssetKey :: Text -> IO (Text, Text)
parseAssetKey raw =
    case Text.breakOn "." raw of
        (policyId, assetNameWithDot)
            | Text.length policyId == 56 && Text.null assetNameWithDot ->
                pure (policyId, "")
            | Text.null policyId || Text.null assetNameWithDot ->
                invalidAssetKey
            | otherwise ->
                pure (policyId, Text.drop 1 assetNameWithDot)
  where
    invalidAssetKey =
        fail $
            "Kupo native asset key must be policyId.assetNameHex: "
                <> Text.unpack raw

decodeAssetNameHex :: Text -> IO Text
decodeAssetNameHex raw =
    case Base16.decode (Text.encodeUtf8 raw) of
        Left err ->
            fail ("Kupo asset name is not valid base16: " <> err)
        Right bytes ->
            case Text.decodeUtf8' bytes of
                Left err ->
                    fail $
                        "Kupo asset name is not valid UTF-8 for CLI token-name text: "
                            <> show err
                Right decoded ->
                    pure decoded

instance FromJSON KupoMatch where
    parseJSON =
        withObject "Kupo match" $ \object ->
            KupoMatch
                <$> object .: "transaction_id"
                <*> object .: "output_index"
                <*> object .: "address"
                <*> object .: "value"

instance FromJSON KupoValue where
    parseJSON =
        withObject "Kupo value" $ \object ->
            (KupoValue . unQuantity <$> object .: "coins")
                <*> fmap (fmap unQuantity) (object .:? "assets" .!= Map.empty)

instance FromJSON Quantity where
    parseJSON value =
        (Quantity <$> parseJSON value)
            <|> withText
                "decimal quantity"
                ( \raw ->
                    case readMaybe (Text.unpack raw) of
                        Just quantity ->
                            pure (Quantity quantity)
                        Nothing ->
                            fail ("invalid decimal quantity: " <> Text.unpack raw)
                )
                value
