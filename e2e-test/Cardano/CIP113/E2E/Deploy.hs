{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.E2E.Deploy (
    CIP113Deployment (..),
    deployCIP113,
    issuanceMintPolicyId,
    nftValue,
    withCIP113Devnet,
    withCIP113DevnetSocket,
) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel, poll)
import Control.Exception (finally)
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Lens.Micro ((^.))

import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (Inject (..), StrictMaybe (SJust))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.TxCert (ConwayDelegCert (..), ConwayTxCert (..))
import Cardano.Ledger.Core (PParams, ppKeyDepositL)
import Cardano.Ledger.Credential (Credential (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxIn)

import Cardano.Node.Client.E2E.Devnet (withCardanoNode)
import Cardano.Node.Client.E2E.Setup (
    addKeyWitness,
    devnetMagic,
    genesisAddr,
    genesisSignKey,
 )
import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Types (LSQChannel, LTxSChannel)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (submitTx))
import Cardano.Tx.Balance (CollateralUtxos (..))
import Cardano.Tx.Build (
    BuildOptions (..),
    CertWitness (..),
    InterpretIO (..),
    TxBuild,
    attachScript,
    buildWith,
    certify,
    collateral,
    defaultBuildOptions,
    mint,
    mkPParamsBound,
    payTo,
    payTo',
    spend,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Cardano.CIP113.Deployment (
    CIP113Deployment (..),
    computeDeployment,
    issuanceMintPolicyId,
 )
import Cardano.CIP113.Scripts (Blueprint, policyIdData, scriptCredData, scriptHashBytes)
import Cardano.CIP113.Types (IssuanceCborHex (..), RegistryRedeemer (..), originNode)
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))

withCIP113Devnet :: (LSQChannel -> LTxSChannel -> IO a) -> IO a
withCIP113Devnet action =
    withCIP113DevnetSocket $ \_sock lsq ltxs ->
        action lsq ltxs

