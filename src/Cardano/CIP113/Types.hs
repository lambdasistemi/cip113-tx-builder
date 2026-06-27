{- |
Module      : Cardano.CIP113.Types
Description : Plutus Data types for CIP-113 programmable tokens

On-chain type encodings, tracked from the Aiken reference implementation at
cardano-foundation/cip113-programmable-tokens. The Java off-chain backend
is behind audit fixes F07 (RegistryInsert mode field) and F10
(SmartTokenMintingAction wrapper removed), so the Aiken source is authoritative.

All 'ToData' instances match the Aiken encoding exactly. 'FromData' instances
are provided for types that callers need to read from the chain (e.g. when
building the predecessor node update for 'registerTx').
-}
module Cardano.CIP113.Types (
    -- * PLG redeemers
    PLGRedeemer (..),
    RegistryProof (..),

    -- * Registry node datum
    RegistryNode (..),
    CIP113Credential (..),
    sentinelNext,
    originNode,

    -- * Registry mint redeemer
    RegistryRedeemer (..),
    RegistrationMode (..),

    -- * Issuance mint redeemer (post-F10 audit)
    MintingRegistryProof (..),
) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS

import PlutusCore.Data (Data (..))
import PlutusTx.Builtins (fromBuiltin, toBuiltin)
import PlutusTx.Builtins.Internal (BuiltinByteString, BuiltinData (..))
import PlutusTx.IsData.Class (FromData (..), ToData (..))

-- ----------------------------------------------------
-- Internal helpers
-- ----------------------------------------------------

-- Construct a Constr node. Unwraps and rewraps BuiltinData.
mkConstrD :: Integer -> [BuiltinData] -> BuiltinData
mkConstrD tag fields = BuiltinData $ Constr tag (map (\(BuiltinData d) -> d) fields)

-- Encode a list of BuiltinData as a Plutus List.
mkListD :: [BuiltinData] -> BuiltinData
mkListD ds = BuiltinData $ List (map (\(BuiltinData d) -> d) ds)

-- Encode a ByteString as Plutus B.
mkBsD :: ByteString -> BuiltinData
mkBsD = toBuiltinData . toBuiltin

-- Decode a ByteString field.
decodeBs :: Data -> Maybe ByteString
decodeBs d =
    fromBuiltin
        <$> (fromBuiltinData (BuiltinData d) :: Maybe BuiltinByteString)

-- Decode a CIP113Credential field.
decodeCred :: Data -> Maybe CIP113Credential
decodeCred d = fromBuiltinData (BuiltinData d)

-- Decode a list of ByteStrings.
decodeBsList :: Data -> Maybe [ByteString]
decodeBsList (List ds) = traverse decodeBs ds
decodeBsList _ = Nothing

-- ----------------------------------------------------
-- PLG redeemers
-- ----------------------------------------------------

