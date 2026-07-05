{-# LANGUAGE OverloadedStrings #-}

module Cardano.CIP113.Deployment (
    CIP113Deployment (..),
    computeDeployment,
    issuanceMintPolicyId,
) where

import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.BaseTypes (Network (..), txIxToInt)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash, originalBytes)
import Cardano.Ledger.Mary.Value (PolicyID (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import PlutusCore.Data (Data (..))

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
import Cardano.CIP113.Types (CIP113Credential (..))

-- | All the script handles produced by the CIP-113 bootstrap deployment.
data CIP113Deployment = CIP113Deployment
    { dPlbScript :: !(Script ConwayEra)
    , dPlbHash :: !ScriptHash
    , dPlgScript :: !(Script ConwayEra)
    , dPlgHash :: !ScriptHash
    , dRegistrySpendScript :: !(Script ConwayEra)
    , dRegistrySpendHash :: !ScriptHash
    , dRegistryMintScript :: !(Script ConwayEra)
    , dRegistryPolicy :: !PolicyID
    , dRegistryAddr :: !Addr
    , dAlwaysFailScript :: !(Script ConwayEra)
    , dAlwaysFailHash :: !ScriptHash
    , dAlwaysFailAddr :: !Addr
    , dParamsScript :: !(Script ConwayEra)
    , dParamsPolicy :: !PolicyID
    , dUnfrackingHash :: !ScriptHash
    , dIssuanceCborScript :: !(Script ConwayEra)
    , dIssuanceCborPolicy :: !PolicyID
    , dIssuanceCborPrefix :: !ByteString
    , dIssuanceCborPostfix :: !ByteString
    , dIssuancePolicy :: !PolicyID
    , dIssuanceMintScript :: !(Script ConwayEra)
    , dThirdPartyScript :: !(Script ConwayEra)
    , dThirdPartyHash :: !ScriptHash
    }

computeDeployment :: Blueprint -> (TxIn, TxIn, TxIn) -> CIP113Deployment
computeDeployment bp (paramsSeedIn, registrySeedIn, issuanceSeedIn) =
    let TxIn paramsTxId paramsIdx = paramsSeedIn
        TxId paramsSafeHash = paramsTxId
        paramsTxHashBytes = originalBytes paramsSafeHash
        TxIn registryTxId registryIdx = registrySeedIn
        TxId registrySafeHash = registryTxId
        registryTxHashBytes = originalBytes registrySafeHash
        TxIn issuanceTxId issuanceIdx = issuanceSeedIn
        TxId issuanceSafeHash = issuanceTxId
        issuanceTxHashBytes = originalBytes issuanceSafeHash

        afBin = applyDataArg (lookupValidator "always_fail.always_fail.spend" bp) (B mempty)
        afScript = toConwayScript afBin
        afHash = scriptHashOf afBin

        ppmBin =
            applyDataArg
                ( applyDataArg
                    (lookupValidator "protocol_params_mint.protocol_params_mint.mint" bp)
                    (outputRefData paramsTxHashBytes (txIxToInt paramsIdx))
                )
                (policyIdData (scriptHashBytes afHash))
        ppmHash = scriptHashOf ppmBin
        ppmScript = toConwayScript ppmBin
        paramsPolicy = PolicyID ppmHash

        plgBin =
            applyDataArg
                (lookupValidator "programmable_logic_global.programmable_logic_global.withdraw" bp)
                (policyIdData (scriptHashBytes ppmHash))
        plgScript = toConwayScript plgBin
        plgHash = scriptHashOf plgBin

        plbBin =
            applyDataArg
                (lookupValidator "programmable_logic_base.programmable_logic_base.spend" bp)
                (scriptCredData plgHash)
        plbScript = toConwayScript plbBin
        plbHash = scriptHashOf plbBin

        unfrackingBin =
            applyDataArg
                (lookupValidator "unfracking.unfracking.withdraw" bp)
                (policyIdData (scriptHashBytes ppmHash))
        unfrackingHash = scriptHashOf unfrackingBin

        ichmBin =
            applyDataArg
                ( applyDataArg
                    (lookupValidator "issuance_cbor_hex_mint.issuance_cbor_hex_mint.mint" bp)
                    (outputRefData issuanceTxHashBytes (txIxToInt issuanceIdx))
                )
                (policyIdData (scriptHashBytes afHash))
        ichmScript = toConwayScript ichmBin
        ichmHash = scriptHashOf ichmBin
        issuanceCborPolicy = PolicyID ichmHash

        rsBin =
            applyDataArg
                (lookupValidator "registry_spend.registry_spend.spend" bp)
                (policyIdData (scriptHashBytes ppmHash))
        rsScript = toConwayScript rsBin
        rsHash = scriptHashOf rsBin

        rmBin =
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

        issuanceMintBin =
            issuanceMintScriptBytes
                bp
                plbHash
                registryPolicy
                (ScriptCredential (scriptHashBytes plgHash))
                plgHash
        issuanceMintScript = toConwayScript issuanceMintBin
        issuancePolicy = PolicyID (scriptHashOf issuanceMintBin)
        (issuanceCborPrefix, issuanceCborPostfix) =
            issuanceCborScriptParts bp plbHash registryPolicy plgHash

        thirdPartyBin =
            applyDataArg
                (lookupValidator "programmable_logic_global.programmable_logic_global.publish" bp)
                (policyIdData (scriptHashBytes ppmHash))
        thirdPartyScript = toConwayScript thirdPartyBin
        thirdPartyHash = scriptHashOf thirdPartyBin

        registryAddr = Addr Testnet (ScriptHashObj rsHash) StakeRefNull
        alwaysFailAddr = Addr Testnet (ScriptHashObj afHash) StakeRefNull
     in CIP113Deployment
            { dPlbScript = plbScript
            , dPlbHash = plbHash
            , dPlgScript = plgScript
            , dPlgHash = plgHash
            , dRegistrySpendScript = rsScript
            , dRegistrySpendHash = rsHash
            , dRegistryMintScript = rmScript
            , dRegistryPolicy = registryPolicy
            , dRegistryAddr = registryAddr
            , dAlwaysFailScript = afScript
            , dAlwaysFailHash = afHash
            , dAlwaysFailAddr = alwaysFailAddr
            , dParamsScript = ppmScript
            , dParamsPolicy = paramsPolicy
            , dUnfrackingHash = unfrackingHash
            , dIssuanceCborScript = ichmScript
            , dIssuanceCborPolicy = issuanceCborPolicy
            , dIssuanceCborPrefix = issuanceCborPrefix
            , dIssuanceCborPostfix = issuanceCborPostfix
            , dIssuancePolicy = issuancePolicy
            , dIssuanceMintScript = issuanceMintScript
            , dThirdPartyScript = thirdPartyScript
            , dThirdPartyHash = thirdPartyHash
            }

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

issuanceCborScriptParts :: Blueprint -> ScriptHash -> PolicyID -> ScriptHash -> (ByteString, ByteString)
issuanceCborScriptParts bp plbHash registryPolicy plgHash =
    let issuanceMintBin =
            issuanceMintScriptBytes
                bp
                plbHash
                registryPolicy
                (ScriptCredential (scriptHashBytes plgHash))
                plgHash
        issuanceMintAltBin =
            issuanceMintScriptBytes
                bp
                plbHash
                registryPolicy
                (ScriptCredential (BS.replicate 28 0))
                plgHash
     in splitVaryingScript issuanceMintBin issuanceMintAltBin

credentialData :: CIP113Credential -> Data
credentialData (VKeyCredential h) = Constr 0 [B h]
credentialData (ScriptCredential h) = Constr 1 [B h]

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
