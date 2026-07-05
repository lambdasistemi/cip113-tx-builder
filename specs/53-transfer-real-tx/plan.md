# Issue 53 - Transfer Real Transaction Plan

## Architecture

`exe/Main.hs` will mirror the merged register path for `transfer`: load the
deployment descriptor, require it for real building, reject non-node providers,
and pass a live `Cardano.Node.Client.Provider.Provider IO` to a new
`Transfer.runWithNodeProvider` entry point. The node-provider bridge should
reuse the same connection shape as register.

`Transfer.hs` will replace the placeholder CBOR map with a real `TxBuild`:

- parse the source, destination, change address, and policy id into ledger
  shapes;
- derive the source and destination smart-wallet addresses used by the CIP-113
  transfer scripts;
- query live UTxOs for the source smart wallet, change/funding address,
  registry address, and locked always-fail address;
- select the smart-wallet UTxO(s) carrying the requested asset;
- resolve the registered policy with `findNode`, using the exact registry
  reference inputs supplied to `transferTx`;
- construct `TransferInput` values from the selected smart-wallet UTxOs and
  the resolved registry proof index;
- construct the registered token's `TransferLogic` from the deployment PLG
  script/account and an appropriate unit redeemer;
- call `transferTx`, add collateral and any always-fail references needed by
  the deployed scripts, balance with the requested change address, and serialize
  the unsigned Conway body as definite CBOR hex using the register precedent.

The e2e smoke will exercise the executable boundary:

1. start the existing `withCIP113DevnetSocket` harness;
2. deploy CIP-113 and write the descriptor to a temp file;
3. run the built `cip113-cli register` subprocess with node flags, deployment,
   policy id, and change address;
4. sign and submit the register transaction, then wait for the registry update;
5. fund a smart-wallet UTxO carrying the registered token;
6. run `cip113-cli transfer` with node flags, deployment, change address,
   source smart-wallet address, destination address, policy id, token name, and
   amount;
7. pipe the emitted body hex through `cip113-cli sign`;
8. submit the signed transfer transaction through the existing N2C submitter;
9. assert `Submitted`.

## Slice Breakdown

### Slice 1 - Real transfer CLI path and smoke

Implement the transfer node-only path, real `transferTx` builder output,
registry `findNode` proof resolution, CLI subprocess e2e smoke, and docs. This
is intentionally one vertical slice because the e2e proof depends on the
builder, provider bridge, and command-line contract landing together.

## Verification

The ticket gate is `./gate.sh`. It runs:

- `git diff --check`
- `fourmolu -m check` over tracked Haskell files
- `hlint src exe e2e-test`
- `nix build .#cip113-cli`
- `nix build .#cardano-node`
- `nix build .#e2e-tests`
- the e2e test binary from `e2e-test/` with `CIP113_CLI` and `PATH` set as in
  GitHub Actions

The slice must run focused checks first where useful, then the full gate before
commit. Final PR readiness requires a green `./gate.sh` at HEAD.
