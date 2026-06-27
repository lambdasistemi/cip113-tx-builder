{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.E2E.Deploy (
    CIP113Deployment (..),
    deployCIP113,
) where

import Control.Concurrent (threadDelay)
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map

import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams, Script)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash, originalBytes)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue, PolicyID (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Node.Client.E2E.Setup (
    addKeyWitness,
    genesisAddr,
    genesisSignKey,
 )
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (submitTx))
import Cardano.Tx.Build (
    Check (..),
    Convergence (..),
    InterpretIO (..),
    TxBuild,
    attachScript,
    build,
    mint,
    mkPParamsBound,
    payTo',
    spend,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Cardano.CIP113.Scripts (
    Blueprint,
    applyDataArg,
    lookupValidator,
    outputRefData,
    policyIdData,
    scriptCredData,
    scriptHashBytes,
    scriptHashOf,
    toConwayScript,
 )
import Cardano.CIP113.Types (RegistryNode (..), originNode)
import PlutusCore.Data (Data (..))

-- | All the script handles produced by the CIP-113 bootstrap deployment.
data CIP113Deployment = CIP113Deployment
    { dPlbScript :: !(Script ConwayEra)
    , dPlbHash :: !ScriptHash
    , dPlgScript :: !(Script ConwayEra)
    , dPlgHash :: !ScriptHash
    , dRegistryMintScript :: !(Script ConwayEra)
    , dRegistryPolicy :: !PolicyID
    , dRegistryAddr :: !Addr
    , dAlwaysFailScript :: !(Script ConwayEra)
    , dAlwaysFailHash :: !ScriptHash
    , dParamsPolicy :: !PolicyID
    }

{- | Deploy CIP-113 to a running devnet and return all script handles.

Submits two transactions:
  1. Mint the protocol-params NFT (one-shot, keyed to genesis UTxO #0).
  2. Initialise the registry origin node.
-}
deployCIP113 ::
    Blueprint ->
    Provider IO ->
    Submitter IO ->
    PParams ConwayEra ->
    [(TxIn, TxOut ConwayEra)] ->
    IO CIP113Deployment
deployCIP113 bp provider submitter pp genesisUtxos = do
    (seedIn, _) <- case genesisUtxos of
        u : _ -> pure u
        [] -> fail "deployCIP113: no genesis UTxOs"

    let TxIn txId _idx = seedIn
        TxId safeHash = txId
        txHashBytes = originalBytes safeHash

    -- ── Parameter application chain ───────────────────────────────────────

    -- always_fail: nonce = empty bytes
    let afBin = applyDataArg (lookupValidator "always_fail.always_fail.spend" bp) (B mempty)
        afScript = toConwayScript afBin
        afHash = scriptHashOf afBin

    -- protocol_params_mint: (utxo_ref #0, always_fail_hash)
    let ppmBin =
            applyDataArg
                ( applyDataArg
                    (lookupValidator "protocol_params_mint.protocol_params_mint.mint" bp)
                    (outputRefData txHashBytes 0)
                )
                (policyIdData (scriptHashBytes afHash))
        ppmScript = toConwayScript ppmBin
        ppmHash = scriptHashOf ppmBin
        paramsPolicy = PolicyID ppmHash
        paramsAsset = AssetName (SBS.toShort (scriptHashBytes ppmHash))

    -- programmable_logic_global: params_policy = ppmHash
    let plgBin =
            applyDataArg
                (lookupValidator "programmable_logic_global.programmable_logic_global.withdraw" bp)
                (policyIdData (scriptHashBytes ppmHash))
        plgScript = toConwayScript plgBin
        plgHash = scriptHashOf plgBin

    -- programmable_logic_base: stake_cred = PLG script credential
    let plbBin =
            applyDataArg
                (lookupValidator "programmable_logic_base.programmable_logic_base.spend" bp)
                (scriptCredData plgHash)
        plbScript = toConwayScript plbBin
        plbHash = scriptHashOf plbBin

    -- issuance_cbor_hex_mint: (utxo_ref #0, always_fail_hash)
    let ichmBin =
            applyDataArg
                ( applyDataArg
                    (lookupValidator "issuance_cbor_hex_mint.issuance_cbor_hex_mint.mint" bp)
                    (outputRefData txHashBytes 0)
                )
                (policyIdData (scriptHashBytes afHash))
        ichmHash = scriptHashOf ichmBin

    -- registry_mint: (utxo_ref #0, issuance_cbor_hex_cs, PLB script credential)
    let rmBin =
            applyDataArg
                ( applyDataArg
                    ( applyDataArg
                        (lookupValidator "registry_mint.registry_mint.mint" bp)
                        (outputRefData txHashBytes 0)
                    )
                    (policyIdData (scriptHashBytes ichmHash))
                )
                (scriptCredData plbHash)
        rmScript = toConwayScript rmBin
        rmHash = scriptHashOf rmBin
        registryPolicy = PolicyID rmHash

    -- Registry nodes: payment = PLB, no stake
    let registryAddr = Addr Testnet (ScriptHashObj plbHash) StakeRefNull

    -- ── Tx 1: Mint protocol params NFT ───────────────────────────────────

    let paramsMintTx :: TxBuild NoQ NoErr ()
        paramsMintTx = do
            attachScript ppmScript
            _ <- spend seedIn
            _ <- mint paramsPolicy (Map.singleton paramsAsset 1) ()
            _ <- payTo' genesisAddr (inject (Coin 2_000_000) :: MaryValue) ()
            pure ()

    _tx1 <- runTx pp paramsMintTx genesisUtxos provider submitter

    threadDelay 5_000_000

    -- ── Tx 2: Init registry origin node ──────────────────────────────────

    utxos2 <- queryUTxOs provider genesisAddr
    (seed2, _) <- case utxos2 of
        u : _ -> pure u
        [] -> fail "deployCIP113: no UTxOs for registry init"

    let registryInitTx :: TxBuild NoQ NoErr ()
        registryInitTx = do
            attachScript rmScript
            _ <- spend seed2
            -- Origin node NFT: asset name = empty bytes (origin key is empty)
            _ <- mint registryPolicy (Map.singleton (AssetName SBS.empty) 1) ()
            _ <- payTo' registryAddr (inject (Coin 2_000_000) :: MaryValue) originNode
            pure ()

    _tx2 <- runTx pp registryInitTx utxos2 provider submitter

    threadDelay 5_000_000

    pure
        CIP113Deployment
            { dPlbScript = plbScript
            , dPlbHash = plbHash
            , dPlgScript = plgScript
            , dPlgHash = plgHash
            , dRegistryMintScript = rmScript
            , dRegistryPolicy = registryPolicy
            , dRegistryAddr = registryAddr
            , dAlwaysFailScript = afScript
            , dAlwaysFailHash = afHash
            , dParamsPolicy = paramsPolicy
            }

-- ── Internal ──────────────────────────────────────────────────────────────────

data NoQ a
data NoErr deriving (Show)

runTx ::
    PParams ConwayEra ->
    TxBuild NoQ NoErr () ->
    [(TxIn, TxOut ConwayEra)] ->
    Provider IO ->
    Submitter IO ->
    IO ConwayTx
runTx pp txBuild utxos provider submitter = do
    let interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
    tx <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound pp)
                interpret
                eval
                utxos
                utxos
                genesisAddr
                txBuild
    let signed = addKeyWitness genesisSignKey tx
    result <- submitTx submitter signed
    case result of
        Submitted _ -> pure signed
        Rejected reason -> fail $ "runTx: " <> show reason
