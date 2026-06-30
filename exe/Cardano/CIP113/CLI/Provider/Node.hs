{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.CIP113.CLI.Provider.Node (
    NodeProvider,
    NodeProviderConfig (..),
    withNodeProvider,
) where

import Cardano.CIP113.CLI.Provider (
    UTxO (..),
    UTxOProvider (..),
    UTxORef (..),
    UTxOValue (..),
 )
import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.Ledger.Address (Addr, decodeAddrEither, serialiseAddr)
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Hashes (ScriptHash (..), extractHash, unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.Provider qualified as Node
import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent.Async (withAsync)
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import Data.Word (Word32)
import Lens.Micro ((^.))
import Ouroboros.Network.Magic (NetworkMagic (..))
import System.Directory (doesPathExist)

data NodeProviderConfig = NodeProviderConfig
    { nodeSocketPath :: !FilePath
    , nodeNetworkMagic :: !Word32
    }
    deriving (Show, Eq)

newtype NodeProvider = NodeProvider
    { nodeProviderBackend :: Node.Provider IO
    }

withNodeProvider :: NodeProviderConfig -> (NodeProvider -> IO a) -> IO a
withNodeProvider NodeProviderConfig{nodeSocketPath, nodeNetworkMagic} k = do
    socketExists <- doesPathExist nodeSocketPath
    if socketExists
        then do
            lsqCh <- newLSQChannel 64
            ltxsCh <- newLTxSChannel 64
            withAsync
                ( void $
                    runNodeClient
                        (NetworkMagic nodeNetworkMagic)
                        nodeSocketPath
                        lsqCh
                        ltxsCh
                )
                $ \_ ->
                    k (NodeProvider (mkN2CProvider lsqCh))
        else fail ("node socket path does not exist: " <> nodeSocketPath)

instance UTxOProvider NodeProvider where
    queryUTxOsByAddress provider rawAddress = do
        address <- parseNodeAddress rawAddress
        utxos <- Node.queryUTxOs (nodeProviderBackend provider) address
        traverse convertUTxO utxos

    queryUTxOByRef provider ref = do
        txIn <- parseNodeTxIn ref
        utxos <-
            Node.queryUTxOByTxIn
                (nodeProviderBackend provider)
                (Set.singleton txIn)
        traverse (\txOut -> convertUTxO (txIn, txOut)) (Map.lookup txIn utxos)

parseNodeAddress :: Text -> IO Addr
parseNodeAddress raw =
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
                        "failed to parse node address as bech32 Cardano address ("
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

parseNodeTxIn :: UTxORef -> IO TxIn
parseNodeTxIn UTxORef{utxoTxId, utxoIndex} = do
    txIdBytes <- decodeHexText "transaction id" utxoTxId
    txIdHash <-
        case hashFromBytes txIdBytes of
            Just hash ->
                pure hash
            Nothing ->
                fail "UTxO reference transaction id must be 32 bytes of base16"
    pure $
        TxIn
            (TxId (unsafeMakeSafeHash txIdHash))
            (TxIx (fromIntegral utxoIndex))

convertUTxO :: (TxIn, TxOut ConwayEra) -> IO UTxO
convertUTxO (txIn, txOut) = do
    value <- convertValue (txOut ^. valueTxOutL)
    pure
        UTxO
            { utxoRef = convertTxIn txIn
            , utxoAddress = addressText (txOut ^. addrTxOutL)
            , utxoValue = value
            }

convertTxIn :: TxIn -> UTxORef
convertTxIn (TxIn (TxId safeHash) (TxIx ix)) =
    UTxORef
        { utxoTxId = hexText (hashToBytes (extractHash safeHash))
        , utxoIndex = fromIntegral ix
        }

convertValue :: MaryValue -> IO UTxOValue
convertValue (MaryValue (Coin lovelace) multiAsset) = do
    assets <- convertAssets multiAsset
    pure
        UTxOValue
            { utxoLovelace = lovelace
            , utxoAssets = assets
            }

convertAssets :: MultiAsset -> IO (Map Text (Map Text Integer))
convertAssets (MultiAsset assets) =
    Map.fromList <$> traverse convertPolicy (Map.toAscList assets)

convertPolicy :: (PolicyID, Map AssetName Integer) -> IO (Text, Map Text Integer)
convertPolicy (policy, assets) = do
    assets' <- traverseKeys assetNameText assets
    pure (policyText policy, assets')

traverseKeys :: (Ord k2) => (k1 -> IO k2) -> Map k1 v -> IO (Map k2 v)
traverseKeys convertKey input =
    Map.fromList <$> traverse convertEntry (Map.toAscList input)
  where
    convertEntry (key, value) = do
        key' <- convertKey key
        pure (key', value)

assetNameText :: AssetName -> IO Text
assetNameText (AssetName nameBytes) =
    case Text.decodeUtf8' (SBS.fromShort nameBytes) of
        Right name ->
            pure name
        Left err ->
            fail $
                "asset name is not valid UTF-8 for CLI token-name text: "
                    <> show err

addressText :: Addr -> Text
addressText =
    hexText . serialiseAddr

policyText :: PolicyID -> Text
policyText (PolicyID (ScriptHash policyHash)) =
    hexText (hashToBytes policyHash)

decodeHexText :: String -> Text -> IO ByteString
decodeHexText label raw =
    case Base16.decode (Text.encodeUtf8 raw) of
        Right bytes ->
            pure bytes
        Left err ->
            fail ("invalid " <> label <> " base16: " <> err)

hexText :: ByteString -> Text
hexText =
    Text.decodeUtf8 . Base16.encode
