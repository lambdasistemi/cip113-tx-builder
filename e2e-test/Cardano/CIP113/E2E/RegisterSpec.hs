{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.E2E.RegisterSpec (spec) where

import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Lens.Micro ((^.))
import Test.Hspec

import Cardano.Ledger.Api.Tx.Out (TxOut, valueTxOutL)
import Cardano.Ledger.BaseTypes (Inject (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Hashes (originalBytes)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue, PolicyID (..))
import Cardano.Ledger.TxIn (TxIn (..))

import Cardano.Node.Client.E2E.Setup (
    addKeyWitness,
    genesisAddr,
    genesisSignKey,
    withDevnet,
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
    mint,
    mkPParamsBound,
    payTo',
    spendScript,
 )

import Cardano.CIP113.E2E.Deploy (CIP113Deployment (..), deployCIP113)
import Cardano.CIP113.Scripts (loadBlueprint, scriptHashBytes)
import Cardano.CIP113.Types (
    CIP113Credential (..),
    RegistrationMode (..),
    RegistryNode (..),
    RegistryRedeemer (..),
    originNode,
    sentinelNext,
 )

spec :: Spec
spec =
    around withEnv $
        describe "CIP-113 registry insertion (E2E)" $
            it "inserts a new policy into the registry" runInsert

data Env = Env
    { envProvider :: !(Provider IO)
    , envSubmitter :: !(Submitter IO)
    , envPParams :: !(PParams ConwayEra)
    , envDeployment :: !CIP113Deployment
    }

withEnv :: (Env -> IO ()) -> IO ()
withEnv action =
    withDevnet $ \lsq ltxs -> do
        let provider = mkN2CProvider lsq
            submitter = mkN2CSubmitter ltxs
        pp <- queryProtocolParams provider
        utxos <- queryUTxOs provider genesisAddr
        bp <- loadBlueprint "e2e-test/fixtures/cip113-blueprint.json"
        deployment <- deployCIP113 bp provider submitter pp utxos
        action
            Env
                { envProvider = provider
                , envSubmitter = submitter
                , envPParams = pp
                , envDeployment = deployment
                }

runInsert :: Env -> IO ()
runInsert Env{..} = do
    let CIP113Deployment{..} = envDeployment

    -- Placeholder 28-byte policy key to register.
    let newPolicyKey = BS8.replicate 28 'p'

    let updatedOrigin =
            originNode
                { rnNext = newPolicyKey
                , rnMintingLogicScript = ScriptCredential (scriptHashBytes dAlwaysFailHash)
                , rnTransferLogicScript = ScriptCredential (scriptHashBytes dAlwaysFailHash)
                , rnThirdPartyTransferLogicScript = ScriptCredential (scriptHashBytes dAlwaysFailHash)
                }
        newNode =
            RegistryNode
                { rnKey = newPolicyKey
                , rnNext = sentinelNext
                , rnMintingLogicScript = ScriptCredential (scriptHashBytes dAlwaysFailHash)
                , rnTransferLogicScript = ScriptCredential (scriptHashBytes dAlwaysFailHash)
                , rnThirdPartyTransferLogicScript = ScriptCredential (scriptHashBytes dAlwaysFailHash)
                , rnGlobalStateCs = mempty
                , rnProtectedPrefixes = []
                }
        insertRdmr =
            RegistryInsert
                { riKey = newPolicyKey
                , riMintingLogicScript = ScriptCredential (scriptHashBytes dAlwaysFailHash)
                , riMode = RegisterOnly
                }

    registryUtxos <- queryUTxOs envProvider dRegistryAddr
    (originIn, originOut) <- case registryUtxos of
        u : _ -> pure u
        [] -> fail "no registry UTxOs — deployCIP113 must have failed"

    let originValue = originOut ^. valueTxOutL

    genesisUtxos <- queryUTxOs envProvider genesisAddr

    let insertTx :: TxBuild NoQ NoErr ()
        insertTx = do
            attachScript dRegistrySpendScript
            attachScript dRegistryMintScript
            _ <- spendScript originIn insertRdmr
            _ <-
                mint
                    dRegistryPolicy
                    (Map.singleton (AssetName (SBS.toShort newPolicyKey)) 1)
                    insertRdmr
            _ <- payTo' dRegistryAddr originValue updatedOrigin
            _ <- payTo' dRegistryAddr (inject (Coin 2_000_000) :: MaryValue) newNode
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
                (genesisUtxos <> registryUtxos)
                genesisUtxos
                genesisAddr
                insertTx
    let signed = addKeyWitness genesisSignKey tx
    result <- submitTx envSubmitter signed
    case result of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "registry insert rejected: " <> show reason

data NoQ a
data NoErr deriving (Show)
