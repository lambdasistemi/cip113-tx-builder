# Feature Specification: Vault Seal and Sign CLI

## P1 User Story

As an operator, I can encrypt a plaintext payment signing key with
`cip113 vault seal --signing-key payment.skey --out payment.vault.age`, then
pipe an unsigned CIP-113 transaction CBOR hex into `cip113 sign` using either a
plaintext key or the encrypted vault and receive witnessed transaction CBOR hex
on stdout.

## Functional Requirements

- `cardano-wallet-tools` is available to the executable via a pinned
  `source-repository-package` and an executable-only build dependency.
- `cip113 vault seal --signing-key FILE --out FILE` reads the plaintext
  cardano-cli TextEnvelope key, prompts for a vault passphrase twice on
  `/dev/tty`, rejects mismatched passphrases, and writes an age-encrypted vault.
- `cip113 sign --signing-key FILE` accepts a plaintext TextEnvelope payment
  signing key using `Cardano.Wallet.Tools.Cli.Vault.signingKeySourceParser`.
- `cip113 sign --signing-key-vault FILE [--passphrase-file FILE]` decrypts the
  vault using the upstream parser and key-loading helpers.
- `cip113 sign` reads CBOR hex from stdin, signs the transaction body, attaches a
  vkey witness, and writes witnessed CBOR hex to stdout without extra text.
- Key parsing, vault encryption/decryption, signing, and witness attachment are
  delegated to `cardano-wallet-tools`; this repo only wires the CLI.

## Success Criteria

- `cip113-tx-builder.cabal` lists `cardano-wallet-tools` only in the
  `cip113-cli` executable dependencies and exposes any new executable modules.
- `cabal.project` pins `lambdasistemi/cardano-wallet-tools` at
  `cf70a316573d8e2b97134a856e2f9e9869925efb`.
- Local gate passes: `./gate.sh`.
- Manual CLI smoke can seal a key and sign a CBOR hex transaction via plaintext
  and vault-backed key paths.
