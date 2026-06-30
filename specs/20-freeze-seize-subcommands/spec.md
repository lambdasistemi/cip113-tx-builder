# Issue 20 - Freeze and Seize Subcommands

## User Story

As a compliance officer, I can run `cip113 freeze` or `cip113 seize`
against an offline UTxO JSON file and receive an unsigned CIP-113
third-party transaction body as CBOR hex on stdout.

## Functional Requirements

- `freeze --help` documents `--utxo-file FILE`,
  `--target-address ADDR`, `--token-name NAME`, and
  `--policy-id HEX`.
- `seize --help` documents `--utxo-file FILE`,
  `--target-address ADDR`, `--to-address ADDR`, `--token-name NAME`,
  and `--policy-id HEX`.
- Both commands load the offline UTxO JSON through the existing
  `OfflineUTxOProvider` and query target UTxOs by `--target-address`.
- Missing required flags, malformed policy ids, empty names/addresses,
  unreadable UTxO files, absent target UTxOs, and target UTxOs without
  the requested token exit with code 1 and a useful error.
- Successful runs exit 0 and print a non-empty CBOR hex string.
- With the global `--json` flag, stdout is a JSON object of shape
  `{"tx":"<cbor-hex>"}`.
- The commands never sign, submit, hold keys, or introduce live
  node/indexer backends.

## Scope Notes

The parent brief narrows this ticket to the current CLI skeleton and
offline provider flags. It does not authorize changes to `exe/Main.hs`,
the provider typeclass, `flake.nix`, `src/`, dependency manifests, or
sibling command modules.

The GitHub issue body still mentions earlier third-party flags such as
`--smart-wallet-input`, `--always-fail-script`, `--third-party-account`,
and `--new-owner`. This ticket follows the parent brief's explicit
offline-provider option set instead.

The executable is named `cip113-cli`. The smoke gate creates a temporary
`cip113` symlink to that binary so the command shape in the brief is
exercised without changing package metadata.

## Success Criteria

- `nix build .#cip113-cli --no-link` succeeds.
- `nix develop --quiet -c fourmolu -m check exe` succeeds.
- `nix develop --quiet -c hlint exe` succeeds.
- `./gate.sh` succeeds, including human and JSON smoke commands for
  both `freeze` and `seize` against offline fixtures.
