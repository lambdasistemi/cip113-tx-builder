# CLI usage

The `cip113-cli` binary builds unsigned CIP-113 transaction bodies and can also
sign them. Every subcommand prints a human-readable summary by default; pass
the global `--json` flag for machine-readable output instead.

```bash
nix build .#cip113-cli
./result/bin/cip113-cli --help
```

Exit codes: `0` success, `1` user error, `2` internal/unimplemented error.

## Settings: flags, environment variables, and config keys

Every build setting can be supplied three interchangeable ways, resolved in
priority order:

1. a command-line flag,
2. a `CIP113_*` environment variable,
3. a key in a YAML configuration file.

The configuration file is selected by `--config-file FILE` or the
`CIP113_CONFIG_FILE` environment variable; with neither set, the default XDG
path `~/.config/cip113-cli/config.yaml` is used when it exists.

```bash
cip113-cli --config-file ./cip113-cli.config.yaml register ...
CIP113_CONFIG_FILE=./cip113-cli.config.yaml cip113-cli register ...
```

Collecting the shared real-build settings in a config file lets the register,
transfer, freeze, and seize commands run without repeating `--deployment`,
`--socket-path`, `--network-magic`, and `--change-address` on every
invocation:

```yaml
deployment: deployment.json
socket-path: /path/to/node.socket
network-magic: 42
change-address: <hex-serialized-address>
```

## Real transaction building

`register`, `transfer`, `freeze`, and `seize` build real transactions only
against a local Cardano node. Each command queries live registry UTxOs,
balances the unsigned transaction, and returns change, so it needs a deployment
descriptor, a node connection, and a funding/change address. There is no
offline-JSON, Blockfrost, or Kupo real-build path.

### Shared real-build settings

These four settings are common to all four commands and are the ones best moved
into a config file or environment.

| Setting | Flag | Environment variable | Config key |
|---|---|---|---|
| Deployment descriptor JSON | `--deployment FILE` | `CIP113_DEPLOYMENT` | `deployment` |
| Node socket path | `--socket-path PATH` | `CIP113_SOCKET_PATH` | `socket-path` |
| Network magic | `--network-magic INT` | `CIP113_NETWORK_MAGIC` | `network-magic` |
| Funding and change address | `--change-address ADDR` | `CIP113_CHANGE_ADDRESS` | `change-address` |

## register

Register a CIP-113 policy. In addition to the shared real-build settings,
`register` takes:

| Setting | Flag | Environment variable | Config key |
|---|---|---|---|
| Token name | `--token-name NAME` | `CIP113_TOKEN_NAME` | `token-name` |
| Policy id (56-char hex) | `--policy-id HEX` | `CIP113_POLICY_ID` | `policy-id` |

With the shared settings provided through `CIP113_CONFIG_FILE`, register reduces
to its command-specific flags:

```bash
CIP113_CONFIG_FILE=cip113-cli.config.yaml \
  cip113-cli register \
  --token-name <name> \
  --policy-id <56-char-hex>
```

## transfer

Move CIP-113 tokens between smart wallet addresses. In addition to the shared
real-build settings, `transfer` takes:

| Setting | Flag | Environment variable | Config key |
|---|---|---|---|
| Sender address | `--from-address ADDR` | `CIP113_FROM_ADDRESS` | `from-address` |
| Recipient address | `--to-address ADDR` | `CIP113_TO_ADDRESS` | `to-address` |
| Token name | `--token-name NAME` | `CIP113_TOKEN_NAME` | `token-name` |
| Policy id (56-char hex) | `--policy-id HEX` | `CIP113_POLICY_ID` | `policy-id` |
| Positive token amount | `--amount INT` | `CIP113_AMOUNT` | `amount` |

```bash
CIP113_CONFIG_FILE=cip113-cli.config.yaml \
  cip113-cli transfer \
  --from-address <addr> \
  --to-address <addr> \
  --token-name <name> \
  --policy-id <56-char-hex> \
  --amount <positive-int>
```

## freeze

Lock tokens at an always-fail address (third-party freeze). In addition to the
shared real-build settings, `freeze` takes:

| Setting | Flag | Environment variable | Config key |
|---|---|---|---|
| Target address | `--target-address ADDR` | `CIP113_TARGET_ADDRESS` | `target-address` |
| Token name | `--token-name NAME` | `CIP113_TOKEN_NAME` | `token-name` |
| Policy id (56-char hex) | `--policy-id HEX` | `CIP113_POLICY_ID` | `policy-id` |

```bash
CIP113_CONFIG_FILE=cip113-cli.config.yaml \
  cip113-cli freeze \
  --target-address <addr> \
  --token-name <name> \
  --policy-id <56-char-hex>
```

## seize

Redirect frozen tokens to a new owner (third-party seize). In addition to the
shared real-build settings, `seize` takes:

| Setting | Flag | Environment variable | Config key |
|---|---|---|---|
| Target address | `--target-address ADDR` | `CIP113_TARGET_ADDRESS` | `target-address` |
| Destination address | `--to-address ADDR` | `CIP113_TO_ADDRESS` | `to-address` |
| Token name | `--token-name NAME` | `CIP113_TOKEN_NAME` | `token-name` |
| Policy id (56-char hex) | `--policy-id HEX` | `CIP113_POLICY_ID` | `policy-id` |

```bash
CIP113_CONFIG_FILE=cip113-cli.config.yaml \
  cip113-cli seize \
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
CIP113_CONFIG_FILE=cip113-cli.config.yaml \
  cip113-cli register --token-name ... --policy-id ... \
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

`sign` never generates keys and never manages the node connection above — it
delegates all key handling to `cardano-wallet-tools`.