{- | Proof that a policy is (or is not) in the registry.

Carried in 'TransferAct' for each token present in the transfer inputs.
The index points to the registry node UTxO supplied as a reference input:

  TokenExists     — the node at @node_idx@ holds this policy as its key
  TokenDoesNotExist — the node at @node_idx@ is the covering node whose
                      key < this policy < node.next (proving non-membership)
-}
data RegistryProof
    = TokenExists {-# UNPACK #-} !Int
    | TokenDoesNotExist {-# UNPACK #-} !Int
    deriving (Show, Eq)

instance ToData RegistryProof where
    toBuiltinData (TokenExists i) =
        mkConstrD 0 [toBuiltinData (toInteger i)]
    toBuiltinData (TokenDoesNotExist i) =
        mkConstrD 1 [toBuiltinData (toInteger i)]

{- | Redeemer for the 'programmableLogicGlobal' withdrawal script.

Invoked via the withdraw-zero pattern (zero-lovelace withdrawal from PLG's
staking credential) in every transaction that moves programmable tokens.

  TransferAct   — user-initiated transfer; proofs cover every token in inputs
  ThirdPartyAct — admin seizure/freeze; targets a single policy at a time
  UnfrackingAct — split bloated smart-wallet UTxOs without invoking transfer logic
-}
data PLGRedeemer
    = -- | Constr 0 [List<RegistryProof>]
      TransferAct [RegistryProof]
    | -- | Constr 1 [Int, Int]
      ThirdPartyAct
        { registryNodeIdx :: !Int
        {- ^ Index into the transaction's reference inputs pointing at the
        registry node for the token being administered.
        -}
        , outputsStartIdx :: !Int
        {- ^ First output index in the body that belongs to this ThirdPartyAct
        (the validator checks outputs from this index onward).
        -}
        }
    | -- | Constr 2 []
      UnfrackingAct
    deriving (Show, Eq)

instance ToData PLGRedeemer where
    toBuiltinData (TransferAct proofs) =
        mkConstrD 0 [mkListD (map toBuiltinData proofs)]
    toBuiltinData (ThirdPartyAct ni oi) =
        mkConstrD
            1
            [ toBuiltinData (toInteger ni)
            , toBuiltinData (toInteger oi)
            ]
    toBuiltinData UnfrackingAct =
        mkConstrD 2 []

-- ----------------------------------------------------
-- CIP-113 Credential
-- ----------------------------------------------------

{- | Cardano credential (standard Plutus encoding).

Wraps a 28-byte hash of either a verification key or a script.
Matches the on-chain 'Credential' type in cardano-ledger and Aiken.
-}
data CIP113Credential
    = -- | Constr 0 [B hash]
      VKeyCredential !ByteString
    | -- | Constr 1 [B hash]
      ScriptCredential !ByteString
    deriving (Show, Eq)

instance ToData CIP113Credential where
    toBuiltinData (VKeyCredential h) = mkConstrD 0 [mkBsD h]
    toBuiltinData (ScriptCredential h) = mkConstrD 1 [mkBsD h]

instance FromData CIP113Credential where
    fromBuiltinData (BuiltinData (Constr 0 [f])) =
        VKeyCredential <$> decodeBs f
    fromBuiltinData (BuiltinData (Constr 1 [f])) =
        ScriptCredential <$> decodeBs f
    fromBuiltinData _ = Nothing

-- ----------------------------------------------------
-- Registry node datum
-- ----------------------------------------------------

{- | Datum on every UTxO in the registry linked-list.

The list is sorted lexicographically by 'rnKey'. The head node has an empty
key; the tail sentinel uses 'sentinelNext' (30 × 0xff) as both key and next.

Field order is load-bearing for CBOR layout (Aiken reads positionally):
  0 key, 1 next, 2 minting, 3 transfer, 4 third-party, 5 global-state, 6 prefixes
-}
data RegistryNode = RegistryNode
    { rnKey :: !ByteString
    -- ^ 28-byte policy ID of the registered token (empty for the origin node).
    , rnNext :: !ByteString
    -- ^ 28-byte key of the next node; 'sentinelNext' at the list tail.
    , rnMintingLogicScript :: !CIP113Credential
    -- ^ Substandard issuance script, invoked via withdraw-zero during minting.
    , rnTransferLogicScript :: !CIP113Credential
    -- ^ Substandard transfer-rule script.
    , rnThirdPartyTransferLogicScript :: !CIP113Credential
    -- ^ Substandard admin/seizure script.
    , rnGlobalStateCs :: !ByteString
    -- ^ Optional global-state NFT policy (empty if unused).
    , rnProtectedPrefixes :: ![ByteString]
    -- ^ CIP-67 4-byte asset-name prefixes exempt from seizure (e.g. reference NFTs).
    }
    deriving (Show, Eq)

-- | Sentinel value for the 'rnNext' field of the last node: 30 × 0xff.
sentinelNext :: ByteString
sentinelNext = BS.replicate 30 0xff

-- | The origin (head) node of an empty registry. Insert after this.
originNode :: RegistryNode
originNode =
    RegistryNode
        { rnKey = BS.empty
        , rnNext = sentinelNext
        , rnMintingLogicScript = VKeyCredential BS.empty
        , rnTransferLogicScript = VKeyCredential BS.empty
        , rnThirdPartyTransferLogicScript = VKeyCredential BS.empty
        , rnGlobalStateCs = BS.empty
        , rnProtectedPrefixes = []
        }

instance ToData RegistryNode where
    toBuiltinData RegistryNode{..} =
        mkConstrD
            0
            [ mkBsD rnKey
            , mkBsD rnNext
            , toBuiltinData rnMintingLogicScript
            , toBuiltinData rnTransferLogicScript
            , toBuiltinData rnThirdPartyTransferLogicScript
            , mkBsD rnGlobalStateCs
            , mkListD (map mkBsD rnProtectedPrefixes)
            ]

instance FromData RegistryNode where
    fromBuiltinData
        ( BuiltinData
                ( Constr
                        0
                        [ k
                            , n
                            , m
                            , t
                            , tp
                            , g
                            , p
                            ]
                    )
            ) = do
            rnKey <- decodeBs k
            rnNext <- decodeBs n
            rnMintingLogicScript <- decodeCred m
            rnTransferLogicScript <- decodeCred t
            rnThirdPartyTransferLogicScript <- decodeCred tp
            rnGlobalStateCs <- decodeBs g
            rnProtectedPrefixes <- decodeBsList p
            pure RegistryNode{..}
    fromBuiltinData _ = Nothing

-- ----------------------------------------------------
-- Registry mint redeemer
-- ----------------------------------------------------

{- | Whether to register alone or register-and-mint in one atomic step.

Post-F07 audit fix: 'RegistryInsert' now carries an explicit 'RegistrationMode'
field. The Java backend (which omits this field) is behind this fix.
-}
data RegistrationMode
    = -- | Constr 0 [] — register first, mint separately later.
      RegisterOnly
    | -- | Constr 1 [] — register and mint initial supply atomically.
      RegisterAndMint
    deriving (Show, Eq)

instance ToData RegistrationMode where
    toBuiltinData RegisterOnly = mkConstrD 0 []
    toBuiltinData RegisterAndMint = mkConstrD 1 []

{- | Redeemer for the 'registry_mint' minting policy.

'RegistryInsert' carries the 28-byte policy key being registered, the
credential of the minting-logic script that will govern issuance, and
the registration mode (see 'RegistrationMode').
-}
data RegistryRedeemer
    = -- | Constr 0 [] — one-time initialisation of the origin node.
      RegistryInit
    | -- | Constr 1 [B key, Credential, RegistrationMode]
      RegistryInsert
        { riKey :: !ByteString
        -- ^ 28-byte policy ID being inserted.
        , riMintingLogicScript :: !CIP113Credential
        -- ^ Credential of the issuance/minting logic script.
        , riMode :: !RegistrationMode
        }
    deriving (Show, Eq)

instance ToData RegistryRedeemer where
    toBuiltinData RegistryInit = mkConstrD 0 []
    toBuiltinData RegistryInsert{..} =
        mkConstrD
            1
            [ mkBsD riKey
            , toBuiltinData riMintingLogicScript
            , toBuiltinData riMode
            ]

-- ----------------------------------------------------
-- Issuance mint redeemer
-- ----------------------------------------------------

{- | Redeemer for the 'issuanceMintingPolicy' script.

Post-F10 audit fix: the 'SmartTokenMintingAction' wrapper and the redundant
'minting_logic_cred' field have been removed. The Java backend still uses the
pre-F10 shape; ignore it.

  RefInput    — proves registration via an existing registry node supplied as
                a reference input at the given index.
  OutputIndex — proves registration via a new registry node being created at
                the given output index in the same transaction ('RegisterAndMint').
-}
data MintingRegistryProof
    = -- | Constr 0 [Int]
      RefInputProof !Int
    | -- | Constr 1 [Int]
      OutputIndexProof !Int
    deriving (Show, Eq)

instance ToData MintingRegistryProof where
    toBuiltinData (RefInputProof i) =
        mkConstrD 0 [toBuiltinData (toInteger i)]
    toBuiltinData (OutputIndexProof i) =
        mkConstrD 1 [toBuiltinData (toInteger i)]
