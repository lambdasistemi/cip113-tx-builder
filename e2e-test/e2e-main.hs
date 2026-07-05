module Main (main) where

import Test.Hspec (hspec)

import Cardano.CIP113.E2E.DeploymentSpec qualified as DeploymentSpec
import Cardano.CIP113.E2E.RegisterCLISpec qualified as RegisterCLISpec
import Cardano.CIP113.E2E.RegisterSpec qualified as RegisterSpec
import Cardano.CIP113.E2E.RegistryResolverSpec qualified as RegistryResolverSpec
import Cardano.CIP113.E2E.ThirdPartySpec qualified as ThirdPartySpec
import Cardano.CIP113.E2E.TransferCLISpec qualified as TransferCLISpec

main :: IO ()
main = hspec $ do
    DeploymentSpec.spec
    RegisterCLISpec.spec
    RegisterSpec.spec
    RegistryResolverSpec.spec
    ThirdPartySpec.spec
    TransferCLISpec.spec
