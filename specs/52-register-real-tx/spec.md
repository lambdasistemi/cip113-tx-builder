# Issue 52 - Register Real Transaction

## User Story

As a CIP-113 token issuer, I can run `cip113-cli register` against a live node
and a deployment descriptor and receive a real unsigned Conway transaction body
that registers my policy in the on-chain registry.

## Functional Requirements

- `register` must require `--deployment FILE`; without it the command exits 1
  with a clear user-facing error.
- When `--deployment FILE` is supplied, real register transaction building is
  supported only with the node backend selected by `--socket-path` and
  `--network-magic`.
- If `--deployment FILE` is supplied with offline, Kupo, or Blockfrost
  backends, the command exits 1 and explains that real register transaction
  building currently requires the node backend.
- `register` must call `Cardano.CIP113.Registry.findInsertionPoint` using the
  loaded `CIP113Deployment` and a live `Cardano.Node.Client.Provider.Provider IO`.
- `register` must construct the updated predecessor `RegistryNode`, new
  `RegistryNode`, and `RegistryInsert` redeemer using the same datum shape as
  `e2e-test/Cardano/CIP113/E2E/RegisterSpec.hs::runInsert`.
- `register` must call `Cardano.CIP113.Register.registerTx` and print real
  unsigned Conway transaction-body CBOR hex, not the current placeholder CBOR
  summary map.
- `register` must accept the funding/change address needed to balance the
  unsigned transaction body against live node UTxOs.
- `--json` mode must continue to return `{"tx":"<cbor-hex>"}` with the real
  transaction body hex.
- `docs/cli.md` must document that real `register --deployment` transaction
  building currently requires the node backend.

## Success Criteria

- A CLI-driven e2e smoke deploys CIP-113 on the devnet, runs the actual
  `cip113-cli register` executable, pipes its output through `cip113-cli sign`,
  submits the signed transaction through the N2C submitter, and asserts a
  `Submitted` result.
- `nix build .#e2e-tests` succeeds.
- `./result/bin/e2e-tests`, run from `e2e-test/`, succeeds.
- `fourmolu` and `hlint` pass for `src`, `exe`, and `e2e-test`.

## Scope Notes

- Parent answer `A-001-provider-bridge-scope` chose node-only real transaction
  building for this ticket. Offline, Kupo, and Blockfrost real-builder parity
  is follow-up scope.
- The ticket may touch `exe/Main.hs` for minimal deployment/node-provider
  plumbing, `exe/Cardano/CIP113/CLI/Command/Register.hs`, one new e2e spec
  file plus required e2e test-suite registration, and `docs/cli.md` for the
  node-only constraint.
- `Transfer.hs`, `Freeze.hs`, and `Seize.hs` remain sibling-owned and must not
  be edited.
