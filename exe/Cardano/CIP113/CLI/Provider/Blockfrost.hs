{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.CIP113.CLI.Provider.Blockfrost (
    BlockfrostProviderConfig (..),
    BlockfrostProvider,
    withBlockfrostProvider,
) where

import Cardano.CIP113.CLI.Provider (
    UTxO (..),
    UTxOProvider (..),
    UTxORef (..),
    UTxOValue (..),
 )
import Control.Applicative ((<|>))
import Control.Exception (displayException, try)
import Control.Monad (foldM)
import Data.Aeson (
    FromJSON (parseJSON),
    eitherDecode',
    withObject,
    withText,
    (.:),
 )
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy qualified as LBS
import Data.List qualified as List
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

newtype BlockfrostProviderConfig = BlockfrostProviderConfig
    { blockfrostProjectId :: Text
    }
    deriving (Show, Eq)

data BlockfrostProvider = BlockfrostProvider
    { blockfrostManager :: !Manager
    , blockfrostBaseRequest :: !Request
    , blockfrostProjectIdHeader :: !Text
    }

data BlockfrostAddressUTxO = BlockfrostAddressUTxO
    { blockfrostAddress :: !Text
    , blockfrostTxHash :: !Text
    , blockfrostOutputIndex :: !Word
    , blockfrostAmount :: ![BlockfrostAmount]
    }
    deriving (Show, Eq)

newtype BlockfrostTxUTxOs = BlockfrostTxUTxOs
    { blockfrostTxOutputs :: [BlockfrostTxOutput]
    }
    deriving (Show, Eq)

data BlockfrostTxOutput = BlockfrostTxOutput
    { blockfrostTxOutputAddress :: !Text
    , blockfrostTxOutputIndex :: !Word
    , blockfrostTxOutputAmount :: ![BlockfrostAmount]
    }
    deriving (Show, Eq)

data BlockfrostAmount = BlockfrostAmount
    { blockfrostAmountUnit :: !Text
    , blockfrostAmountQuantity :: !Integer
    }
    deriving (Show, Eq)

newtype Quantity = Quantity
    { unQuantity :: Integer
    }

withBlockfrostProvider ::
    BlockfrostProviderConfig ->
    (BlockfrostProvider -> IO a) ->
    IO a
withBlockfrostProvider BlockfrostProviderConfig{blockfrostProjectId} k = do
    baseUrl <- blockfrostBaseUrl blockfrostProjectId
    baseRequest <- parseProviderRequest "Blockfrost" baseUrl
    manager <- newManager tlsManagerSettings
    k
        BlockfrostProvider
            { blockfrostManager = manager
            , blockfrostBaseRequest = baseRequest
            , blockfrostProjectIdHeader = blockfrostProjectId
            }

instance UTxOProvider BlockfrostProvider where
    queryUTxOsByAddress provider address =
        queryAddressPage 1 []
      where
        queryAddressPage :: Int -> [UTxO] -> IO [UTxO]
        queryAddressPage page accumulated = do
            pageUtxos <-
                blockfrostGetJSON
                    provider
                    ("/addresses/" <> address <> "/utxos")
                    [ ("count", Just "100")
                    , ("page", Just (BSC.pack (show page)))
                    ]
            converted <- traverse convertAddressUTxO pageUtxos
            let accumulated' = accumulated <> converted
            if length pageUtxos < 100
                then pure accumulated'
                else queryAddressPage (page + 1) accumulated'

    queryUTxOByRef provider UTxORef{utxoTxId, utxoIndex} = do
        result <-
            blockfrostGetJSONMaybe404
                provider
                ("/txs/" <> utxoTxId <> "/utxos")
                []
        case result of
            Nothing ->
                pure Nothing
            Just BlockfrostTxUTxOs{blockfrostTxOutputs} ->
                traverse
                    (convertTxOutput utxoTxId)
                    ( List.find
                        ( \BlockfrostTxOutput{blockfrostTxOutputIndex} ->
                            blockfrostTxOutputIndex == utxoIndex
                        )
                        blockfrostTxOutputs
                    )

blockfrostBaseUrl :: Text -> IO Text
blockfrostBaseUrl projectId
    | "mainnet" `Text.isPrefixOf` projectId =
        pure "https://cardano-mainnet.blockfrost.io/api/v0"
    | "preprod" `Text.isPrefixOf` projectId =
        pure "https://cardano-preprod.blockfrost.io/api/v0"
    | "preview" `Text.isPrefixOf` projectId =
        pure "https://cardano-preview.blockfrost.io/api/v0"
    | otherwise =
        fail $
            "Blockfrost project id must start with mainnet, preprod, or preview: "
                <> Text.unpack projectId

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

blockfrostGetJSON ::
    (FromJSON a) =>
    BlockfrostProvider ->
    Text ->
    Query ->
    IO a
blockfrostGetJSON provider endpoint query =
    blockfrostRequest provider endpoint query
        >>= decodeProviderJSON "Blockfrost" (endpointText endpoint query)

blockfrostGetJSONMaybe404 ::
    (FromJSON a) =>
    BlockfrostProvider ->
    Text ->
    Query ->
    IO (Maybe a)
blockfrostGetJSONMaybe404 provider endpoint query = do
    response <- performBlockfrostRequest provider endpoint query
    let status = responseStatus response
        code = Status.statusCode status
    if code == 404
        then pure Nothing
        else do
            requireSuccessStatus "Blockfrost" response
            Just
                <$> decodeProviderJSON
                    "Blockfrost"
                    (endpointText endpoint query)
                    response

blockfrostRequest ::
    BlockfrostProvider ->
    Text ->
    Query ->
    IO (Response LBS.ByteString)
blockfrostRequest provider endpoint query = do
    response <- performBlockfrostRequest provider endpoint query
    requireSuccessStatus "Blockfrost" response
    pure response

performBlockfrostRequest ::
    BlockfrostProvider ->
    Text ->
    Query ->
    IO (Response LBS.ByteString)
performBlockfrostRequest
    BlockfrostProvider
        { blockfrostManager
        , blockfrostBaseRequest
        , blockfrostProjectIdHeader
        }
    endpoint
    query = do
        let request =
                (buildRequest blockfrostBaseRequest endpoint query)
                    { requestHeaders =
                        ( "project_id"
                        , Text.encodeUtf8 blockfrostProjectIdHeader
                        )
                            : requestHeaders blockfrostBaseRequest
                    }
        result <-
            try (httpLbs request blockfrostManager) ::
                IO (Either HttpException (Response LBS.ByteString))
        case result of
            Left err ->
                fail $
                    "Blockfrost HTTP request failed for "
                        <> requestEndpoint request
                        <> ": "
                        <> displayException err
            Right response ->
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

convertAddressUTxO :: BlockfrostAddressUTxO -> IO UTxO
convertAddressUTxO
    BlockfrostAddressUTxO
        { blockfrostAddress
        , blockfrostTxHash
        , blockfrostOutputIndex
        , blockfrostAmount
        } = do
        value <- convertAmounts blockfrostAmount
        pure
            UTxO
                { utxoRef =
                    UTxORef
                        { utxoTxId = blockfrostTxHash
                        , utxoIndex = blockfrostOutputIndex
                        }
                , utxoAddress = blockfrostAddress
                , utxoValue = value
                }

convertTxOutput :: Text -> BlockfrostTxOutput -> IO UTxO
convertTxOutput txHash BlockfrostTxOutput{blockfrostTxOutputAddress, blockfrostTxOutputIndex, blockfrostTxOutputAmount} = do
    value <- convertAmounts blockfrostTxOutputAmount
    pure
        UTxO
            { utxoRef =
                UTxORef
                    { utxoTxId = txHash
                    , utxoIndex = blockfrostTxOutputIndex
                    }
            , utxoAddress = blockfrostTxOutputAddress
            , utxoValue = value
            }

convertAmounts :: [BlockfrostAmount] -> IO UTxOValue
convertAmounts =
    foldM
        convertAmount
        UTxOValue
            { utxoLovelace = 0
            , utxoAssets = Map.empty
            }

convertAmount :: UTxOValue -> BlockfrostAmount -> IO UTxOValue
convertAmount value BlockfrostAmount{blockfrostAmountUnit, blockfrostAmountQuantity}
    | blockfrostAmountUnit == "lovelace" =
        pure value{utxoLovelace = blockfrostAmountQuantity}
    | Text.length blockfrostAmountUnit < 56 =
        fail $
            "Blockfrost native asset unit is shorter than a policy id: "
                <> Text.unpack blockfrostAmountUnit
    | otherwise = do
        tokenName <- decodeAssetNameHex "Blockfrost" assetNameHex
        pure
            value
                { utxoAssets =
                    Map.insertWith
                        (Map.unionWith (+))
                        policyId
                        (Map.singleton tokenName blockfrostAmountQuantity)
                        (utxoAssets value)
                }
  where
    policyId = Text.take 56 blockfrostAmountUnit
    assetNameHex = Text.drop 56 blockfrostAmountUnit

decodeAssetNameHex :: String -> Text -> IO Text
decodeAssetNameHex providerName raw =
    case Base16.decode (Text.encodeUtf8 raw) of
        Left err ->
            fail $
                providerName
                    <> " asset name is not valid base16: "
                    <> err
        Right bytes ->
            case Text.decodeUtf8' bytes of
                Left err ->
                    fail $
                        providerName
                            <> " asset name is not valid UTF-8 for CLI token-name text: "
                            <> show err
                Right decoded ->
                    pure decoded

instance FromJSON BlockfrostAddressUTxO where
    parseJSON =
        withObject "Blockfrost address UTxO" $ \object ->
            BlockfrostAddressUTxO
                <$> object .: "address"
                <*> object .: "tx_hash"
                <*> object .: "output_index"
                <*> object .: "amount"

instance FromJSON BlockfrostTxUTxOs where
    parseJSON =
        withObject "Blockfrost transaction UTxOs" $ \object ->
            BlockfrostTxUTxOs
                <$> object .: "outputs"

instance FromJSON BlockfrostTxOutput where
    parseJSON =
        withObject "Blockfrost transaction output" $ \object ->
            BlockfrostTxOutput
                <$> object .: "address"
                <*> object .: "output_index"
                <*> object .: "amount"

instance FromJSON BlockfrostAmount where
    parseJSON =
        withObject "Blockfrost amount" $ \object ->
            BlockfrostAmount
                <$> object .: "unit"
                <*> (unQuantity <$> object .: "quantity")

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
