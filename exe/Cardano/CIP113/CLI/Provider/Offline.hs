{-# LANGUAGE OverloadedStrings #-}

module Cardano.CIP113.CLI.Provider.Offline (
    OfflineUTxOProvider,
    loadOfflineUTxOProvider,
) where

import Control.Monad (foldM)
import Data.Aeson (
    FromJSON (parseJSON),
    Value,
    eitherDecodeFileStrict,
    withObject,
    (.:),
 )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Text.Read (readMaybe)

import Cardano.CIP113.CLI.Provider (
    UTxO (..),
    UTxOProvider (..),
    UTxORef (..),
    UTxOValue (..),
 )

newtype OfflineUTxOProvider = OfflineUTxOProvider
    { offlineUTxOs :: Map UTxORef UTxO
    }
    deriving (Show, Eq)

newtype CardanoCliUTxOFile = CardanoCliUTxOFile
    { unCardanoCliUTxOFile :: Map UTxORef UTxO
    }

newtype CardanoCliValue = CardanoCliValue
    { unCardanoCliValue :: UTxOValue
    }

loadOfflineUTxOProvider :: FilePath -> IO OfflineUTxOProvider
loadOfflineUTxOProvider path = do
    decoded <- eitherDecodeFileStrict path
    case decoded of
        Left err ->
            fail ("failed to load UTxO JSON from " <> path <> ": " <> err)
        Right utxoFile ->
            pure (OfflineUTxOProvider (unCardanoCliUTxOFile utxoFile))

instance UTxOProvider OfflineUTxOProvider where
    queryUTxOsByAddress provider address =
        pure
            [ utxo
            | utxo <- Map.elems (offlineUTxOs provider)
            , utxoAddress utxo == address
            ]

    queryUTxOByRef provider ref =
        pure (Map.lookup ref (offlineUTxOs provider))

instance FromJSON CardanoCliUTxOFile where
    parseJSON =
        withObject "cardano-cli UTxO output" $ \object ->
            CardanoCliUTxOFile . Map.fromList
                <$> traverse
                    parseUTxOEntry
                    (KeyMap.toList object)

parseUTxOEntry :: (Key.Key, Value) -> Parser (UTxORef, UTxO)
parseUTxOEntry (key, entryValue) = do
    ref <- parseUTxORef (Key.toText key)
    utxo <-
        withObject
            "UTxO entry"
            ( \object -> do
                address <- object .: "address"
                parsedValue <- object .: "value"
                pure
                    UTxO
                        { utxoRef = ref
                        , utxoAddress = address
                        , utxoValue = unCardanoCliValue parsedValue
                        }
            )
            entryValue
    pure (ref, utxo)

parseUTxORef :: Text -> Parser UTxORef
parseUTxORef raw =
    case Text.breakOnEnd "#" raw of
        ("", _) ->
            fail ("UTxO reference is missing '#': " <> Text.unpack raw)
        (txIdWithHash, indexText) ->
            case readMaybe (Text.unpack indexText) of
                Just index ->
                    pure
                        UTxORef
                            { utxoTxId = Text.dropEnd 1 txIdWithHash
                            , utxoIndex = index
                            }
                Nothing ->
                    fail ("UTxO reference has invalid index: " <> Text.unpack raw)

instance FromJSON CardanoCliValue where
    parseJSON =
        withObject "UTxO value" $ \object -> do
            lovelace <- object .: "lovelace"
            assets <- foldM parseAssetPolicy Map.empty (KeyMap.toList object)
            pure
                ( CardanoCliValue
                    UTxOValue
                        { utxoLovelace = lovelace
                        , utxoAssets = assets
                        }
                )

parseAssetPolicy ::
    Map Text (Map Text Integer) ->
    (Key.Key, Value) ->
    Parser (Map Text (Map Text Integer))
parseAssetPolicy assets (policyKey, value)
    | policy == "lovelace" = pure assets
    | otherwise = do
        policyAssets <-
            withObject
                "asset policy"
                ( \object ->
                    Map.fromList
                        <$> traverse
                            parseAssetQuantity
                            (KeyMap.toList object)
                )
                value
        pure (Map.insert policy policyAssets assets)
  where
    policy = Key.toText policyKey

parseAssetQuantity :: (Key.Key, Value) -> Parser (Text, Integer)
parseAssetQuantity (assetKey, value) =
    (,) (Key.toText assetKey) <$> parseJSON value
