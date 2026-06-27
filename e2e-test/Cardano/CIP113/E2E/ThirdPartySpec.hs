{-# LANGUAGE OverloadedStrings #-}

module Cardano.CIP113.E2E.ThirdPartySpec (spec) where

import Test.Hspec

spec :: Spec
spec =
    describe "CIP-113 freeze/seize (E2E)" $ do
        it "freeze: moves tokens from smart wallet to lockup address" $
            pendingWith "issue #6: freeze integration test"
        it "seize: moves tokens from smart wallet to a new owner" $
            pendingWith "issue #7: seize integration test"
