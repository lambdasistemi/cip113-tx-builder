{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.E2E.ThirdPartySpec (spec) where

import Control.Concurrent (threadDelay)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Lens.Micro ((%~), (&), (^.))
import Test.Hspec

import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx.Body (reqSignerHashesTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, valueTxOutL)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams, Script, bodyTxL)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Crypto (StandardCrypto)
import Cardano.Ledger.Hashes (ScriptHash, originalBytes)
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (..))
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
import Cardano.Tx.Ledger (ConwayTx)

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

import Cardano.CIP113.Address (plgAccountAddress, smartWalletAddr)
import Cardano.CIP113.E2E.Deploy (CIP113Deployment (..), deployCIP113)
import Cardano.CIP113.Scripts (loadBlueprint, scriptHashBytes)
import Cardano.CIP113.ThirdParty (SubstandardLogic (..), ThirdPartyInput (..), thirdPartyTx)
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
        describe "CIP-113 freeze/seize (E2E)" $ do
            it "freeze: moves smart-wallet UTxO to lockup address" runFreeze
            it "seize: moves smart-wallet UTxO to new owner address" runSeize

data Env = Env
    { envProvider :: !(Provider IO)
    , envSubmitter :: !(Submitter IO)
    , envPParams :: !(PParams ConwayEra)
    , envDeployment :: !CIP113Deployment
    , envGenesisKeyHashBytes :: !BS.ByteString
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
        let gKeyHashBytes = case genesisAddr of
                Addr _ (KeyHashObj (KeyHash h)) _ -> originalBytes h
                _ -> error "genesisAddr is not a KeyHashObj address"
        action
            Env
                { envProvider = provider
                , envSubmitter = submitter
                , envPParams = pp
                , envDeployment = deployment
                , envGenesisKeyHashBytes = gKeyHashBytes
                }

data NoQ a
data NoErr deriving (Show)

-- | 28-byte test policy key — sorts after origin (empty) and before sentinelNext.
testPolicyKey :: BS.ByteString
testPolicyKey = BS.replicate 28 0x01

-- ── Common setup: register test policy and fund smart wallet ──────────────────

data Setup = Setup
    { sRegistryNodeIn :: !TxIn
    , sSmartWalletIn :: !TxIn
    , sSmartWalletValue :: !MaryValue
    , sSmartWalletAddr :: !Addr
    }

runSetup :: Env -> IO Setup
runSetup Env{..} = do
    let CIP113Deployment{..} = envDeployment
        thirdPartyCred = VKeyCredential envGenesisKeyHashBytes
        mintingCred = ScriptCredential (scriptHashBytes dAlwaysFailHash)

    let updatedOrigin =
            originNode
                { rnNext = testPolicyKey
                , rnMintingLogicScript = mintingCred
                , rnTransferLogicScript = mintingCred
                , rnThirdPartyTransferLogicScript = thirdPartyCred
                }
        newNode =
            RegistryNode
                { rnKey = testPolicyKey
                , rnNext = sentinelNext
                , rnMintingLogicScript = mintingCred
                , rnTransferLogicScript = mintingCred
                , rnThirdPartyTransferLogicScript = thirdPartyCred
                , rnGlobalStateCs = mempty
                , rnProtectedPrefixes = []
                }
        insertRdmr =
            RegistryInsert
                { riKey = testPolicyKey
                , riMintingLogicScript = mintingCred
                , riMode = RegisterOnly
                }

    registryUtxos <- queryUTxOs envProvider dRegistryAddr
    (originIn, originOut) <- case registryUtxos of
        u : _ -> pure u
        [] -> fail "no registry UTxOs"

    let originValue = originOut ^. valueTxOutL

    genesisUtxos1 <- queryUTxOs envProvider genesisAddr

    let interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx envProvider tx

    -- Tx 1: register test policy
    let insertTx :: TxBuild NoQ NoErr ()
        insertTx = do
            attachScript dRegistrySpendScript
            attachScript dRegistryMintScript
            _ <- spendScript originIn insertRdmr
            _ <-
                mint
                    dRegistryPolicy
                    (Map.singleton (AssetName (SBS.toShort testPolicyKey)) 1)
                    insertRdmr
            _ <- payTo' dRegistryAddr originValue updatedOrigin
            _ <- payTo' dRegistryAddr (inject (Coin 2_000_000) :: MaryValue) newNode
            pure ()

    txInsert <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                (genesisUtxos1 <> registryUtxos)
                genesisUtxos1
                genesisAddr
                insertTx
    let signedInsert = addKeyWitness genesisSignKey txInsert
    rInsert <- submitTx envSubmitter signedInsert
    case rInsert of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "registry insert rejected: " <> show reason

    threadDelay 5_000_000

    -- Tx 2: fund a smart wallet (payment = PLB, staking = genesis payment key)
    let smartWallet =
            case genesisAddr of
                Addr _ (KeyHashObj (KeyHash h)) _ ->
                    smartWalletAddr
                        Testnet
                        dPlbHash
                        (KeyHashObj (KeyHash h :: KeyHash 'Staking StandardCrypto))
                _ -> error "genesisAddr is not a key hash address"
        fundValue = inject (Coin 5_000_000) :: MaryValue

    genesisUtxos2 <- queryUTxOs envProvider genesisAddr

    let fundTx :: TxBuild NoQ NoErr ()
        fundTx = do
            _ <- payTo' smartWallet fundValue ()
            pure ()

    txFund <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                genesisUtxos2
                genesisUtxos2
                genesisAddr
                fundTx
    let signedFund = addKeyWitness genesisSignKey txFund
    rFund <- submitTx envSubmitter signedFund
    case rFund of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "fund smart wallet rejected: " <> show reason

    threadDelay 5_000_000

    -- Query resulting UTxOs
    smartWalletUtxos <- queryUTxOs envProvider smartWallet
    (swIn, swOut) <- case smartWalletUtxos of
        u : _ -> pure u
        [] -> fail "no smart wallet UTxOs after funding"

    -- Pick any registry node; both nodes carry the same thirdPartyCred
    registryUtxos2 <- queryUTxOs envProvider dRegistryAddr
    (regIn, _) <- case registryUtxos2 of
        u : _ -> pure u
        [] -> fail "no registry UTxOs after insert"

    pure
        Setup
            { sRegistryNodeIn = regIn
            , sSmartWalletIn = swIn
            , sSmartWalletValue = swOut ^. valueTxOutL
            , sSmartWalletAddr = smartWallet
            }

-- ── Inject the genesis key hash into the tx required-signers set ──────────────
--
-- PLG ThirdPartyAct with VKeyCredential checks txInfoSignatories (Plutus V3),
-- which maps to reqSignerHashes in the Conway tx body.
addGenesisRequiredSigner :: ConwayTx -> ConwayTx
addGenesisRequiredSigner tx =
    tx & bodyTxL . reqSignerHashesTxBodyL %~ Set.insert witnessKH
  where
    witnessKH :: KeyHash 'Witness StandardCrypto
    witnessKH = case genesisAddr of
        Addr _ (KeyHashObj (KeyHash h)) _ -> KeyHash h
        _ -> error "genesisAddr is not a key hash address"

-- ── Freeze ─────────────────────────────────────────────────────────────────────

runFreeze :: Env -> IO ()
runFreeze env@Env{..} = do
    let CIP113Deployment{..} = envDeployment
    Setup{..} <- runSetup env

    let plgAccount = plgAccountAddress Testnet dPlgHash
        lockupAddr = genesisAddr

    genesisUtxos <- queryUTxOs envProvider genesisAddr
    swUtxos <- queryUTxOs envProvider sSmartWalletAddr
    regUtxos <- queryUTxOs envProvider dRegistryAddr

    let interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx envProvider tx

    let freezeTx :: TxBuild NoQ NoErr ()
        freezeTx =
            thirdPartyTx
                plgAccount
                dPlbScript
                dPlgScript
                [ ThirdPartyInput
                    { tpTxIn = sSmartWalletIn
                    , tpRegistryNodeIdx = 0
                    , tpOutputsStartIdx = 0
                    }
                ]
                [sRegistryNodeIn]
                []
                [(lockupAddr, sSmartWalletValue)]

    tx <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                (genesisUtxos <> swUtxos <> regUtxos)
                genesisUtxos
                genesisAddr
                freezeTx

    let signed = addKeyWitness genesisSignKey (addGenesisRequiredSigner tx)
    result <- submitTx envSubmitter signed
    case result of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "freeze tx rejected: " <> show reason

-- ── Seize ──────────────────────────────────────────────────────────────────────

runSeize :: Env -> IO ()
runSeize env@Env{..} = do
    let CIP113Deployment{..} = envDeployment
    Setup{..} <- runSetup env

    let plgAccount = plgAccountAddress Testnet dPlgHash
        newOwnerAddr = genesisAddr

    genesisUtxos <- queryUTxOs envProvider genesisAddr
    swUtxos <- queryUTxOs envProvider sSmartWalletAddr
    regUtxos <- queryUTxOs envProvider dRegistryAddr

    let interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx envProvider tx

    let seizeTx :: TxBuild NoQ NoErr ()
        seizeTx =
            thirdPartyTx
                plgAccount
                dPlbScript
                dPlgScript
                [ ThirdPartyInput
                    { tpTxIn = sSmartWalletIn
                    , tpRegistryNodeIdx = 0
                    , tpOutputsStartIdx = 0
                    }
                ]
                [sRegistryNodeIn]
                []
                [(newOwnerAddr, sSmartWalletValue)]

    tx <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                (genesisUtxos <> swUtxos <> regUtxos)
                genesisUtxos
                genesisAddr
                seizeTx

    let signed = addKeyWitness genesisSignKey (addGenesisRequiredSigner tx)
    result <- submitTx envSubmitter signed
    case result of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "seize tx rejected: " <> show reason
