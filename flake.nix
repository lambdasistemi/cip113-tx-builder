{
  description = "CIP-113 programmable token transaction builders";
  nixConfig = {
    extra-substituters = [
      "https://cache.iog.io"
      "https://paolino.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "paolino.cachix.org-1:ecmgO3CXdgSWA2cHlm4srknd/cLFMLmK3i3NrzeDFaE="
    ];
  };
  inputs = {
    haskellNix = {
      url =
        "github:input-output-hk/haskell.nix/8b447d7f57d62fab9249f79bb916bc891e29b9d0";
      inputs.hackage.follows = "hackageNix";
    };
    hackageNix = {
      url = "github:input-output-hk/hackage.nix/b6b4aa4bd699f743238da45c7f43da5a26a822f7";
      flake = false;
    };
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    iohkNix = {
      url =
        "github:input-output-hk/iohk-nix/f444d972c301ddd9f23eac4325ffcc8b5766eee9";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    CHaP = {
      url =
        "github:intersectmbo/cardano-haskell-packages/887d73ce434831e3a67df48e070f4f979b3ac5a6";
      flake = false;
    };
    cardano-node.url = "github:IntersectMBO/cardano-node/10.7.0";
    flake-parts.url = "github:hercules-ci/flake-parts";
    bundlers = {
      url = "github:NixOS/bundlers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ghc-wasm-meta.url =
      "gitlab:haskell-wasm/ghc-wasm-meta?host=gitlab.haskell.org";
    dev-assets.url = "github:paolino/dev-assets";
    dev-assets-mkdocs.url = "github:paolino/dev-assets?dir=mkdocs";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, haskellNix, iohkNix, CHaP, dev-assets-mkdocs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      perSystem = { system, ... }:
        let
          pkgs = import nixpkgs {
            overlays = [
              iohkNix.overlays.crypto
              haskellNix.overlay
              iohkNix.overlays.haskell-nix-crypto
              iohkNix.overlays.cardano-lib
            ];
            inherit system;
          };
          lib = pkgs.lib;
          packageVersion =
            let
              cabalLines =
                lib.splitString "\n" (builtins.readFile ./cip113-tx-builder.cabal);
              versionLines =
                builtins.filter (line: builtins.match "version:.*" line != null) cabalLines;
              versionMatch =
                builtins.match "version:[[:space:]]*(.*)" (builtins.head versionLines);
            in
            builtins.head versionMatch;
          sourceRevision = self.shortRev or (self.dirtyShortRev or "dirty");
          devArtifactVersion = "${packageVersion}-${sourceRevision}";
          releasePleaseVersion =
            (builtins.fromJSON (builtins.readFile ./.release-please-manifest.json)).".";
          releasePleaseTag = "v${releasePleaseVersion}";
          lintPkgs = pkgs;
          indexState = "2026-02-17T10:15:41Z";
          indexTool = { index-state = indexState; };
          fix-libs = { lib, pkgs, ... }: {
            packages.cardano-crypto-praos.components.library.pkgconfig =
              lib.mkForce [ [ pkgs.libsodium-vrf ] ];
            packages.cardano-crypto-class.components.library.pkgconfig =
              lib.mkForce
                [ [ pkgs.libsodium-vrf pkgs.secp256k1 pkgs.libblst ] ];
            packages.cardano-lmdb.components.library.pkgconfig =
              lib.mkForce [ [ pkgs.lmdb ] ];
            packages.cardano-ledger-binary.components.library.doHaddock =
              lib.mkForce false;
            packages.plutus-core.components.library.doHaddock =
              lib.mkForce false;
            packages.plutus-ledger-api.components.library.doHaddock =
              lib.mkForce false;
            packages.plutus-tx.components.library.doHaddock =
              lib.mkForce false;
          };
          mkProject = extraModules: pkgs.haskell-nix.cabalProject' {
            name = "cip113-tx-builder";
            src = ./.;
            compiler-nix-name = "ghc9123";
            shell = {
              withHoogle = true;
              tools = {
                cabal = indexTool;
              };
              buildInputs = [
                lintPkgs.haskellPackages.cabal-fmt
                lintPkgs.haskellPackages.fourmolu
                lintPkgs.haskellPackages.hlint
                pkgs.just
              ];
            };
            modules = [ fix-libs ] ++ extraModules;
            inputMap = {
              "https://chap.intersectmbo.org/" = CHaP;
            };
          };
          project = mkProject [
            {
              packages.cip113-tx-builder.flags.build-e2e-tests = true;
            }
          ];
          cip113Cli =
            project.hsPkgs.cip113-tx-builder.components.exes.cip113-cli;
          cip113CliForBundlers = pkgs.symlinkJoin {
            name = "cip113-cli-${packageVersion}";
            paths = [ cip113Cli ];
            meta.mainProgram = "cip113-cli";
          };
          cip113Wasm =
            let
              wasmTools = inputs.ghc-wasm-meta.packages.${system};
            in
            pkgs.runCommand "cip113-wasm"
              {
                nativeBuildInputs = [ wasmTools.all_9_12 ];
                src = ./.;
              } ''
              export HOME=$(mktemp -d)
              cd $src
              wasm32-wasi-cabal --project-file=cabal-wasm.project build cip113-tx-builder 2>&1
              mkdir -p $out
              echo "WASM build placeholder — full FOD pattern TBD in issue #3" > $out/README
            '';
          linuxReleasePackages = lib.optionalAttrs pkgs.stdenv.isLinux {
            linux-release-artifacts =
              import ./nix/linux-release.nix {
                inherit pkgs system packageVersion;
                package = cip113CliForBundlers;
                bundlers = inputs.bundlers;
              };
            linux-dev-release-artifacts =
              import ./nix/linux-release.nix {
                inherit pkgs system packageVersion;
                artifactVersion = devArtifactVersion;
                package = cip113CliForBundlers;
                bundlers = inputs.bundlers;
              };
          };
          darwinReleasePackages = lib.optionalAttrs pkgs.stdenv.isDarwin {
            darwin-release-artifacts =
              import ./nix/darwin-release.nix {
                inherit inputs pkgs packageVersion;
                package = cip113CliForBundlers;
                releaseTag = releasePleaseTag;
              };
            darwin-dev-homebrew-artifacts =
              import ./nix/darwin-release.nix {
                inherit inputs pkgs packageVersion;
                artifactVersion = devArtifactVersion;
                package = cip113CliForBundlers;
                releaseTag = "dev-homebrew";
                formulaName = "cip113-cli-dev";
                formulaClass = "Cip113CliDev";
                formulaVersion = devArtifactVersion;
                formulaExtraLines =
                  "\n  conflicts_with \"cip113-cli\", because: \"both install the same command-line tools\"";
              };
          };
        in
        {
          packages = {
            cip113-tx-builder =
              project.hsPkgs.cip113-tx-builder.components.library;
            cip113-cli = cip113Cli;
            e2e-tests =
              project.hsPkgs.cip113-tx-builder.components.tests.e2e-tests;
            cardano-node =
              inputs.cardano-node.packages.${system}.cardano-node;
            cip113-wasm = cip113Wasm;
          } // linuxReleasePackages // darwinReleasePackages;
          devShells.default = project.shell;
          devShells.docs = pkgs.mkShell {
            inputsFrom = [ dev-assets-mkdocs.devShells.${system}.default ];
            packages = [ pkgs.just ];
          };
        };
    };
}
