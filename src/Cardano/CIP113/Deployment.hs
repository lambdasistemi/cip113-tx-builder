{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.CIP113.Deployment (
    CIP113Deployment (..),
    computeDeployment,
    issuanceMintPolicyId,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.Ledger.Address (Addr (..), decodeAddrEither, serialiseAddr)
import Cardano.Ledger.BaseTypes (Network (..), txIxToInt)
import Cardano.Ledger.Binary (Annotator, Decoder, decCBOR, decodeFullAnnotator, serialize')
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script, eraProtVerLow)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..), originalBytes)
import Cardano.Ledger.Mary.Value (PolicyID (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.Aeson.Types (Parser)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
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

instance ToJSON CIP113Deployment where
    toJSON CIP113Deployment{..} =
        object
            [ "plbScript" .= scriptText dPlbScript
            , "plbHash" .= scriptHashText dPlbHash
            , "plgScript" .= scriptText dPlgScript
            , "plgHash" .= scriptHashText dPlgHash
            , "registrySpendScript" .= scriptText dRegistrySpendScript
            , "registrySpendHash" .= scriptHashText dRegistrySpendHash
            , "registryMintScript" .= scriptText dRegistryMintScript
            , "registryPolicy" .= policyText dRegistryPolicy
            , "registryAddr" .= addrText dRegistryAddr
            , "alwaysFailScript" .= scriptText dAlwaysFailScript
            , "alwaysFailHash" .= scriptHashText dAlwaysFailHash
            , "alwaysFailAddr" .= addrText dAlwaysFailAddr
            , "paramsScript" .= scriptText dParamsScript
            , "paramsPolicy" .= policyText dParamsPolicy
            , "unfrackingHash" .= scriptHashText dUnfrackingHash
            , "issuanceCborScript" .= scriptText dIssuanceCborScript
            , "issuanceCborPolicy" .= policyText dIssuanceCborPolicy
            , "issuanceCborPrefix" .= hexText dIssuanceCborPrefix
            , "issuanceCborPostfix" .= hexText dIssuanceCborPostfix
            , "issuancePolicy" .= policyText dIssuancePolicy
            , "issuanceMintScript" .= scriptText dIssuanceMintScript
            , "thirdPartyScript" .= scriptText dThirdPartyScript
            , "thirdPartyHash" .= scriptHashText dThirdPartyHash
            ]

instance FromJSON CIP113Deployment where
    parseJSON = withObject "CIP113Deployment" $ \o -> do
        dPlbScript <- o .: "plbScript" >>= parseScript "plbScript"
        dPlbHash <- o .: "plbHash" >>= parseScriptHash "plbHash"
        dPlgScript <- o .: "plgScript" >>= parseScript "plgScript"
        dPlgHash <- o .: "plgHash" >>= parseScriptHash "plgHash"
        dRegistrySpendScript <- o .: "registrySpendScript" >>= parseScript "registrySpendScript"
        dRegistrySpendHash <- o .: "registrySpendHash" >>= parseScriptHash "registrySpendHash"
        dRegistryMintScript <- o .: "registryMintScript" >>= parseScript "registryMintScript"
        dRegistryPolicy <- o .: "registryPolicy" >>= parsePolicy "registryPolicy"
        dRegistryAddr <- o .: "registryAddr" >>= parseAddr "registryAddr"
        dAlwaysFailScript <- o .: "alwaysFailScript" >>= parseScript "alwaysFailScript"
        dAlwaysFailHash <- o .: "alwaysFailHash" >>= parseScriptHash "alwaysFailHash"
        dAlwaysFailAddr <- o .: "alwaysFailAddr" >>= parseAddr "alwaysFailAddr"
        dParamsScript <- o .: "paramsScript" >>= parseScript "paramsScript"
        dParamsPolicy <- o .: "paramsPolicy" >>= parsePolicy "paramsPolicy"
        dUnfrackingHash <- o .: "unfrackingHash" >>= parseScriptHash "unfrackingHash"
        dIssuanceCborScript <- o .: "issuanceCborScript" >>= parseScript "issuanceCborScript"
        dIssuanceCborPolicy <- o .: "issuanceCborPolicy" >>= parsePolicy "issuanceCborPolicy"
        dIssuanceCborPrefix <- o .: "issuanceCborPrefix" >>= parseHex "issuanceCborPrefix"
        dIssuanceCborPostfix <- o .: "issuanceCborPostfix" >>= parseHex "issuanceCborPostfix"
        dIssuancePolicy <- o .: "issuancePolicy" >>= parsePolicy "issuancePolicy"
        dIssuanceMintScript <- o .: "issuanceMintScript" >>= parseScript "issuanceMintScript"
        dThirdPartyScript <- o .: "thirdPartyScript" >>= parseScript "thirdPartyScript"
        dThirdPartyHash <- o .: "thirdPartyHash" >>= parseScriptHash "thirdPartyHash"
        pure CIP113Deployment{..}

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

scriptText :: Script ConwayEra -> Text
scriptText =
    hexText . serialize' (eraProtVerLow @ConwayEra)

scriptHashText :: ScriptHash -> Text
scriptHashText =
    hexText . scriptHashBytes

policyText :: PolicyID -> Text
policyText (PolicyID policyHash) =
    scriptHashText policyHash

addrText :: Addr -> Text
addrText =
    hexText . serialiseAddr

hexText :: ByteString -> Text
hexText =
    TE.decodeUtf8 . Base16.encode

parseScript :: String -> Text -> Parser (Script ConwayEra)
parseScript label raw = do
    bytes <- parseHex label raw
    case decodeFullAnnotator
        (eraProtVerLow @ConwayEra)
        (Text.pack label)
        (decCBOR :: forall s. Decoder s (Annotator (Script ConwayEra)))
        (BSL.fromStrict bytes) of
        Left err -> fail ("invalid " <> label <> " script CBOR: " <> show err)
        Right script -> pure script

parseScriptHash :: String -> Text -> Parser ScriptHash
parseScriptHash label raw = do
    bytes <- parseHex label raw
    case hashFromBytes bytes of
        Nothing -> fail (label <> " must be a 28-byte script hash")
        Just h -> pure (ScriptHash h)

parsePolicy :: String -> Text -> Parser PolicyID
parsePolicy label raw =
    PolicyID <$> parseScriptHash label raw

parseAddr :: String -> Text -> Parser Addr
parseAddr label raw = do
    bytes <- parseHex label raw
    case decodeAddrEither bytes of
        Left err -> fail ("invalid " <> label <> " serialized address: " <> err)
        Right addr -> pure addr

parseHex :: String -> Text -> Parser ByteString
parseHex label raw =
    case Base16.decode (TE.encodeUtf8 raw) of
        Left err -> fail ("invalid " <> label <> " base16: " <> err)
        Right bytes -> pure bytes
