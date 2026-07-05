# Issue 53 - Transfer Real Transaction

## User Story

As a CIP-113 token holder, I can run `cip113-cli transfer` against a live node
and a deployment descriptor and receive a real unsigned Conway transaction body
that moves registered programmable tokens between smart-wallet addresses.

## Functional Requirements

- `transfer` must require `--deployment FILE`; without it the command exits 1
  with a clear user-facing error.
- Real `transfer --deployment FILE` transaction building is supported only with
  the node backend selected by `--socket-path` and `--network-magic`.
- Offline JSON, Kupo, and Blockfrost transfer paths must exit 1 clearly instead
  of emitting the current placeholder CBOR map.
- `transfer` must accept a funding/change address for balancing the unsigned
  transaction body against live node UTxOs.
- `transfer` must call `Cardano.CIP113.Registry.findNode` using the loaded
  `CIP113Deployment`, the live `Cardano.Node.Client.Provider.Provider IO`, and
  the registry reference-input set that will be passed to `transferTx`.
- `transfer` must build `TransferInput` values whose `tiProof` index matches
  `ResolvedRegistryNode.rrnReferenceInputIndex`.
- For registered tokens, `transfer` must include a `TransferLogic` entry using
  the registered transfer-logic script from the deployment-compatible registry
  node.
- `transfer` must call `Cardano.CIP113.Transfer.transferTx` and print real
  unsigned Conway transaction-body CBOR hex, not the current placeholder CBOR
  summary map.
- `--json` mode must continue to return `{"tx":"<cbor-hex>"}` with the real
  transaction body hex.
- `docs/cli.md` must document that real `transfer --deployment` transaction
  building currently requires the node backend.

## Success Criteria

- A CLI-driven e2e smoke deploys CIP-113 on the devnet, registers a token using
  the real `cip113-cli register` flow, funds a smart wallet, runs the actual
  `cip113-cli transfer` executable, pipes its output through `cip113-cli sign`,
  submits the signed transaction through the N2C submitter, and asserts a
  `Submitted` result.
- `nix build .#e2e-tests` succeeds.
- The CI-shaped e2e command from `gate.sh` succeeds with `CIP113_CLI` and
  `PATH` set to the built `cip113-cli` and `cardano-node` outputs.
- `fourmolu` and `hlint` pass for `src`, `exe`, and `e2e-test`.

## Scope Notes

- Parent precedent from #52 chose node-only real transaction building for the
  current CLI builder tickets. Offline, Kupo, and Blockfrost real-builder
  parity is follow-up scope.
- The ticket may touch `exe/Main.hs` for minimal transfer-specific deployment
  and node-provider plumbing, `exe/Cardano/CIP113/CLI/Command/Transfer.hs`, one
  new e2e spec file plus required e2e test-suite registration, the cabal file
  only for genuinely required test-suite registration/dependencies, and
  `docs/cli.md` for the node-only constraint.
- `Register.hs`, `Freeze.hs`, and `Seize.hs` remain sibling-owned and must not
  be edited.
