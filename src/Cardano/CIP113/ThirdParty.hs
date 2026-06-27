{-# LANGUAGE ExistentialQuantification #-}

{- |
Module      : Cardano.CIP113.ThirdParty
Description : CIP-113 third-party freeze/seize transaction builder

Builds the 'ThirdPartyAct' flow: authorized third-party administration of
programmable tokens, such as freeze or seize operations.

== Protocol summary

1. Spend each affected smart-wallet UTxO through the PLB script.
2. Include registry node UTxOs as reference inputs.
3. Invoke PLG via zero-lovelace withdrawals ('withdrawScript'), passing
   'ThirdPartyAct' with the registry reference-input index and output start
   index for each affected wallet.
4. Invoke each substandard third-party logic script via withdraw-zero.
5. Send outputs to their destination addresses.

== Caller responsibilities

* Supply the registry reference input index for each 'ThirdPartyInput'.
* Supply the first output index governed by each 'ThirdPartyAct'.
* Provide one 'SubstandardLogic' entry for each token type involved.
* Provide collateral and change inputs via the outer 'build' call.
-}
module Cardano.CIP113.ThirdParty (
    ThirdPartyInput (..),
    SubstandardLogic (..),
    thirdPartyTx,
) where

import Control.Monad (forM_, void)

import Cardano.Ledger.Address (AccountAddress, Addr)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script)
import Cardano.Ledger.Mary.Value (MaryValue)
import Cardano.Ledger.TxIn (TxIn)
import PlutusTx.IsData.Class (ToData)

import Cardano.CIP113.Types (PLGRedeemer (..))
import Cardano.Tx.Build (
    TxBuild,
    attachScript,
    payTo,
    reference,
    spendScript,
    withdrawScript,
 )

-- | One affected smart-wallet input for a third-party action.
data ThirdPartyInput = ThirdPartyInput
    { tpTxIn :: !TxIn
    -- ^ UTxO at the smart wallet address.
    , tpRegistryNodeIdx :: !Int
    -- ^ Index of the registry node in this transaction's reference inputs.
    , tpOutputsStartIdx :: !Int
    -- ^ First output index in the body governed by this 'ThirdPartyAct'.
    }

{- | A substandard third-party logic script that must run in the transaction.

Include one 'SubstandardLogic' for each token type involved in the freeze or
seize operation.
-}
data SubstandardLogic
    = forall r.
      (ToData r) =>
    SubstandardLogic
    { slAccount :: !AccountAddress
    -- ^ Staking account for the substandard script.
    , slScript :: !(Script ConwayEra)
    -- ^ The substandard's third-party logic Plutus script.
    , slRedeemer :: r
    -- ^ Redeemer for this invocation (substandard-defined).
    }

{- | Build a CIP-113 third-party freeze/seize transaction.

Returns a 'TxBuild' program that, when passed to 'build', produces a
balanced Conway transaction satisfying the PLG third-party protocol.
-}
thirdPartyTx ::
    -- | PLG staking account.
    AccountAddress ->
    -- | PLB script (payment credential of affected smart wallets).
    Script ConwayEra ->
    -- | PLG script (withdrawal script for the zero-lovelace invocation).
    Script ConwayEra ->
    -- | Smart-wallet UTxOs being affected.
    [ThirdPartyInput] ->
    -- | Registry node reference inputs.
    [TxIn] ->
    -- | Substandard third-party logic scripts for involved token types.
    [SubstandardLogic] ->
    -- | Outputs: destination address and value.
    [(Addr, MaryValue)] ->
    TxBuild q e ()
thirdPartyTx
    plgAccount
    plbScript
    plgScript
    inputs
    registryRefInputs
    substandardLogics
    outputs = do
        attachScript plbScript
        attachScript plgScript
        forM_ substandardLogics $ \(SubstandardLogic _ s _) ->
            attachScript s

        forM_ inputs $ \(ThirdPartyInput txIn _ _) ->
            void $ spendScript txIn ()

        forM_ registryRefInputs reference

        forM_ inputs $ \(ThirdPartyInput _ nodeIdx outIdx) ->
            withdrawScript
                plgAccount
                (Coin 0)
                (ThirdPartyAct nodeIdx outIdx)

        forM_ substandardLogics $ \(SubstandardLogic acct _ rdmr) ->
            withdrawScript acct (Coin 0) rdmr

        forM_ outputs $ \(addr, val) ->
            void $ payTo addr val
