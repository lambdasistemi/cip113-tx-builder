# Issue 54 - Freeze/Seize Real Transactions Specification

## User Story

As a CIP-113 operator, I want `cip113-cli freeze` and `cip113-cli seize` to
build real unsigned Conway transaction bodies from a live node-backed
deployment, so I can sign and submit third-party actions through the same CLI
path already proven for register and transfer.

## Functional Requirements

- `freeze` and `seize` must require `--deployment FILE` for real transaction
  building.
- Real `freeze` and `seize` builds must be node-only. Offline, Blockfrost, and
  Kupo provider selections must exit with code 1 and a clear user-facing error.
- Both commands must accept `--change-address ADDR` for funding, balancing,
  change, and collateral selection during live node-backed builds.
- Both commands must resolve the registered policy with
  `Cardano.CIP113.Registry.findNode` and use the resolved registry reference
  input index when constructing `ThirdPartyInput`.
- Both commands must call `Cardano.CIP113.ThirdParty.thirdPartyTx` instead of
  emitting the placeholder summary CBOR map on the node-backed path.
- Both commands must emit unsigned Conway transaction-body CBOR hex in plain
  and JSON modes, using definite-length CBOR serialization.
- The CLI e2e suite must include smoke coverage for both commands: prepare a
  real devnet deployment and registered token, build the command output, pipe it
  through `cip113-cli sign`, submit through the devnet submitter, and assert a
  real `Submitted` result.
- Documentation must describe the node-only `--deployment` and
  `--change-address` constraint for `freeze` and `seize`.

## Non-Goals

- Changing register or transfer command behavior.
- Productizing register-time selection of per-token third-party logic scripts.
- Changing `Cardano.CIP113.Deployment`, `Cardano.CIP113.Registry`, or library
  third-party builders.

## Success Criteria

- `freeze` and `seize` no longer emit placeholder summary maps on the real node
  path.
- The e2e test binary proves both command subprocesses can build, sign, submit,
  and reach `Submitted` on the local devnet.
- `./gate.sh` passes at HEAD before the PR is handed to the parent for merge
  review.
