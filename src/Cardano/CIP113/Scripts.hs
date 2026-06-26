{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.CIP113.Scripts
    ( -- * Blueprint
      Blueprint
    , loadBlueprint
    , lookupValidator

      -- * Parameter application
    , applyDataArg
    , toConwayScript
    , scriptHashOf

      -- * Data encodings for CIP-113 parameters
    , outputRefData
    , policyIdData
    , scriptCredData
    , vkeyCredData
    ) where

import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)

import Data.Aeson (FromJSON (..), Value, (.:))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (Parser, withObject)
import Data.ByteString.Base16 qualified as Base16

import Cardano.Ledger.Alonzo.Scripts (fromPlutusScript, mkPlutusScript)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script, hashScript)
import Cardano.Ledger.Hashes (ScriptHash (..), originalBytes)
import Cardano.Ledger.Plutus.Language (Language (PlutusV3), Plutus (..), PlutusBinary (..))

import Codec.Extras.SerialiseViaFlat (SerialiseViaFlat (..))
import Codec.Serialise (deserialise, serialise)
import Control.Monad.Except (runExcept)
import PlutusCore (DefaultFun, DefaultUni (..), Some (..), ValueOf (..))
import PlutusCore.Data (Data (..))
import UntypedPlutusCore (Program (..), UnrestrictedProgram (..), applyProgram, unUnrestrictedProgram)
import UntypedPlutusCore.Core.Type (Term (Constant))
import UntypedPlutusCore.DeBruijn (DeBruijn)

newtype Blueprint = Blueprint {bpValidators :: Map Text SBS.ShortByteString}

instance FromJSON Blueprint where
    parseJSON = withObject "Blueprint" $ \o -> do
        vs <- o .: "validators"
        pairs <- traverse parsePair vs
        pure $ Blueprint (Map.fromList pairs)
      where
        parsePair :: Value -> Parser (Text, SBS.ShortByteString)
        parsePair = withObject "Validator" $ \v -> do
            title <- v .: "title"
            hexCode <- v .: "compiledCode"
            case Base16.decode (encodeUtf8 hexCode) of
                Left err -> fail $ "hex decode: " <> err
                Right bs -> pure (title, SBS.toShort bs)

loadBlueprint :: FilePath -> IO Blueprint
loadBlueprint path = do
    bs <- BSL.readFile path
    case Aeson.eitherDecode bs of
        Left err -> fail $ "loadBlueprint " <> path <> ": " <> err
        Right bp -> pure bp

lookupValidator :: Text -> Blueprint -> SBS.ShortByteString
lookupValidator title bp =
    case Map.lookup title (bpValidators bp) of
        Just sbs -> sbs
        Nothing -> error $ "lookupValidator: " <> show title <> " not in blueprint"

-- | Apply one Plutus Data argument to a serialised script.
applyDataArg :: SBS.ShortByteString -> Data -> SBS.ShortByteString
applyDataArg sbs d =
    let prog = deser sbs
        Program ann ver _ = prog
        argTerm = Constant () (Some (ValueOf DefaultUniData d))
        argProg = Program ann ver argTerm
        applied = either (error . show) id $ runExcept $ applyProgram prog argProg
    in ser applied

-- | Wrap a serialised Plutus V3 binary as a 'Script' 'ConwayEra'.
toConwayScript :: SBS.ShortByteString -> Script ConwayEra
toConwayScript sbs =
    maybe (error "toConwayScript: invalid Plutus V3 binary") fromPlutusScript $
        mkPlutusScript (Plutus @PlutusV3 (PlutusBinary sbs))

scriptHashOf :: SBS.ShortByteString -> ScriptHash
scriptHashOf = hashScript . toConwayScript

-- | Encode a UTxO reference as Plutus Data.
-- Aiken OutputReference = Constr 0 [Constr 0 [B txHash], I outputIndex]
outputRefData :: ByteString -> Int -> Data
outputRefData txHash idx =
    Constr 0 [Constr 0 [B txHash], I (fromIntegral idx)]

-- | Encode a 28-byte policy/script hash as a bare bytes Plutus Data.
policyIdData :: ByteString -> Data
policyIdData = B

-- | Encode a script hash as a script credential: Constr 1 [B hash].
scriptCredData :: ScriptHash -> Data
scriptCredData (ScriptHash h) = Constr 1 [B (originalBytes h)]

-- | Encode raw bytes as a vkey credential: Constr 0 [B hash].
vkeyCredData :: ByteString -> Data
vkeyCredData h = Constr 0 [B h]

-- ── Internal ──────────────────────────────────────────────────────────────────

type UPLC a = Program DeBruijn DefaultUni DefaultFun a

deser :: SBS.ShortByteString -> UPLC ()
deser =
    unUnrestrictedProgram
        . (\(SerialiseViaFlat x) -> x)
        . deserialise
        . BSL.fromStrict
        . SBS.fromShort

ser :: UPLC () -> SBS.ShortByteString
ser =
    SBS.toShort
        . BSL.toStrict
        . serialise
        . SerialiseViaFlat
        . UnrestrictedProgram
