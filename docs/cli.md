# CLI usage

The `cip113-cli` binary builds unsigned CIP-113 transaction bodies and can also
sign them. Every subcommand prints a human-readable summary by default; pass
the global `--json` flag for machine-readable output instead.

```bash
nix build .#cip113-cli
./result/bin/cip113-cli --help
```

Exit codes: `0` success, `1` user error, `2` internal/unimplemented error.

## UTxO sources

`register`, `transfer`, `freeze`, and `seize` read their inputs from one of
four interchangeable sources, selected by which flags are passed:

| Source | Flags |
|---|---|
| Offline JSON | `--utxo-file FILE` (a `cardano-cli query utxo --out-file` document) |
| Local node | `--socket-path PATH --network-magic MAGIC` |
| Blockfrost | `--blockfrost-project-id ID` |
| Kupo | `--kupo-url URL` |

Provider flags can be given once before the subcommand (apply to any
subcommand that follows) or repeated after it — a per-command flag overrides
the global one. With no provider flags at all, the offline backend is used
against stdin/`--utxo-file`.

## register

Register a CIP-113 policy.

```bash
cip113-cli register \
  --utxo-file utxos.json \
  --registry-utxo <txid>#<ix> \
  --token-name <name> \
  --policy-id <56-char-hex>
```

## transfer

Move CIP-113 tokens between smart wallet addresses.

```bash
cip113-cli transfer \
  --utxo-file utxos.json \
  --from-address <addr> \
  --to-address <addr> \
  --token-name <name> \
  --policy-id <56-char-hex> \
  --amount <positive-int>
```

## freeze

Lock tokens at an always-fail address (third-party freeze).

```bash
cip113-cli freeze \
  --utxo-file utxos.json \
  --target-address <addr> \
  --token-name <name> \
  --policy-id <56-char-hex>
```

## seize

Redirect frozen tokens to a new owner (third-party seize).

```bash
cip113-cli seize \
  --utxo-file utxos.json \
  --target-address <addr> \
  --to-address <addr> \
  --token-name <name> \
  --policy-id <56-char-hex>
```

## vault seal

Encrypt a plaintext cardano-cli signing key into an age-encrypted vault, via
`cardano-wallet-tools`. Prompts for the passphrase twice on `/dev/tty`.

```bash
cip113-cli vault seal --signing-key payment.skey --out payment.vault.age
```

## sign

Attach a vkey witness to an unsigned tx body. Reads CBOR hex from stdin,
writes witnessed CBOR hex to stdout — the same pipe contract as `cwt sign`
from `cardano-wallet-tools`, so it composes directly with any of the
transaction-building subcommands above:

```bash
cip113-cli register --utxo-file utxos.json --registry-utxo ... \
  --token-name ... --policy-id ... \
  | cip113-cli sign --signing-key payment.skey \
  > registered.signed.cbor
```

Two key sources are supported:

```bash
# Plaintext cardano-cli TextEnvelope key
cip113-cli sign --signing-key payment.skey

# Age-encrypted vault (from `vault seal` above); prompts for the
# passphrase on /dev/tty unless --passphrase-file is given
cip113-cli sign --signing-key-vault payment.vault.age [--passphrase-file FILE]
```

`sign` never generates keys and never manages the offline/node/indexer
providers above — it delegates all key handling to `cardano-wallet-tools`.
