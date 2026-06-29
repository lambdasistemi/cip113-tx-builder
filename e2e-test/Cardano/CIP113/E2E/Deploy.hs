{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.CIP113.E2E.Deploy (
    CIP113Deployment (..),
    deployCIP113,
    issuanceMintPolicyId,
    nftValue,
    withCIP113Devnet,
) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel, poll)
import Control.Exception (finally)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Lens.Micro ((^.))

import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..), StrictMaybe (SJust), txIxToInt)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.TxCert (ConwayDelegCert (..), ConwayTxCert (..))
import Cardano.Ledger.Core (PParams, Script, ppKeyDepositL)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash, originalBytes)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

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
import Cardano.CIP113.Types (CIP113Credential (..), IssuanceCborHex (..), RegistryRedeemer (..), originNode)
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))

withCIP113Devnet :: (LSQChannel -> LTxSChannel -> IO a) -> IO a
withCIP113Devnet action =
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
        action lsqCh ltxsCh `finally` cancel nodeThread

-- | All the script handles produced by the CIP-113 bootstrap deployment.
data CIP113Deployment = CIP113Deployment
    { dPlbScript :: !(Script ConwayEra)
    , dPlbHash :: !ScriptHash
    , dPlgScript :: !(Script ConwayEra)
    , dPlgHash :: !ScriptHash
    , dRegistrySpendScript :: !(Script ConwayEra)
    , dRegistryMintScript :: !(Script ConwayEra)
    , dRegistryPolicy :: !PolicyID
    , dRegistryAddr :: !Addr
    , dAlwaysFailScript :: !(Script ConwayEra)
    , dAlwaysFailHash :: !ScriptHash
    , dAlwaysFailAddr :: !Addr
    , dParamsPolicy :: !PolicyID
    , dIssuanceCborScript :: !(Script ConwayEra)
    , dIssuanceCborPolicy :: !PolicyID
    , dIssuancePolicy :: !PolicyID
    , dIssuanceMintScript :: !(Script ConwayEra)
    , dThirdPartyScript :: !(Script ConwayEra)
    , dThirdPartyHash :: !ScriptHash
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

    let TxIn paramsTxId paramsIdx = paramsSeedIn
        TxId paramsSafeHash = paramsTxId
        paramsTxHashBytes = originalBytes paramsSafeHash
        TxIn registryTxId registryIdx = registrySeedIn
        TxId registrySafeHash = registryTxId
        registryTxHashBytes = originalBytes registrySafeHash
        TxIn issuanceTxId issuanceIdx = issuanceSeedIn
        TxId issuanceSafeHash = issuanceTxId
        issuanceTxHashBytes = originalBytes issuanceSafeHash

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
                    (outputRefData paramsTxHashBytes (txIxToInt paramsIdx))
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

    -- unfracking: params_policy = ppmHash
    let unfrackingBin =
            applyDataArg
                (lookupValidator "unfracking.unfracking.withdraw" bp)
                (policyIdData (scriptHashBytes ppmHash))
        unfrackingHash = scriptHashOf unfrackingBin

    -- issuance_cbor_hex_mint: (utxo_ref #0, always_fail_hash)
    let ichmBin =
            applyDataArg
                ( applyDataArg
                    (lookupValidator "issuance_cbor_hex_mint.issuance_cbor_hex_mint.mint" bp)
                    (outputRefData issuanceTxHashBytes (txIxToInt issuanceIdx))
                )
                (policyIdData (scriptHashBytes afHash))
        ichmScript = toConwayScript ichmBin
        ichmHash = scriptHashOf ichmBin
        issuanceCborPolicy = PolicyID ichmHash

    -- registry_spend: (protocol_params_cs = ppmHash)
    let rsBin =
            applyDataArg
                (lookupValidator "registry_spend.registry_spend.spend" bp)
                (policyIdData (scriptHashBytes ppmHash))
        rsScript = toConwayScript rsBin
        rsHash = scriptHashOf rsBin

    -- registry_mint: (registry seed, issuance_cbor_hex_cs, registry_spend credential)
    let rmBin =
            applyDataArg
                ( applyDataArg
                    ( applyDataArg
                        (lookupValidator "registry_mint.registry_mint.mint" bp)
                        (outputRefData registryTxHashBytes (txIxToInt registryIdx))
                    )
                    (policyIdData (scriptHashBytes ichmHash))
                )
                (scriptCredData rsHash)
        rmScript = toConwayScript rmBin
        rmHash = scriptHashOf rmBin
        registryPolicy = PolicyID rmHash

    -- issuance_mint: concrete e2e policy using PLG as the substandard
    -- minting credential.
    let issuanceMintBin =
            issuanceMintScriptBytes
                bp
                plbHash
                registryPolicy
                (ScriptCredential (scriptHashBytes plgHash))
                plgHash
        issuanceMintScript = toConwayScript issuanceMintBin
        issuancePolicy = PolicyID (scriptHashOf issuanceMintBin)
        issuanceMintAltBin =
            issuanceMintScriptBytes
                bp
                plbHash
                registryPolicy
                (ScriptCredential (BS.replicate 28 0))
                plgHash
        (issuancePrefix, issuancePostfix) =
            splitVaryingScript issuanceMintBin issuanceMintAltBin
        thirdPartyBin =
            applyDataArg
                (lookupValidator "programmable_logic_global.programmable_logic_global.publish" bp)
                (policyIdData (scriptHashBytes ppmHash))
        thirdPartyScript = toConwayScript thirdPartyBin
        thirdPartyHash = scriptHashOf thirdPartyBin

    -- Registry nodes sit at the registry_spend address (no stake)
    let registryAddr = Addr Testnet (ScriptHashObj rsHash) StakeRefNull
        alwaysFailAddr = Addr Testnet (ScriptHashObj afHash) StakeRefNull
        paramsDatum =
            RawData $
                Constr
                    0
                    [ policyIdData (scriptHashBytes rmHash)
                    , scriptCredData plbHash
                    , scriptCredData unfrackingHash
                    ]
        paramsAsset = AssetName (SBS.toShort "ProtocolParams")
        paramsValue = nftValue paramsPolicy paramsAsset 2_000_000
        issuanceCborAsset = AssetName (SBS.toShort "IssuanceCborHex")
        issuanceCborValue = nftValue issuanceCborPolicy issuanceCborAsset 2_000_000
        issuanceCborDatum = IssuanceCborHex issuancePrefix issuancePostfix

    -- ── Tx 1: Mint protocol params NFT ───────────────────────────────────

    let paramsMintTx :: TxBuild NoQ NoErr ()
        paramsMintTx = do
            attachScript ppmScript
            collateral (fst collateralUtxo)
            _ <- spend paramsSeedIn
            _ <- mint paramsPolicy (Map.singleton paramsAsset 1) ()
            _ <- payTo' alwaysFailAddr paramsValue paramsDatum
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
            attachScript ichmScript
            collateral (fst collateralUtxo)
            _ <- spend issuanceSeedIn
            _ <- mint issuanceCborPolicy (Map.singleton issuanceCborAsset 1) ()
            _ <- payTo' alwaysFailAddr issuanceCborValue issuanceCborDatum
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
            attachScript rmScript
            collateral (fst collateralUtxo)
            _ <- spend registrySeedIn
            -- Origin node NFT: asset name = empty bytes (origin key is empty)
            _ <- mint registryPolicy (Map.singleton (AssetName SBS.empty) 1) RegistryInit
            _ <-
                payTo'
                    registryAddr
                    (nftValue registryPolicy (AssetName SBS.empty) 2_000_000)
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
            attachScript plgScript
            collateral (fst collateralUtxo)
            _ <-
                certify
                    ( ConwayTxCertDeleg $
                        ConwayRegCert
                            (ScriptHashObj plgHash)
                            (SJust (pp ^. ppKeyDepositL))
                    )
                    (ScriptCert (RawData (List [])))
            pure ()

    _tx4 <- runTx pp plgAccountRegTx plgRegUtxos [collateralUtxo] provider submitter

    threadDelay 5_000_000

    pure
        CIP113Deployment
            { dPlbScript = plbScript
            , dPlbHash = plbHash
            , dPlgScript = plgScript
            , dPlgHash = plgHash
            , dRegistrySpendScript = rsScript
            , dRegistryMintScript = rmScript
            , dRegistryPolicy = registryPolicy
            , dRegistryAddr = registryAddr
            , dAlwaysFailScript = afScript
            , dAlwaysFailHash = afHash
            , dAlwaysFailAddr = alwaysFailAddr
            , dParamsPolicy = paramsPolicy
            , dIssuanceCborScript = ichmScript
            , dIssuanceCborPolicy = issuanceCborPolicy
            , dIssuancePolicy = issuancePolicy
            , dIssuanceMintScript = issuanceMintScript
            , dThirdPartyScript = thirdPartyScript
            , dThirdPartyHash = thirdPartyHash
            }

-- ── Internal ──────────────────────────────────────────────────────────────────

issuanceMintPolicyId ::
    Blueprint ->
    ScriptHash ->
    PolicyID ->
    CIP113Credential ->
    ScriptHash ->
    PolicyID
issuanceMintPolicyId bp plbHash registryPolicy mintingCred plgHash =
    PolicyID $
        scriptHashOf $
            issuanceMintScriptBytes bp plbHash registryPolicy mintingCred plgHash

issuanceMintScriptBytes ::
    Blueprint ->
    ScriptHash ->
    PolicyID ->
    CIP113Credential ->
    ScriptHash ->
    SBS.ShortByteString
issuanceMintScriptBytes bp plbHash (PolicyID registryPolicy) mintingCred plgHash =
    applyDataArg
        ( applyDataArg
            ( applyDataArg
                ( applyDataArg
                    (lookupValidator "issuance_mint.issuance_mint.mint" bp)
                    (scriptCredData plbHash)
                )
                (policyIdData (scriptHashBytes registryPolicy))
            )
            (credentialData mintingCred)
        )
        (scriptCredData plgHash)

credentialData :: CIP113Credential -> Data
credentialData (VKeyCredential h) = Constr 0 [B h]
credentialData (ScriptCredential h) = Constr 1 [B h]

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

splitVaryingScript :: SBS.ShortByteString -> SBS.ShortByteString -> (ByteString, ByteString)
splitVaryingScript targetScript alternateScript =
    let target = SBS.fromShort targetScript
        alternate = SBS.fromShort alternateScript
        prefixLen = commonPrefixLength target alternate
        targetTail = BS.drop prefixLen target
        alternateTail = BS.drop prefixLen alternate
        suffixLen = commonPrefixLength (BS.reverse targetTail) (BS.reverse alternateTail)
        variableLen = BS.length targetTail - suffixLen
     in if variableLen /= 28
            then error "splitVaryingScript: expected one 28-byte varying script parameter"
            else
                ( BS.take prefixLen target
                , BS.drop (BS.length target - suffixLen) target
                )

commonPrefixLength :: ByteString -> ByteString -> Int
commonPrefixLength a b =
    length (takeWhile (uncurry (==)) (BS.zip a b))

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
