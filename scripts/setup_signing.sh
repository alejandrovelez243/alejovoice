#!/bin/bash
# One-time setup: creates a self-signed code-signing identity in the login keychain.
#
# Why: an ad-hoc signature (`codesign -s -`) changes on every build, so macOS treats
# each rebuild as a different program and asks for Microphone/Accessibility again.
# A fixed identity keeps the code identity stable, and the permissions stick.
#
# macOS will ask for your login password to trust the certificate.
set -euo pipefail

CN="AlejoVoice Self Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# The exported identity is kept here so scripts/export_signing_secrets.sh can hand the
# very same cert to GitHub Actions — `security export` cannot pick one identity by name.
VAULT="$HOME/Library/Application Support/AlejoVoice/signing"

if security find-identity -v -p codesigning | grep -q "$CN"; then
  echo "==> Identity '$CN' already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P12_PASSWORD="$(uuidgen)"

echo "==> Generating certificate"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$CN" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout pass:"$P12_PASSWORD" >/dev/null 2>&1

echo "==> Importing into the login keychain"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -A >/dev/null

echo "==> Trusting it for code signing (password prompt incoming)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "==> Stashing the identity for CI use in $VAULT"
mkdir -p "$VAULT"
cp "$TMP/identity.p12" "$VAULT/identity.p12"
printf '%s' "$P12_PASSWORD" > "$VAULT/identity.pass"
chmod 700 "$VAULT"
chmod 600 "$VAULT/identity.p12" "$VAULT/identity.pass"

echo "==> Done. scripts/build_app.sh will now sign with '$CN'."
echo "    First run after switching identities still asks for Microphone and"
echo "    Accessibility once — after that, updates keep the grants."
