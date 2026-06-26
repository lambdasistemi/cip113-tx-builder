{-# LANGUAGE ExistentialQuantification #-}

{- |
Module      : Cardano.CIP113.Transfer
Description : CIP-113 token transfer transaction builder

Builds the 'TransferAct' flow: user-initiated movement of programmable
tokens between smart wallets.

== Protocol summary

1. Spend each source smart-wallet UTxO through the PLB script.
2. Invoke PLG via a zero-lovelace withdrawal ('withdrawScript'), passing
   'TransferAct' with one 'RegistryProof' per token present in the inputs.
3. Include registry node UTxOs as reference inputs — validators read them
   to verify proofs.
4. For each __registered__ token, invoke its 'transferLogicScript' (also via
   withdraw-zero); the substandard's script enforces its own rules (allowlist,
   KYC, etc.).
5. Send outputs to smart-wallet addresses (derived via 'smartWalletAddr').

== Caller responsibilities

* Compute the correct 'RegistryProof' for each token:
    - 'TokenExists' i   — reference input i is the node whose key == this policy.
    - 'TokenDoesNotExist' i — reference input i is the covering node proving
      non-membership.
* Supply a 'TransferLogic' for every __registered__ token appearing in the
  inputs; omitting one causes the PLG script to reject the transaction.
* Ensure all outputs target smart-wallet addresses; plain addresses reject.
* Provide collateral and change inputs via the outer 'build' call.
-}
module Cardano.CIP113.Transfer
    ( TransferInput (..)
    , TransferLogic (..)
    , transferTx
    ) where

import Control.Monad (forM_, void)

import Cardano.Ledger.Address (AccountAddress, Addr)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Core (Script)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Mary.Value (MaryValue)
import Cardano.Ledger.TxIn (TxIn)
import PlutusTx.IsData.Class (ToData)

import Cardano.Tx.Build (
    TxBuild,
    attachScript,
    payTo,
    reference,
    spendScript,
    withdrawScript,
 )
import Cardano.CIP113.Types (PLGRedeemer (..), RegistryProof)

-- | One input from a smart wallet, paired with its registry membership proof.
data TransferInput = TransferInput
    { tiTxIn :: !TxIn
    -- ^ UTxO at the smart wallet address.
    , tiProof :: !RegistryProof
    -- ^ Proof of registry status for the token(s) in this UTxO.
    --
    --   If the UTxO holds multiple programmable tokens, include one
    --   'TransferInput' per distinct policy, all pointing to the same 'tiTxIn'.
    }
    deriving (Show, Eq)

{- | A substandard transfer-logic script that must run in the transaction.

Include one 'TransferLogic' for each __registered__ token present in the
transfer inputs. Unregistered tokens (proved via 'TokenDoesNotExist') do
not require a corresponding entry.
-}
data TransferLogic
    = forall r.
      (ToData r) =>
      TransferLogic
    { tlAccount :: !AccountAddress
    -- ^ PLG-style staking account for the transfer-logic script.
    --   Used for the withdraw-zero invocation.
    , tlScript :: !(Script ConwayEra)
    -- ^ The substandard's transfer-logic Plutus script.
    , tlRedeemer :: r
    -- ^ Redeemer for this invocation (substandard-defined).
    }

{- | Build a CIP-113 token transfer transaction.

Returns a 'TxBuild' program that, when passed to 'build', produces a
balanced Conway transaction satisfying the PLG transfer protocol.

@
transferTx
    (plgAccountAddress Mainnet plgHash)
    plbScript
    plgScript
    [ TransferInput aliceIn (TokenExists 0)
    , TransferInput aliceIn (TokenExists 1)  -- second token, same UTxO
    ]
    [registryNodeRef0, registryNodeRef1]
    [ TransferLogic usdmTransferAccount usdmTransferScript ()
    , TransferLogic eurmTransferAccount eurmTransferScript ()
    ]
    [ (bobSmartWallet, usdmValue)
    , (bobSmartWallet, eurmValue)
    ]
@
-}
transferTx
    :: AccountAddress
    -- ^ PLG staking account (from 'plgAccountAddress').
    -> Script ConwayEra
    -- ^ PLB script (payment credential of all smart wallets).
    -> Script ConwayEra
    -- ^ PLG script (withdrawal script for the zero-lovelace invocation).
    -> [TransferInput]
    -- ^ Smart-wallet UTxOs being spent with their registry proofs.
    -> [TxIn]
    -- ^ Registry node reference inputs (supply one per proof).
    -> [TransferLogic]
    -- ^ Transfer-logic scripts for each registered token in the inputs.
    -> [(Addr, MaryValue)]
    -- ^ Outputs: (smart-wallet address, value). Min-UTxO is auto-compensated.
    -> TxBuild q e ()
transferTx
    plgAccount
    plbScript
    plgScript
    inputs
    registryRefs
    transferLogics
    outputs = do
        -- Attach scripts to the witness set.
        attachScript plbScript
        attachScript plgScript
        forM_ transferLogics $ \(TransferLogic _ s _) ->
            attachScript s

        -- Spend each source smart-wallet UTxO through PLB.
        -- PLB validates by checking PLG ran; the PLB redeemer is unit.
        forM_ inputs $ \(TransferInput txIn _) ->
            spendScript txIn ()

        -- Include registry nodes as reference inputs for proof verification.
        forM_ registryRefs reference

        -- Invoke PLG via withdraw-zero with the transfer proofs.
        withdrawScript
            plgAccount
            (Coin 0)
            (TransferAct (map tiProof inputs))

        -- Invoke each registered token's transfer-logic script via withdraw-zero.
        forM_ transferLogics $ \(TransferLogic acct _ rdmr) ->
            withdrawScript acct (Coin 0) rdmr

        -- Emit outputs. 'payTo' uses SendMin: lovelace is raised to min-UTxO.
        forM_ outputs $ \(addr, val) ->
            void $ payTo addr val