withCIP113DevnetSocket :: (FilePath -> LSQChannel -> LTxSChannel -> IO a) -> IO a
withCIP113DevnetSocket action =
    withCardanoNode "genesis" $ \sock _startMs -> do
        lsqCh <- newLSQChannel 16
        ltxsCh <- newLTxSChannel 16
        nodeThread <-
            async $
                runNodeClient
                    devnetMagic
                    sock
                    lsqCh
                    ltxsCh
        threadDelay 6_000_000
        status <- poll nodeThread
        case status of
            Just (Left err) ->
                error $
                    "Node connection failed: "
                        <> show err
            Just (Right (Left err)) ->
                error $
                    "Node connection error: "
                        <> show err
            Just (Right (Right ())) ->
                error
                    "Node connection closed \
                    \unexpectedly"
            Nothing -> pure ()
        action sock lsqCh ltxsCh `finally` cancel nodeThread

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
    (initialSeedIn, _) <- case genesisUtxos of
        u : _ -> pure u
        [] -> fail "deployCIP113: no genesis UTxOs"

    let bootstrapTx :: TxBuild NoQ NoErr ()
        bootstrapTx = do
            _ <- spend initialSeedIn
            _ <- payTo genesisAddr (inject (Coin 50_000_000) :: MaryValue)
            _ <- payTo genesisAddr (inject (Coin 50_000_000) :: MaryValue)
            _ <- payTo genesisAddr (inject (Coin 50_000_000) :: MaryValue)
            _ <- payTo genesisAddr (inject (Coin 50_000_000) :: MaryValue)
            pure ()

    _tx0 <- runTx pp bootstrapTx genesisUtxos [] provider submitter

    threadDelay 5_000_000

    bootstrapUtxos <- queryUTxOs provider genesisAddr
    ((paramsSeedIn, _), (registrySeedIn, _), (issuanceSeedIn, _), collateralUtxo) <-
        case bootstrapUtxos of
            a : b : c : d : _ -> pure (a, b, c, d)
            _ -> fail "deployCIP113: bootstrap split did not create enough UTxOs"

    let deployment@CIP113Deployment{..} =
            computeDeployment bp (paramsSeedIn, registrySeedIn, issuanceSeedIn)
        PolicyID registryHash = dRegistryPolicy
        paramsDatum =
            RawData $
                Constr
                    0
                    [ policyIdData (scriptHashBytes registryHash)
                    , scriptCredData dPlbHash
                    , scriptCredData dUnfrackingHash
                    ]
        paramsAsset = AssetName (SBS.toShort "ProtocolParams")
        paramsValue = nftValue dParamsPolicy paramsAsset 2_000_000
        issuanceCborAsset = AssetName (SBS.toShort "IssuanceCborHex")
        issuanceCborValue = nftValue dIssuanceCborPolicy issuanceCborAsset 2_000_000
        issuanceCborDatum = IssuanceCborHex dIssuanceCborPrefix dIssuanceCborPostfix

    -- ── Tx 1: Mint protocol params NFT ───────────────────────────────────

    let paramsMintTx :: TxBuild NoQ NoErr ()
        paramsMintTx = do
            attachScript dParamsScript
            collateral (fst collateralUtxo)
            _ <- spend paramsSeedIn
            _ <- mint dParamsPolicy (Map.singleton paramsAsset 1) ()
            _ <- payTo' dAlwaysFailAddr paramsValue paramsDatum
            pure ()

    _tx1 <-
        runTx
            pp
            paramsMintTx
            [lookupInput paramsSeedIn bootstrapUtxos]
            [collateralUtxo]
            provider
            submitter

    threadDelay 5_000_000

    -- ── Tx 2: Mint issuance-CBOR reference NFT ───────────────────────────

    let issuanceCborTx :: TxBuild NoQ NoErr ()
        issuanceCborTx = do
            attachScript dIssuanceCborScript
            collateral (fst collateralUtxo)
            _ <- spend issuanceSeedIn
            _ <- mint dIssuanceCborPolicy (Map.singleton issuanceCborAsset 1) ()
            _ <- payTo' dAlwaysFailAddr issuanceCborValue issuanceCborDatum
            pure ()

    _tx2 <-
        runTx
            pp
            issuanceCborTx
            [lookupInput issuanceSeedIn bootstrapUtxos]
            [collateralUtxo]
            provider
            submitter

    threadDelay 5_000_000

    -- ── Tx 3: Init registry origin node ──────────────────────────────────

    let registryInitTx :: TxBuild NoQ NoErr ()
        registryInitTx = do
            attachScript dRegistryMintScript
            collateral (fst collateralUtxo)
            _ <- spend registrySeedIn
            -- Origin node NFT: asset name = empty bytes (origin key is empty)
            _ <- mint dRegistryPolicy (Map.singleton (AssetName SBS.empty) 1) RegistryInit
            _ <-
                payTo'
                    dRegistryAddr
                    (nftValue dRegistryPolicy (AssetName SBS.empty) 2_000_000)
                    originNode
            pure ()

    _tx3 <-
        runTx
            pp
            registryInitTx
            [lookupInput registrySeedIn bootstrapUtxos]
            [collateralUtxo]
            provider
            submitter

    threadDelay 5_000_000

    -- ── Tx 4: Register PLG reward account for withdraw-zero ──────────────

    plgRegUtxos <- queryUTxOs provider genesisAddr

    let plgAccountRegTx :: TxBuild NoQ NoErr ()
        plgAccountRegTx = do
            attachScript dPlgScript
            collateral (fst collateralUtxo)
            _ <-
                certify
                    ( ConwayTxCertDeleg $
                        ConwayRegCert
                            (ScriptHashObj dPlgHash)
                            (SJust (pp ^. ppKeyDepositL))
                    )
                    (ScriptCert (RawData (List [])))
            pure ()

    _tx4 <- runTx pp plgAccountRegTx plgRegUtxos [collateralUtxo] provider submitter

    threadDelay 5_000_000

    pure deployment

-- ── Internal ──────────────────────────────────────────────────────────────────

data NoQ a
data NoErr deriving (Show)

newtype RawData = RawData Data

instance ToData RawData where
    toBuiltinData (RawData datum) =
        BuiltinData datum

nftValue :: PolicyID -> AssetName -> Integer -> MaryValue
nftValue policy asset lovelace =
    MaryValue
        (Coin lovelace)
        (MultiAsset (Map.singleton policy (Map.singleton asset 1)))

lookupInput :: TxIn -> [(TxIn, TxOut ConwayEra)] -> (TxIn, TxOut ConwayEra)
lookupInput txIn utxos =
    case filter ((== txIn) . fst) utxos of
        u : _ -> u
        [] -> error "lookupInput: missing UTxO"

runTx ::
    PParams ConwayEra ->
    TxBuild NoQ NoErr () ->
    [(TxIn, TxOut ConwayEra)] ->
    [(TxIn, TxOut ConwayEra)] ->
    Provider IO ->
    Submitter IO ->
    IO ConwayTx
runTx pp txBuild utxos collateralUtxos provider submitter = do
    let interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx provider tx
        options =
            defaultBuildOptions
                { boCollateralUtxos = CollateralUtxos collateralUtxos
                }
    tx <-
        either (fail . show) pure
            =<< buildWith
                options
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
