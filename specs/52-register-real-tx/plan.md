# Issue 52 - Register Real Transaction Plan

## Architecture

`exe/Main.hs` will stop treating a loaded deployment descriptor as a forced
no-op for `register`. Instead, it will load the descriptor into a
`CIP113Deployment`, select a register-specific node path when
`--socket-path`/`--network-magic` are present, and pass the deployment plus the
underlying node `Provider IO` into `Register.runWithNodeProvider`.

For this ticket, real `register --deployment` builds are node-only. The other
CLI UTxO backends still exist for sibling placeholder-era commands, but
`register --deployment` with offline, Kupo, or Blockfrost exits 1 with a clear
message. This matches parent answer `A-001-provider-bridge-scope` and avoids
widening the shared provider abstraction inside this child.

`Register.hs` will replace the placeholder CBOR map with a real `TxBuild`:

- decode the target policy ID into the 28-byte registry key;
- resolve the predecessor with `findInsertionPoint`;
- derive `updatedPredecessor`, `newNode`, and `RegistryInsert` as in
  `RegisterSpec.runInsert`;
- query live UTxOs for the change/funding address, registry address, and locked
  always-fail address;
- build an unsigned Conway body with `registerTx`, PLG withdraw-zero support
  where required by the existing e2e construction, collateral, and the selected
  change address;
- serialize the unsigned transaction body as CBOR hex for stdout/JSON output.

The e2e smoke will exercise the executable boundary, not library calls:

1. start the existing `withCIP113Devnet` harness;
2. deploy CIP-113 and write the descriptor to a temp file;
3. run the built `cip113-cli register` subprocess with node flags, deployment,
   policy id, and change address;
4. pipe the emitted body hex through `cip113-cli sign`;
5. submit the signed tx through the existing N2C submitter;
6. assert `Submitted`.

## Slice Breakdown

### Slice 1 - Node-only deployment plumbing

Thread the loaded deployment into the register command path and add the
node-only resolver-provider branch in `Main.hs`. `register --deployment`
without a node backend must fail before any placeholder output can be emitted.

### Slice 2 - Real register builder output

Replace the placeholder register CBOR map with real `registerTx` construction
and serialization in `Register.hs`, including predecessor resolution and
balancing inputs queried from the node provider.

### Slice 3 - CLI e2e smoke and docs

Add the executable sign-and-submit smoke, wire it into the e2e test suite, and
update CLI documentation for the node-only `register --deployment` constraint.

## Verification

The ticket gate is `./gate.sh`. It runs:

- `git diff --check`
- `fourmolu -m check` over tracked Haskell files
- `hlint src exe e2e-test`
- `nix build .#cip113-cli`
- `nix build .#e2e-tests`
- the e2e test binary from `e2e-test/`

Each slice must run a focused command first, then the full gate before commit.
Final PR readiness requires a green `./gate.sh` at HEAD.
