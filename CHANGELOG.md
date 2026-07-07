# Changelog

## [0.1.2](https://github.com/lambdasistemi/cip113-tx-builder/compare/v0.1.1...v0.1.2) (2026-07-07)


### Features

* add CIP-113 registry resolver ([52f6ccd](https://github.com/lambdasistemi/cip113-tx-builder/commit/52f6ccde73e1ebedc5ff732bcfc14cd1f2777852))
* add shared deployment descriptor flag ([17748e7](https://github.com/lambdasistemi/cip113-tx-builder/commit/17748e7e7e1e54490aff423e46a68373fdd28fdd))
* add vault seal and sign commands ([d52118a](https://github.com/lambdasistemi/cip113-tx-builder/commit/d52118af7a4a1cb49186b301ffc57692bbddbed9))
* **cli:** convert freeze and seize to shared settings ([5b57dd7](https://github.com/lambdasistemi/cip113-tx-builder/commit/5b57dd7c8ce9fa6ec6b6c79c39a06c0cfd2522bc))
* migrate CLI parser foundation to opt-env-conf ([b228246](https://github.com/lambdasistemi/cip113-tx-builder/commit/b228246ffff4d96ca9e2429de92ae152549b6d12))
* move register parser to shared settings ([19493bb](https://github.com/lambdasistemi/cip113-tx-builder/commit/19493bb5774b8c38f75c3bd24cbffa64eb5e2b30))
* move transfer parser to shared settings ([ff06fea](https://github.com/lambdasistemi/cip113-tx-builder/commit/ff06fea95027094b414585f7713af8fb67017a51))
* **nix:** expose release artifact outputs ([91e0902](https://github.com/lambdasistemi/cip113-tx-builder/commit/91e090287e032be80743d4ca6bb18243f58fa291))
* **register:** build real register tx ([bae3160](https://github.com/lambdasistemi/cip113-tx-builder/commit/bae316015a960fde2135855a292c0c0af2405ffe))
* **register:** require node deployment plumbing ([6f87a05](https://github.com/lambdasistemi/cip113-tx-builder/commit/6f87a0598e3ee73db43032699a3d808f46b08775))
* **transfer:** build real transfer tx ([8ad49eb](https://github.com/lambdasistemi/cip113-tx-builder/commit/8ad49eb18838e66aa7a2e41602154067d25556d9))
* wire freeze seize to real thirdPartyTx ([5f320e8](https://github.com/lambdasistemi/cip113-tx-builder/commit/5f320e8583e6f2b5e96315660c1ebfbfdd815e24))


### Bug Fixes

* **register:** submit CLI-built registry insertion ([83b4b89](https://github.com/lambdasistemi/cip113-tx-builder/commit/83b4b8985d5756bb443e9c7c0c5e6539353baff1))

## [0.1.1](https://github.com/lambdasistemi/cip113-tx-builder/compare/v0.1.0...v0.1.1) (2026-06-30)


### Features

* add CIP-113 CLI skeleton ([#33](https://github.com/lambdasistemi/cip113-tx-builder/issues/33)) ([4e1afd5](https://github.com/lambdasistemi/cip113-tx-builder/commit/4e1afd5116b9f12c6060e88fa98fe5094b43ac94))
* add flake.nix with native and WASM package outputs ([1466523](https://github.com/lambdasistemi/cip113-tx-builder/commit/1466523325b9f562190fc66e74178480157255cc))
* add flake.nix with native and WASM package outputs ([39e0f74](https://github.com/lambdasistemi/cip113-tx-builder/commit/39e0f740c6bd0f0275bcbca43b5c07b005ebf7de)), closes [#3](https://github.com/lambdasistemi/cip113-tx-builder/issues/3)
* CIP-113 freeze/seize E2E tests pass ([c3102dc](https://github.com/lambdasistemi/cip113-tx-builder/commit/c3102dcf163754eefc107f26df1f09dab1d3a090))
* devnet test infrastructure ([d47bd1b](https://github.com/lambdasistemi/cip113-tx-builder/commit/d47bd1b8f71297d5d17f08343bc95de787b4503e))
* devnet test infrastructure and script loading ([184ebeb](https://github.com/lambdasistemi/cip113-tx-builder/commit/184ebeb7599eea1248ed6fa80e905937ba95a44e))
* implement freeze/seize E2E integration tests ([3537544](https://github.com/lambdasistemi/cip113-tx-builder/commit/3537544f83ff9a93b05c71fda151ae5b7c8dd155))
* initial CIP-113 tx builder library ([f9dce28](https://github.com/lambdasistemi/cip113-tx-builder/commit/f9dce28ea9949917dfaffea3dc7c8f150dc92384))


### Bug Fixes

* compilation errors in e2e-tests (SubmitResult, payTo', TxId bytes, NoErr Show, ScriptCredential) ([02bf9cd](https://github.com/lambdasistemi/cip113-tx-builder/commit/02bf9cd06a3fb52af7436e1b50bb542d06750fac))
* compilation errors in Scripts module (DataKinds, OverloadedStrings, Parser, ScriptHash pattern) ([3f8e6c6](https://github.com/lambdasistemi/cip113-tx-builder/commit/3f8e6c6fa4fb3fcf3e0a9c26799bf75c2312e3b2))
* parse manifest with sed (no python3/jq in nixos runner PATH) ([0cd6bac](https://github.com/lambdasistemi/cip113-tx-builder/commit/0cd6bacda682f712793ecf2d9498bd1cba7be541))
* replace awk with bash read in drift check (awk not in nixos runner PATH) ([e5a93c2](https://github.com/lambdasistemi/cip113-tx-builder/commit/e5a93c20a7f3d7cd8035e52d14e17f8698c5396a))
* restore RecordWildCards pragma in Types.hs (used by {..} patterns) ([0214eb0](https://github.com/lambdasistemi/cip113-tx-builder/commit/0214eb01aa84d1aba6da13aeeed341d29e880c60))
* use python3 instead of jq in version checks (not in nixos runner PATH) ([73c10fe](https://github.com/lambdasistemi/cip113-tx-builder/commit/73c10feb96acead0b2771f415e692d701cdc839d))
* use scriptHashBytes for ScriptHash in Deploy.hs, add scriptHashBytes export ([841195a](https://github.com/lambdasistemi/cip113-tx-builder/commit/841195a6133bac9be7d2ed7cafd700074795d72f))
