{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.E2E.RegistryResolverSpec (spec) where

import Control.Concurrent (threadDelay)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import GHC.Stack (HasCallStack)
import Lens.Micro ((^.))
import Test.Hspec

import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Mary.Value (AssetName (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxIn)

import Cardano.Node.Client.E2E.Setup (
    addKeyWitness,
    genesisAddr,
    genesisSignKey,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (submitTx))

import Cardano.Tx.Build (
    InterpretIO (..),
    TxBuild,
    attachScript,
    build,
    collateral,
    mint,
    mkPParamsBound,
    payTo',
    reference,
    spendScript,
    withdrawScript,
 )

import Cardano.CIP113.Address (plgAccountAddress)
import Cardano.CIP113.E2E.Deploy (CIP113Deployment (..), deployCIP113, nftValue, withCIP113Devnet)
import Cardano.CIP113.Registry (
    RegistryNodeUtxo (..),
    ResolvedRegistryNode (..),
    findInsertionPoint,
    findNode,
 )
import Cardano.CIP113.Scripts (loadBlueprint, scriptHashBytes)
import Cardano.CIP113.Types (
    CIP113Credential (..),
    PLGRedeemer (..),
    RegistrationMode (..),
    RegistryNode (..),
    RegistryRedeemer (..),
    originNode,
    sentinelNext,
 )

spec :: Spec
spec =
    around withEnv $
        describe "CIP-113 registry resolver (E2E)" $
            it "resolves registered and absent policies from fresh registry UTxOs" runResolver

data Env = Env
    { envProvider :: !(Provider IO)
    , envSubmitter :: !(Submitter IO)
    , envPParams :: !(PParams ConwayEra)
    , envDeployment :: !CIP113Deployment
    , envMintingCred :: !CIP113Credential
    , envPolicyKey :: !BS.ByteString
    }

withEnv :: (Env -> IO ()) -> IO ()
withEnv action =
    withCIP113Devnet $ \lsq ltxs -> do
        let provider = mkN2CProvider lsq
            submitter = mkN2CSubmitter ltxs
        pp <- queryProtocolParams provider
        utxos <- queryUTxOs provider genesisAddr
        bp <- loadBlueprint "fixtures/cip113-blueprint.json"
        deployment <- deployCIP113 bp provider submitter pp utxos
        let CIP113Deployment{..} = deployment
            mintingCred = ScriptCredential (scriptHashBytes dPlgHash)
            policyKey = case dIssuancePolicy of
                PolicyID h -> scriptHashBytes h
        action
            Env
                { envProvider = provider
                , envSubmitter = submitter
                , envPParams = pp
                , envDeployment = deployment
                , envMintingCred = mintingCred
                , envPolicyKey = policyKey
                }

runResolver :: Env -> IO ()
runResolver env@Env{..} = do
    insertRegistryNode env
    threadDelay 5_000_000

    let CIP113Deployment{..} = envDeployment
    laterPolicyKey <-
        maybe
            (fail "test policy key has no same-length successor")
            pure
            (successorKey envPolicyKey)

    freshRegistryUtxos <- queryUTxOs envProvider dRegistryAddr
    freshRegistryUtxos `shouldSatisfy` ((>= 2) . length)

    lockedUtxos <- queryUTxOs envProvider dAlwaysFailAddr
    lockedUtxos `shouldSatisfy` (not . null)
    let otherRefs = map fst lockedUtxos

    resolved <- findNode envDeployment envProvider otherRefs envPolicyKey
    Just ResolvedRegistryNode{rrnUtxo = resolvedUtxo, ..} <-
        resolved `shouldReturnRight` "registered policy"
    let insertedTxIn = rnuTxIn resolvedUtxo
        insertedNodeVal = rnuNode resolvedUtxo

    insertedNodeVal `shouldBe` insertedNode env
    rnKey insertedNodeVal `shouldBe` envPolicyKey
    rrnReferenceInputIndex
        `shouldBe` case List.elemIndex insertedTxIn (List.sort (insertedTxIn : otherRefs)) of
            Just ix -> ix
            Nothing -> error "resolved node missing from reference inputs"

    predecessor <- findInsertionPoint envDeployment envProvider laterPolicyKey
    fmap rnuTxIn predecessor `shouldBe` Right insertedTxIn

    absent <- findNode envDeployment envProvider otherRefs laterPolicyKey
    absent `shouldBe` Right Nothing

data NoQ a
data NoErr deriving (Show)

insertedNode :: Env -> RegistryNode
insertedNode Env{..} =
    RegistryNode
        { rnKey = envPolicyKey
        , rnNext = sentinelNext
        , rnMintingLogicScript = envMintingCred
        , rnTransferLogicScript = envMintingCred
        , rnThirdPartyTransferLogicScript = envMintingCred
        , rnGlobalStateCs = mempty
        , rnProtectedPrefixes = []
        }

successorKey :: BS.ByteString -> Maybe BS.ByteString
successorKey key =
    BS.pack <$> go (BS.unpack key)
  where
    go [] = Nothing
    go [b]
        | b == 0xff = Nothing
        | otherwise = Just [b + 1]
    go (b : bs) =
        case go bs of
            Just bs' -> Just (b : bs')
            Nothing
                | b == 0xff -> Nothing
                | otherwise -> Just (b + 1 : replicate (length bs) 0)

insertRegistryNode :: Env -> IO ()
insertRegistryNode env@Env{..} = do
    let CIP113Deployment{..} = envDeployment
        updatedOrigin =
            originNode
                { rnNext = envPolicyKey
                }
        insertRdmr =
            RegistryInsert
                { riKey = envPolicyKey
                , riMintingLogicScript = envMintingCred
                , riMode = RegisterOnly
                }

    registryUtxos <- queryUTxOs envProvider dRegistryAddr
    (originIn, originOut) <- case registryUtxos of
        u : _ -> pure u
        [] -> fail "no registry UTxOs"

    let originValue = originOut ^. valueTxOutL

    genesisUtxos <- queryUTxOs envProvider genesisAddr
    lockedUtxos <- queryUTxOs envProvider dAlwaysFailAddr
    collateralIn <- case genesisUtxos of
        (txIn, _) : _ -> pure txIn
        [] -> fail "no genesis UTxOs for collateral"

    let insertTx :: TxBuild NoQ NoErr ()
        insertTx = do
            attachScript dRegistrySpendScript
            attachScript dRegistryMintScript
            attachScript dPlgScript
            collateral collateralIn
            mapM_ (reference . fst) lockedUtxos
            _ <- spendScript originIn insertRdmr
            withdrawScript
                (plgAccountAddress Testnet dPlgHash)
                (Coin 0)
                (TransferAct [])
            _ <-
                mint
                    dRegistryPolicy
                    (Map.singleton (AssetName (SBS.toShort envPolicyKey)) 1)
                    insertRdmr
            _ <- payTo' dRegistryAddr originValue updatedOrigin
            _ <-
                payTo'
                    dRegistryAddr
                    (nftValue dRegistryPolicy (AssetName (SBS.toShort envPolicyKey)) 2_000_000)
                    (insertedNode env)
            pure ()

    let interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx envProvider tx

    tx <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                (largeFeeUtxos genesisUtxos <> registryUtxos)
                lockedUtxos
                genesisAddr
                insertTx
    let signed = addKeyWitness genesisSignKey tx
    result <- submitTx envSubmitter signed
    case result of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "registry insert rejected: " <> show reason

shouldReturnRight :: (HasCallStack, Show e) => Either e a -> String -> IO a
shouldReturnRight result label =
    case result of
        Right value -> pure value
        Left err -> fail (label <> " returned Left: " <> show err)

largeFeeUtxos :: [(TxIn, TxOut ConwayEra)] -> [(TxIn, TxOut ConwayEra)]
largeFeeUtxos utxos =
    case filter ((>= Coin 10_000_000) . (^. coinTxOutL) . snd) utxos of
        [] -> utxos
        large -> large
