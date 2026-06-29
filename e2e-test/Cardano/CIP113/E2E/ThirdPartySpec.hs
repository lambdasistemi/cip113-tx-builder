{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cardano.CIP113.E2E.ThirdPartySpec (spec) where

import Control.Concurrent (threadDelay)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Lens.Micro ((^.))
import Test.Hspec

import Cardano.Ledger.Address (AccountAddress (..), AccountId (..), Addr (..))
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams, ppKeyDepositL)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxIn (..))

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
    CertWitness (..),
    mint,
    mkPParamsBound,
    payTo,
    payTo',
    reference,
    registerAndVoteAbstain,
    spendScript,
    withdraw,
    withdrawScript,
 )

import Cardano.CIP113.Address (plgAccountAddress, smartWalletAddr)
import Cardano.CIP113.E2E.Deploy (CIP113Deployment (..), deployCIP113, nftValue, withCIP113Devnet)
import Cardano.CIP113.Scripts (loadBlueprint, scriptHashBytes)
import Cardano.CIP113.ThirdParty (ThirdPartyInput (..), thirdPartyTx)
import Cardano.CIP113.Types (
    CIP113Credential (..),
    MintingRegistryProof (..),
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
        describe "CIP-113 freeze/seize (E2E)" $ do
            it "freeze: moves smart-wallet UTxO to lockup address" runFreeze
            it "seize: moves smart-wallet UTxO to new owner address" runSeize

data Env = Env
    { envProvider :: !(Provider IO)
    , envSubmitter :: !(Submitter IO)
    , envPParams :: !(PParams ConwayEra)
    , envDeployment :: !CIP113Deployment
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
            policyKey = case dIssuancePolicy of
                PolicyID h -> scriptHashBytes h
        action
            Env
                { envProvider = provider
                , envSubmitter = submitter
                , envPParams = pp
                , envDeployment = deployment
                , envPolicyKey = policyKey
                }

data NoQ a
data NoErr deriving (Show)

-- ── Common setup: register test policy and fund smart wallet ──────────────────

data Setup = Setup
    { sRegistryNodeIn :: !TxIn
    , sSmartWalletIn :: !TxIn
    , sSmartWalletValue :: !MaryValue
    , sSmartWalletAddr :: !Addr
    , sThirdPartyAccount :: !AccountAddress
    }

hasToken :: PolicyID -> AssetName -> TxOut ConwayEra -> Bool
hasToken policy asset txOut =
    case txOut ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) ->
            Map.findWithDefault 0 asset (Map.findWithDefault Map.empty policy assets) == 1

removeOneToken :: PolicyID -> AssetName -> MaryValue -> MaryValue
removeOneToken policy asset (MaryValue coin (MultiAsset assets)) =
    MaryValue coin (MultiAsset (Map.update prunePolicy policy assets))
  where
    prunePolicy inner =
        let inner' = Map.update pruneAsset asset inner
         in if Map.null inner'
                then Nothing
                else Just inner'
    pruneAsset n =
        let n' = n - 1
         in if n' == 0
                then Nothing
                else Just n'

largeFeeUtxos :: [(TxIn, TxOut ConwayEra)] -> [(TxIn, TxOut ConwayEra)]
largeFeeUtxos utxos =
    case filter ((>= Coin 10_000_000) . (^. coinTxOutL) . snd) utxos of
        [] -> utxos
        large -> large

genesisStakeCredential :: Credential Staking
genesisStakeCredential =
    case genesisAddr of
        Addr _ (KeyHashObj (KeyHash h)) _ ->
            KeyHashObj (KeyHash h)
        _ -> error "genesisAddr is not a key hash address"

runSetup :: Env -> IO Setup
runSetup Env{..} = do
    let CIP113Deployment{..} = envDeployment
        mintingCred = ScriptCredential (scriptHashBytes dPlgHash)
        thirdPartyCred = ScriptCredential (scriptHashBytes dPlgHash)
        thirdPartyAccount = AccountAddress Testnet (AccountId genesisStakeCredential)
        testPolicyKey = envPolicyKey

    let updatedOrigin =
            originNode
                { rnNext = testPolicyKey
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

    let interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx envProvider tx

    -- Tx 0: register and DRep-delegate the key-backed third-party reward
    -- account used by freeze/seize authorisation.
    genesisUtxos0 <- queryUTxOs envProvider genesisAddr
    let registerThirdPartyAccountTx :: TxBuild NoQ NoErr ()
        registerThirdPartyAccountTx = do
            _ <-
                registerAndVoteAbstain
                    genesisStakeCredential
                    (envPParams ^. ppKeyDepositL)
                    PubKeyCert
            pure ()

    txRegisterThirdPartyAccount <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                (largeFeeUtxos genesisUtxos0)
                []
                genesisAddr
                registerThirdPartyAccountTx
    let signedRegisterThirdPartyAccount = addKeyWitness genesisSignKey txRegisterThirdPartyAccount
    rRegisterThirdPartyAccount <- submitTx envSubmitter signedRegisterThirdPartyAccount
    case rRegisterThirdPartyAccount of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "third-party account registration rejected: " <> show reason

    threadDelay 5_000_000

    genesisUtxos1 <- queryUTxOs envProvider genesisAddr
    lockedUtxos1 <- queryUTxOs envProvider dAlwaysFailAddr
    collateralIn1 <- case genesisUtxos1 of
        (txIn, _) : _ -> pure txIn
        [] -> fail "no genesis UTxOs for registry insert collateral"

    -- Tx 1: register test policy
    let insertTx :: TxBuild NoQ NoErr ()
        insertTx = do
            attachScript dRegistrySpendScript
            attachScript dRegistryMintScript
            attachScript dPlgScript
            collateral collateralIn1
            mapM_ (reference . fst) lockedUtxos1
            _ <- spendScript originIn insertRdmr
            withdrawScript
                (plgAccountAddress Testnet dPlgHash)
                (Coin 0)
                (TransferAct [])
            _ <-
                mint
                    dRegistryPolicy
                    (Map.singleton (AssetName (SBS.toShort testPolicyKey)) 1)
                    insertRdmr
            _ <- payTo' dRegistryAddr originValue updatedOrigin
            _ <-
                payTo'
                    dRegistryAddr
                    (nftValue dRegistryPolicy (AssetName (SBS.toShort testPolicyKey)) 2_000_000)
                    newNode
            pure ()

    txInsert <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                (largeFeeUtxos genesisUtxos1 <> registryUtxos)
                lockedUtxos1
                genesisAddr
                insertTx
    let signedInsert = addKeyWitness genesisSignKey txInsert
    rInsert <- submitTx envSubmitter signedInsert
    case rInsert of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "registry insert rejected: " <> show reason

    threadDelay 5_000_000

    registryUtxos2 <- queryUTxOs envProvider dRegistryAddr
    let registryAsset = AssetName (SBS.toShort testPolicyKey)
    (registeredNodeIn, _) <- case filter (hasToken dRegistryPolicy registryAsset . snd) registryUtxos2 of
        u : _ -> pure u
        [] -> fail "no registry UTxO for registered policy"

    -- Tx 2: fund a smart wallet (payment = PLB, staking = genesis payment key)
    let smartWallet =
            smartWalletAddr
                Testnet
                dPlbHash
                genesisStakeCredential
        tokenName = AssetName (SBS.toShort "token")
        fundValue = nftValue dIssuancePolicy tokenName 5_000_000

    genesisUtxos2 <- queryUTxOs envProvider genesisAddr
    lockedUtxos2 <- queryUTxOs envProvider dAlwaysFailAddr
    collateralIn2 <- case genesisUtxos2 of
        (txIn, _) : _ -> pure txIn
        [] -> fail "no genesis UTxOs for fund collateral"
    let fundRefInputs = registeredNodeIn : map fst lockedUtxos2
        fundInputUtxos = largeFeeUtxos genesisUtxos2
        fundRefUtxos = registryUtxos2 <> lockedUtxos2
        registeredNodeRefIdx =
            case List.elemIndex registeredNodeIn (List.sort fundRefInputs) of
                Just ix -> ix
                Nothing -> error "registered policy node missing from fund reference inputs"

    let fundTx :: TxBuild NoQ NoErr ()
        fundTx = do
            attachScript dIssuanceMintScript
            attachScript dPlgScript
            collateral collateralIn2
            reference registeredNodeIn
            mapM_ (reference . fst) lockedUtxos2
            withdrawScript
                (plgAccountAddress Testnet dPlgHash)
                (Coin 0)
                (TransferAct [])
            mint dIssuancePolicy (Map.singleton tokenName 1) (RefInputProof registeredNodeRefIdx)
            _ <- payTo smartWallet fundValue
            pure ()

    txFund <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                fundInputUtxos
                fundRefUtxos
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

    pure
        Setup
            { sRegistryNodeIn = registeredNodeIn
            , sSmartWalletIn = swIn
            , sSmartWalletValue = swOut ^. valueTxOutL
            , sSmartWalletAddr = smartWallet
            , sThirdPartyAccount = thirdPartyAccount
            }

-- ── Freeze ─────────────────────────────────────────────────────────────────────

runFreeze :: Env -> IO ()
runFreeze env@Env{..} = do
    let CIP113Deployment{..} = envDeployment
    Setup{..} <- runSetup env

    let plgAccount = plgAccountAddress Testnet dPlgHash
        lockupAddr = smartWalletAddr Testnet dPlbHash genesisStakeCredential
        tokenName = AssetName (SBS.toShort "token")
        pairedValue = removeOneToken dIssuancePolicy tokenName sSmartWalletValue
        lockupValue = nftValue dIssuancePolicy tokenName 5_000_000

    genesisUtxos <- queryUTxOs envProvider genesisAddr
    swUtxos <- queryUTxOs envProvider sSmartWalletAddr
    regUtxos <- queryUTxOs envProvider dRegistryAddr
    lockedUtxos <- queryUTxOs envProvider dAlwaysFailAddr
    collateralIn <- case genesisUtxos of
        (txIn, _) : _ -> pure txIn
        [] -> fail "no genesis UTxOs for collateral"
    let thirdPartyRefInputs = sRegistryNodeIn : map fst lockedUtxos
        registryNodeRefIdx =
            case List.elemIndex sRegistryNodeIn (List.sort thirdPartyRefInputs) of
                Just ix -> ix
                Nothing -> error "registered policy node missing from third-party reference inputs"

    let interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx envProvider tx

    let freezeTx :: TxBuild NoQ NoErr ()
        freezeTx = do
            collateral collateralIn
            thirdPartyTx
                plgAccount
                dPlbScript
                dPlgScript
                [ ThirdPartyInput
                    { tpTxIn = sSmartWalletIn
                    , tpRegistryNodeIdx = registryNodeRefIdx
                    , tpOutputsStartIdx = 0
                    }
                ]
                [sRegistryNodeIn]
                []
                [ (sSmartWalletAddr, pairedValue)
                , (lockupAddr, lockupValue)
                ]
            mapM_ (reference . fst) lockedUtxos
            withdraw sThirdPartyAccount (Coin 0)

    tx <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                (largeFeeUtxos genesisUtxos <> swUtxos)
                (regUtxos <> lockedUtxos)
                genesisAddr
                freezeTx

    let signed = addKeyWitness genesisSignKey tx
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
        newOwnerAddr = smartWalletAddr Testnet dPlbHash genesisStakeCredential
        tokenName = AssetName (SBS.toShort "token")
        pairedValue = removeOneToken dIssuancePolicy tokenName sSmartWalletValue
        newOwnerValue = nftValue dIssuancePolicy tokenName 5_000_000

    genesisUtxos <- queryUTxOs envProvider genesisAddr
    swUtxos <- queryUTxOs envProvider sSmartWalletAddr
    regUtxos <- queryUTxOs envProvider dRegistryAddr
    lockedUtxos <- queryUTxOs envProvider dAlwaysFailAddr
    collateralIn <- case genesisUtxos of
        (txIn, _) : _ -> pure txIn
        [] -> fail "no genesis UTxOs for collateral"
    let thirdPartyRefInputs = sRegistryNodeIn : map fst lockedUtxos
        registryNodeRefIdx =
            case List.elemIndex sRegistryNodeIn (List.sort thirdPartyRefInputs) of
                Just ix -> ix
                Nothing -> error "registered policy node missing from third-party reference inputs"

    let interpret :: InterpretIO NoQ
        interpret = InterpretIO $ \case {}
        eval tx =
            Map.map (either (Left . show) Right)
                <$> evaluateTx envProvider tx

    let seizeTx :: TxBuild NoQ NoErr ()
        seizeTx = do
            collateral collateralIn
            thirdPartyTx
                plgAccount
                dPlbScript
                dPlgScript
                [ ThirdPartyInput
                    { tpTxIn = sSmartWalletIn
                    , tpRegistryNodeIdx = registryNodeRefIdx
                    , tpOutputsStartIdx = 0
                    }
                ]
                [sRegistryNodeIn]
                []
                [ (sSmartWalletAddr, pairedValue)
                , (newOwnerAddr, newOwnerValue)
                ]
            mapM_ (reference . fst) lockedUtxos
            withdraw sThirdPartyAccount (Coin 0)

    tx <-
        either (fail . show) pure
            =<< build
                (mkPParamsBound envPParams)
                interpret
                eval
                (largeFeeUtxos genesisUtxos <> swUtxos)
                (regUtxos <> lockedUtxos)
                genesisAddr
                seizeTx

    let signed = addKeyWitness genesisSignKey tx
    result <- submitTx envSubmitter signed
    case result of
        Submitted _ -> pure ()
        Rejected reason -> fail $ "seize tx rejected: " <> show reason
