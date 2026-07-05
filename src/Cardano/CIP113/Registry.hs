{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.Registry (
    RegistryResolverError (..),
    RegistryNodeUtxo (..),
    ResolvedRegistryNode (..),
    findInsertionPoint,
    findNode,
) where

import Data.ByteString (ByteString)
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Lens.Micro ((^.))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (fromBuiltinData)

import Cardano.Ledger.Api.Scripts.Data (getPlutusData)
import Cardano.Ledger.Api.Tx.Out (TxOut, dataTxOutL)
import Cardano.Ledger.BaseTypes (StrictMaybe (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Provider (Provider (..))

import Cardano.CIP113.Deployment (CIP113Deployment (..))
import Cardano.CIP113.Types (RegistryNode (..), originNode, sentinelNext)

data RegistryResolverError
    = RegistryOriginMissing
    | RegistryDatumMissing TxIn
    | RegistryDatumDecodeFailed TxIn
    | RegistryBrokenLink ByteString
    | RegistryCycle ByteString
    deriving (Show, Eq)

data RegistryNodeUtxo = RegistryNodeUtxo
    { rnuTxIn :: !TxIn
    , rnuTxOut :: !(TxOut ConwayEra)
    , rnuNode :: !RegistryNode
    }
    deriving (Show, Eq)

data ResolvedRegistryNode = ResolvedRegistryNode
    { rrnUtxo :: !RegistryNodeUtxo
    , rrnReferenceInputIndex :: !Int
    }
    deriving (Show, Eq)

findInsertionPoint ::
    (Monad m) =>
    CIP113Deployment ->
    Provider m ->
    ByteString ->
    m (Either RegistryResolverError RegistryNodeUtxo)
findInsertionPoint deployment provider targetKey =
    traverseRegistry deployment provider (findPredecessor targetKey)

findNode ::
    (Monad m) =>
    CIP113Deployment ->
    Provider m ->
    [TxIn] ->
    ByteString ->
    m (Either RegistryResolverError (Maybe ResolvedRegistryNode))
findNode deployment provider otherReferenceInputs targetKey =
    fmap (fmap withReferenceInputIndex)
        <$> traverseRegistry deployment provider (findExisting targetKey)
  where
    withReferenceInputIndex utxo =
        ResolvedRegistryNode
            { rrnUtxo = utxo
            , rrnReferenceInputIndex =
                referenceInputIndex (rnuTxIn utxo) otherReferenceInputs
            }

traverseRegistry ::
    (Monad m) =>
    CIP113Deployment ->
    Provider m ->
    (Map.Map ByteString RegistryNodeUtxo -> RegistryNodeUtxo -> Either RegistryResolverError a) ->
    m (Either RegistryResolverError a)
traverseRegistry CIP113Deployment{..} Provider{..} resolve = do
    utxos <- queryUTxOs dRegistryAddr
    pure $ do
        nodeMap <- registryNodeMap utxos
        originUtxo <-
            maybe
                (Left RegistryOriginMissing)
                Right
                (Map.lookup (rnKey originNode) nodeMap)
        resolve nodeMap originUtxo

registryNodeMap ::
    [(TxIn, TxOut ConwayEra)] ->
    Either RegistryResolverError (Map.Map ByteString RegistryNodeUtxo)
registryNodeMap utxos =
    Map.fromList . fmap keyedNode <$> traverse decodeRegistryNodeUtxo utxos
  where
    keyedNode utxo = (rnKey (rnuNode utxo), utxo)

decodeRegistryNodeUtxo ::
    (TxIn, TxOut ConwayEra) ->
    Either RegistryResolverError RegistryNodeUtxo
decodeRegistryNodeUtxo (rnuTxIn, rnuTxOut) = do
    datum <- case rnuTxOut ^. dataTxOutL of
        SNothing -> Left (RegistryDatumMissing rnuTxIn)
        SJust d -> Right d
    rnuNode <-
        maybe
            (Left (RegistryDatumDecodeFailed rnuTxIn))
            Right
            (fromBuiltinData (BuiltinData (getPlutusData datum)))
    Right RegistryNodeUtxo{..}

findPredecessor ::
    ByteString ->
    Map.Map ByteString RegistryNodeUtxo ->
    RegistryNodeUtxo ->
    Either RegistryResolverError RegistryNodeUtxo
findPredecessor targetKey nodeMap =
    walk Set.empty
  where
    walk seen current@RegistryNodeUtxo{rnuNode = RegistryNode{..}}
        | rnKey `Set.member` seen = Left (RegistryCycle rnKey)
        | targetKey > rnKey && (rnNext == sentinelNext || targetKey < rnNext) =
            Right current
        | rnNext == sentinelNext = Right current
        | otherwise =
            case Map.lookup rnNext nodeMap of
                Nothing -> Left (RegistryBrokenLink rnNext)
                Just next -> walk (Set.insert rnKey seen) next

findExisting ::
    ByteString ->
    Map.Map ByteString RegistryNodeUtxo ->
    RegistryNodeUtxo ->
    Either RegistryResolverError (Maybe RegistryNodeUtxo)
findExisting targetKey nodeMap =
    walk Set.empty
  where
    walk seen current@RegistryNodeUtxo{rnuNode = RegistryNode{..}}
        | rnKey `Set.member` seen = Left (RegistryCycle rnKey)
        | rnKey == targetKey = Right (Just current)
        | rnNext == sentinelNext = Right Nothing
        | otherwise =
            case Map.lookup rnNext nodeMap of
                Nothing -> Left (RegistryBrokenLink rnNext)
                Just next -> walk (Set.insert rnKey seen) next

referenceInputIndex :: TxIn -> [TxIn] -> Int
referenceInputIndex nodeIn otherReferenceInputs =
    case List.elemIndex nodeIn (List.sort (nodeIn : otherReferenceInputs)) of
        Just ix -> ix
        Nothing -> error "registry node missing from reference inputs"
