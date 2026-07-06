# CIP-113 CLI tutorial

This walkthrough follows one CIP-113 token through the `cip113-cli` lifecycle:
seal a signing-key vault, register the policy, transfer a token, freeze the
holder, seize the frozen token, and sign each transaction before submission.
The real transaction builders currently require a local Cardano node. Instead of
repeating the deployment descriptor, node socket, network magic, and change
address on every build command, collect them once in a YAML config file and
point `CIP113_CONFIG_FILE` at it; the CLI then reads those shared settings for
every command that follows.

The examples use placeholders for devnet values. Replace them with values from
your own Conway devnet deployment.

<!-- tutorial-command: environment -->

```bash
export CIP113_CLI=./result/bin/cip113-cli
export CIP113_CONFIG_FILE=cip113-cli.config.yaml
export SOCKET_PATH=/path/to/node.socket
export NETWORK_MAGIC=42
export PAYMENT_SKEY=payment.skey
export PAYMENT_VAULT=payment.vault.age
export PASSPHRASE_FILE=vault.passphrase
export POLICY_ID=<56-char-policy-id>
export TOKEN_NAME=<token-name>
export HOLDER_ADDRESS=<current-smart-wallet-address>
export RECIPIENT_ADDRESS=<recipient-smart-wallet-address>
export SEIZED_ADDRESS=<seized-token-recipient-address>
cat > "$CIP113_CONFIG_FILE" <<YAML
deployment: deployment.json
socket-path: $SOCKET_PATH
network-magic: $NETWORK_MAGIC
change-address: <hex-serialized-change-address>
YAML
```

The config file carries `deployment`, `socket-path`, `network-magic`, and
`change-address`, so the register, transfer, freeze, and seize commands below no
longer pass those flags. `SOCKET_PATH` and `NETWORK_MAGIC` stay exported because
the `cardano-cli` submission step still needs them.

Start by sealing the plaintext `cardano-cli` signing key into an
age-encrypted vault. `vault seal` reads the plaintext key, writes the encrypted
vault, and prompts for the vault passphrase on `/dev/tty`.

<!-- tutorial-command: vault-seal -->

```bash
"$CIP113_CLI" vault seal \
  --signing-key "$PAYMENT_SKEY" \
  --out "$PAYMENT_VAULT"
```

The first chain registers the policy and signs with the vault. The `register`
command reads the deployment, node connection, and change address from the
config file, writes an unsigned transaction body as CBOR hex to stdout, and
`sign` reads that CBOR hex from stdin and writes witnessed CBOR hex to stdout.
Decode the signed CBOR hex to a transaction file before submitting it with your
local node tooling.

<!-- tutorial-command: register-vault-sign -->

```bash
"$CIP113_CLI" register \
  --token-name "$TOKEN_NAME" \
  --policy-id "$POLICY_ID" \
  | "$CIP113_CLI" sign \
      --signing-key-vault "$PAYMENT_VAULT" \
      --passphrase-file "$PASSPHRASE_FILE" \
  > register.signed.cborhex
xxd -r -p register.signed.cborhex > register.signed.cbor
CARDANO_NODE_SOCKET_PATH="$SOCKET_PATH" cardano-cli transaction submit \
  --testnet-magic "$NETWORK_MAGIC" \
  --tx-file register.signed.cbor
```

After the register transaction is accepted, build a transfer from the current
smart wallet address to the recipient. This time the walkthrough uses the
plaintext key path to show the other supported key source. The build side of
the pipe only carries the transfer-specific flags; the shared real-build
settings still come from the config file.

<!-- tutorial-command: transfer-plaintext-sign -->

```bash
"$CIP113_CLI" transfer \
  --from-address "$HOLDER_ADDRESS" \
  --to-address "$RECIPIENT_ADDRESS" \
  --token-name "$TOKEN_NAME" \
  --policy-id "$POLICY_ID" \
  --amount 1 \
  | "$CIP113_CLI" sign \
      --signing-key "$PAYMENT_SKEY" \
  > transfer.signed.cborhex
xxd -r -p transfer.signed.cborhex > transfer.signed.cbor
CARDANO_NODE_SOCKET_PATH="$SOCKET_PATH" cardano-cli transaction submit \
  --testnet-magic "$NETWORK_MAGIC" \
  --tx-file transfer.signed.cbor
```

Next, freeze the token holder. A freeze locks the target's programmable token
at an always-fail address, so the target address is the smart wallet that
currently holds the token after the transfer. The signing step can use either
key source; this example keeps using the plaintext key.

<!-- tutorial-command: freeze-plaintext-sign -->

```bash
"$CIP113_CLI" freeze \
  --target-address "$RECIPIENT_ADDRESS" \
  --token-name "$TOKEN_NAME" \
  --policy-id "$POLICY_ID" \
  | "$CIP113_CLI" sign \
      --signing-key "$PAYMENT_SKEY" \
  > freeze.signed.cborhex
xxd -r -p freeze.signed.cborhex > freeze.signed.cbor
CARDANO_NODE_SOCKET_PATH="$SOCKET_PATH" cardano-cli transaction submit \
  --testnet-magic "$NETWORK_MAGIC" \
  --tx-file freeze.signed.cbor
```

Finally, seize the frozen token and send it to the recovery recipient. The
`seize` build reads the same shared settings from the config file and adds both
the frozen target address and the destination address. Once the signed
transaction is submitted, the full lifecycle has been exercised.

<!-- tutorial-command: seize-final-sign -->

```bash
"$CIP113_CLI" seize \
  --target-address "$RECIPIENT_ADDRESS" \
  --to-address "$SEIZED_ADDRESS" \
  --token-name "$TOKEN_NAME" \
  --policy-id "$POLICY_ID" \
  | "$CIP113_CLI" sign \
      --signing-key "$PAYMENT_SKEY" \
  > seize.signed.cborhex
xxd -r -p seize.signed.cborhex > seize.signed.cbor
CARDANO_NODE_SOCKET_PATH="$SOCKET_PATH" cardano-cli transaction submit \
  --testnet-magic "$NETWORK_MAGIC" \
  --tx-file seize.signed.cbor
```

The live E2E tutorial scenario backs this command sequence against a local
Conway devnet and is designed to catch drift between these command blocks and
the commands exercised by the test. The test writes the same config file and
runs each command with `CIP113_CONFIG_FILE` set, proving the shared settings can
come from config instead of per-command flags. The CLI itself still only builds
and signs; submission remains the responsibility of the surrounding node
tooling.
