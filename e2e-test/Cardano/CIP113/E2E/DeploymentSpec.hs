{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.E2E.DeploymentSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.BaseTypes (Network (..), TxIx (..))
import Cardano.Ledger.Core (hashScript)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (PolicyID (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Data.ByteString qualified as BS
import Data.Word (Word16, Word8)
import Test.Hspec

import Cardano.CIP113.Deployment (CIP113Deployment (..), computeDeployment)
import Cardano.CIP113.Scripts (loadBlueprint)

spec :: Spec
spec =
    describe "CIP-113 deployment descriptor" $
        it "computes script hashes, policies, and script addresses purely" $ do
            bp <- loadBlueprint "fixtures/cip113-blueprint.json"
            let CIP113Deployment{..} =
                    computeDeployment
                        bp
                        ( seedTxIn 1 0
                        , seedTxIn 2 1
                        , seedTxIn 3 2
                        )

            hashScript dPlbScript `shouldBe` dPlbHash
            hashScript dPlgScript `shouldBe` dPlgHash
            hashScript dRegistrySpendScript `shouldBe` dRegistrySpendHash
            hashScript dAlwaysFailScript `shouldBe` dAlwaysFailHash
            hashScript dThirdPartyScript `shouldBe` dThirdPartyHash

            dParamsPolicy `shouldBe` PolicyID (hashScript dParamsScript)
            dRegistryPolicy `shouldBe` PolicyID (hashScript dRegistryMintScript)
            dIssuanceCborPolicy `shouldBe` PolicyID (hashScript dIssuanceCborScript)
            dIssuancePolicy `shouldBe` PolicyID (hashScript dIssuanceMintScript)

            dRegistryAddr `shouldBe` Addr Testnet (ScriptHashObj dRegistrySpendHash) StakeRefNull
            dAlwaysFailAddr `shouldBe` Addr Testnet (ScriptHashObj dAlwaysFailHash) StakeRefNull

seedTxIn :: Word8 -> Word16 -> TxIn
seedTxIn byte ix =
    case hashFromBytes (BS.replicate 32 byte) of
        Just txHash ->
            TxIn
                (TxId (unsafeMakeSafeHash txHash))
                (TxIx ix)
        Nothing ->
            error "seedTxIn: expected a 32-byte transaction id hash"
