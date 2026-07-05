# Spec: CLI Deployment Descriptor Flag

## User Story

As an operator building CIP-113 transactions from the CLI, I want the
`register`, `transfer`, `freeze`, and `seize` commands to accept a deployment
descriptor file, so later transaction-building tickets can resolve deployed
scripts and addresses without redeploying the protocol.

## Functional Requirements

- Add a shared `--deployment FILE` option to `register`, `transfer`, `freeze`,
  and `seize`.
- Support the same global and per-command placement style used by provider
  options; a per-command value overrides the global value.
- When supplied, load the file as `Cardano.CIP113.Deployment.CIP113Deployment`
  using its existing `FromJSON` instance.
- Exit with code 1 and a clear `cip113-cli:` message when the file cannot be
  read or cannot be decoded.
- Preserve existing behavior when `--deployment` is omitted.
- Do not change transaction-building behavior in this ticket; commands may
  continue emitting the existing placeholder CBOR.

## Success Criteria

- `cip113-cli --deployment deployment.json register ...` and the equivalent
  command-local form parse for all four transaction-building commands.
- A real descriptor JSON derived from the existing blueprint fixture loads
  without error.
- Missing and malformed descriptor files exit 1 with clear stderr.
- `docs/cli.md` documents the flag for all four commands.
- `./gate.sh`, fourmolu, and hlint pass.

## Non-Goals

- No registry lookup wiring.
- No calls to `findInsertionPoint` or `findNode`.
- No replacement of the existing placeholder transaction builders.
- No changes to `sign`, `vault seal`, `Cardano.CIP113.Deployment`, or
  `Cardano.CIP113.Registry`.
