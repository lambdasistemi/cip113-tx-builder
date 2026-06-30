# Issue 19 - Transfer Subcommand

## User Story

As a token holder, I can run `cip113 transfer` against an offline UTxO
JSON file and receive an unsigned CIP-113 token transfer transaction
body as CBOR hex on stdout.

## Functional Requirements

- `transfer --help` documents `--utxo-file FILE`,
  `--from-address ADDR`, `--to-address ADDR`, `--token-name NAME`,
  `--policy-id HEX`, and `--amount INT`.
- The command loads the offline UTxO JSON through the existing
  `OfflineUTxOProvider` and queries sender UTxOs by `--from-address`.
- Missing required flags, malformed policy ids, empty names/addresses,
  invalid amounts, unreadable UTxO files, absent sender UTxOs, and
  insufficient token balance exit with code 1 and a useful error.
- Successful runs exit 0 and print a non-empty CBOR hex string.
- With the global `--json` flag, stdout is a JSON object of shape
  `{"tx":"<cbor-hex>"}`.
- The command never signs, submits, or holds keys.

## Scope Notes

The parent brief narrows this ticket to the current CLI skeleton and
offline provider flags. It does not authorize changes to `exe/Main.hs`,
the provider typeclass, `src/`, `flake.nix`, dependency manifests, or
sibling command modules.

The existing executable is named `cip113-cli`. The smoke gate creates a
temporary `cip113` symlink to that binary so the command shape in the
brief is exercised without changing package metadata.

## Success Criteria

- `nix build .#cip113-cli --no-link` succeeds.
- `nix develop --quiet -c fourmolu -m check exe` succeeds.
- `nix develop --quiet -c hlint exe` succeeds.
- `./gate.sh` succeeds, including human and JSON transfer smoke commands
  against the offline fixture.
