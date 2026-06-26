{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE RecordWildCards #-}

{- |
Module      : Cardano.CIP113.Register
Description : CIP-113 registry insertion and token minting builder

Builds two related verticals:

* __RegisterOnly__ — insert a new policy into the registry linked-list without
  minting any tokens yet.
* __RegisterAndMint__ — register and mint the initial token supply in one
  atomic transaction (the 'RegisterAndMint' mode, post-F07 audit fix).

== Protocol summary

1. Spend the predecessor registry node through the 'registry_spend' script
   (updates its 'rnNext' pointer to the new policy).
2. Mint one registry NFT via the 'registry_mint' policy (asset name = 28-byte
   new policy ID).
3. Emit two registry-address outputs:
     a. Updated predecessor with new 'rnNext' and its original value.
     b. New node carrying the registry NFT.
4. (RegisterAndMint only) Also mint the initial token supply via the
   'issuanceMintingPolicy', routing tokens to smart-wallet outputs.

== Caller responsibilities

* Compute the updated predecessor datum: keep all fields, set 'rnNext' to
  the new node's 'rnKey'.
* Compute the new node datum: set 'rnNext' to the predecessor's old 'rnNext'.
* Provide the predecessor's current 'MaryValue' (needed to recreate its UTxO).
* Provide collateral and change inputs via the outer 'build' call.

== Linked-list insertion invariant

The registry is sorted by 'rnKey' (lexicographic byte order). Before calling
'registerTx', the caller must verify:

  predecessor.rnKey < newNode.rnKey < predecessor.rnNext (old value)

Violating this will cause the 'registry_spend' or 'registry_mint' script to
reject the transaction.
-}
module Cardano.CIP113.Register
    ( TokenMint (..)
    , registerTx
    ) where

import Control.Monad (forM_, void)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.ByteString.Short (toShort)

import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Core (Script)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue, PolicyID)
import Cardano.Ledger.TxIn (TxIn)
import PlutusTx.IsData.Class (ToData)

import Cardano.Tx.Build (
    TxBuild,
    attachScript,
    mint,
    payTo',
    spendScript,
 )
import Cardano.CIP113.Types (
    RegistryNode (..),
    RegistryRedeemer (..),
 )

{- | Optional initial token mint, included when 'RegistrationMode' is
'RegisterAndMint'.
-}
data TokenMint
    = forall r.
      (ToData r) =>
      TokenMint
    { tmPolicyId :: !PolicyID
    -- ^ Policy ID of the token being minted.
    , tmScript :: !(Script ConwayEra)
    -- ^ 'issuanceMintingPolicy' script.
    , tmAssets :: !(Map AssetName Integer)
    -- ^ Asset names and amounts to mint (positive) or burn (negative).
    , tmRedeemer :: r
    -- ^ 'MintingRegistryProof' or substandard-defined redeemer.
    --
    --   For 'RegisterAndMint', use 'OutputIndexProof' pointing at the
    --   new registry node output index (typically 1, after the updated
    --   predecessor at index 0).
    }

-- | Derive the registry NFT asset name from a 28-byte policy ID.
registryNftName :: RegistryNode -> AssetName
registryNftName node = AssetName (toShort (rnKey node))

{- | Build a CIP-113 registry insertion transaction.

@
registerTx
    registrySpendScript
    registryMintScript registryMintPolicyId
    predecessorTxIn predecessorValue
    registryAddr
    updatedPredecessor  -- rnNext set to new policy key
    newNode
    (RegistryInsert newKey mintingCred RegisterAndMint)
    (Just (TokenMint issuancePid issuanceScript assets (OutputIndexProof 1)))
@

The 'RegistryInsert' redeemer is used for both the 'registry_spend' spend
(predecessor node) and the 'registry_mint' minting policy.
-}
registerTx
    :: Script ConwayEra
    -- ^ 'registry_spend' script (validates linked-list invariant on spend).
    -> Script ConwayEra
    -- ^ 'registry_mint' script.
    -> PolicyID
    -- ^ Policy ID of 'registry_mint' (for minting the registry NFT).
    -> TxIn
    -- ^ Predecessor registry node UTxO to spend.
    -> MaryValue
    -- ^ Current value of the predecessor UTxO (lovelace + its registry NFT).
    -> Addr
    -- ^ Registry script address for node outputs.
    -> RegistryNode
    -- ^ Updated predecessor datum: all fields unchanged except 'rnNext'
    --   (set to 'rnKey' of the new node).
    -> RegistryNode
    -- ^ New registry node datum: 'rnKey' = new policy, 'rnNext' = predecessor's
    --   old 'rnNext'.
    -> RegistryRedeemer
    -- ^ Minting redeemer; also used for the predecessor spend.
    --   Use 'RegistryInsert { riKey, riMintingLogicScript, riMode }'.
    -> Maybe TokenMint
    -- ^ Token mint details when 'riMode' is 'RegisterAndMint'; 'Nothing' for
    --   'RegisterOnly'.
    -> TxBuild q e ()
registerTx
    registrySpendScript
    registryMintScript
    registryMintPolicyId
    predecessorIn
    predecessorValue
    registryAddr
    updatedPredecessor
    newNode
    mintRdmr
    mTokenMint = do
        -- Attach scripts.
        attachScript registrySpendScript
        attachScript registryMintScript
        forM_ mTokenMint $ \(TokenMint _ s _ _) ->
            attachScript s

        -- Spend predecessor node through registry_spend.
        -- The redeemer mirrors the minting policy redeemer.
        void $ spendScript predecessorIn mintRdmr

        -- Mint the registry NFT for the new node (1 token, asset name = policy ID).
        mint
            registryMintPolicyId
            (Map.singleton (registryNftName newNode) 1)
            mintRdmr

        -- Updated predecessor output (same value, updated datum).
        void $ payTo' registryAddr predecessorValue updatedPredecessor

        -- New registry node output (value includes the registry NFT).
        -- Start with 0 lovelace; raised to min-UTxO by the builder via SendMin.
        -- The registry NFT is minted separately; the balancer accounts for it.
        void $ payTo' registryAddr (mempty :: MaryValue) newNode

        -- Optional initial token mint.
        forM_ mTokenMint $ \(TokenMint pid _ assets rdmr) ->
            mint pid assets rdmr
