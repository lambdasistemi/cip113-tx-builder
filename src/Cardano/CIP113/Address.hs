{- |
Module      : Cardano.CIP113.Address
Description : Smart wallet address derivation for CIP-113

CIP-113 tokens always reside at "smart wallet" addresses whose payment
credential is the 'programmableLogicBase' (PLB) script hash and whose
staking credential is the user's own stake credential. Ownership is
therefore encoded in the staking part of the address, not in a datum.

This deterministic derivation requires no on-chain registration step —
tokens appear at a user's smart wallet as soon as any transaction sends
them there.
-}
module Cardano.CIP113.Address
    ( -- * Smart wallet
      smartWalletAddr

      -- * PLG accounting
    , plgAccountAddress
    ) where

import Cardano.Ledger.Address (AccountAddress (..), AccountId (..), Addr (..))
import Cardano.Ledger.BaseTypes (Network)
import Cardano.Ledger.Credential (
    Credential (..),
    StakeReference (..),
 )
import Cardano.Ledger.Hashes (ScriptHash)
import Cardano.Ledger.Keys (KeyRole (Staking))

{- | Derive the smart wallet address for a user.

@smartWalletAddr network plbHash userStakeCred@ returns the address
@BaseAddress(Script(plbHash), userStakeCred)@.

The payment part is always the PLB script hash (shared across all
programmable token holders on that deployment). The staking part is
what distinguishes one user's wallet from another.

The @userStakeCred@ may be either a key-hash or a script credential;
both are valid staking credentials on Cardano.
-}
smartWalletAddr
    :: Network
    -> ScriptHash
    -- ^ Hash of the deployed 'programmableLogicBase' script.
    -> Credential Staking
    -- ^ User's staking credential (key-hash or script).
    -> Addr
smartWalletAddr network plbHash userStakeCred =
    Addr network (ScriptHashObj plbHash) (StakeRefBase userStakeCred)

{- | Derive the reward/staking account address for PLG withdraw-zero.

Every CIP-113 transfer or admin transaction invokes the
'programmableLogicGlobal' withdrawal script by making a zero-lovelace
withdrawal from this account. The account credential is the PLG script
hash.

Callers must include this as the 'AccountAddress' argument to
'withdrawScript' in the transaction builder.
-}
plgAccountAddress
    :: Network
    -> ScriptHash
    -- ^ Hash of the deployed 'programmableLogicGlobal' script.
    -> AccountAddress
plgAccountAddress network plgHash =
    AccountAddress network (AccountId (ScriptHashObj plgHash))
