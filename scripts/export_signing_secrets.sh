#!/bin/bash
# Pushes the local self-signed code-signing identity to GitHub Actions secrets, so
# CI-built releases carry the SAME code identity as local builds. Without this the
# runner signs ad-hoc, the identity changes on every release, and macOS re-asks each
# user for Microphone and Accessibility after every update.
#
# Run scripts/setup_signing.sh first. Asks for the keychain password (macOS prompt).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CN="AlejoVoice Self Signed"
VAULT="$HOME/Library/Application Support/AlejoVoice/signing"

if ! command -v gh >/dev/null 2>&1; then
  echo "Falta el CLI de GitHub: brew install gh && gh auth login"
  exit 1
fi
if [[ ! -f "$VAULT/identity.p12" ]]; then
  echo "No encuentro $VAULT/identity.p12."
  echo "Corre primero: ./scripts/setup_signing.sh (guarda ahí la identidad '$CN')."
  exit 1
fi

echo "==> Subiendo secrets a GitHub"
base64 -i "$VAULT/identity.p12" | gh secret set MACOS_CERT_P12
gh secret set MACOS_CERT_PASSWORD < "$VAULT/identity.pass"

echo "==> Listo. El próximo release de CI irá firmado con '$CN'."
echo "    Comprobar: gh secret list"
