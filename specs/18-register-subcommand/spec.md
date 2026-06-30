# Issue 18 - Register Subcommand

## User Story

As a token issuer, I can run `cip113-cli register` against an offline
UTxO JSON file and receive an unsigned CIP-113 registry registration
transaction body as CBOR hex on stdout.

## Functional Requirements

- `register --help` documents `--utxo-file FILE`,
  `--registry-utxo TXID#IX`, `--token-name NAME`, and
  `--policy-id HEX`.
- The command loads the offline UTxO JSON through the existing
  `OfflineUTxOProvider` and queries the requested registry UTxO by ref.
- Missing required flags, bad references, malformed policy ids, unreadable
  UTxO files, and missing UTxOs exit with code 1 and a useful error.
- Successful runs exit 0 and print a non-empty CBOR hex string.
- With the global `--json` flag, stdout is a JSON object of shape
  `{"tx":"<cbor-hex>"}`.
- The command never signs or submits a transaction.

## Scope Notes

The parent brief narrows this ticket to the current CLI skeleton and offline
provider flags. It does not authorize changes to `exe/Main.hs`, the provider
typeclass, `src/`, `flake.nix`, or sibling command modules.

## Success Criteria

- `nix build .#cip113-cli --no-link` succeeds.
- `nix develop --quiet -c fourmolu -m check exe` succeeds.
- `nix develop --quiet -c hlint exe` succeeds.
- `./gate.sh` succeeds, including the register smoke command.
