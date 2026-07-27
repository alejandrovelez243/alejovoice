#!/bin/bash
# Publishes a version. Bumps VERSION, commits, tags and pushes — GitHub Actions
# (.github/workflows/release.yml) builds the DMG + update zip on an arm64 runner and
# creates the release. The in-app updater reads that release, so this is the single
# command that ships an update to an installed app.
#
#   scripts/release.sh 1.2.0            build in CI (default)
#   scripts/release.sh 1.2.0 --local    build and upload from this Mac instead
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AlejoVoice"
VERSION="${1:-}"
MODE="${2:-}"

if [[ -z "$VERSION" ]]; then
  echo "uso: scripts/release.sh <version> [--local]   (ej. scripts/release.sh 1.2.0)"
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "La versión debe ser X.Y.Z (el updater compara números)."
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "Falta el CLI de GitHub: brew install gh && gh auth login"
  exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Hay cambios sin commitear. Commitéalos antes de publicar."
  exit 1
fi
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "El tag v$VERSION ya existe."
  exit 1
fi

echo "==> VERSION -> $VERSION"
printf '%s\n' "$VERSION" > VERSION
git add VERSION
# VERSION may already hold this value (first release of a version bumped by hand).
if ! git diff --cached --quiet; then
  git commit -q -m "chore: release v$VERSION"
fi
git tag "v$VERSION"

echo "==> Pushing"
git push -q origin HEAD
git push -q origin "v$VERSION"

if [[ "$MODE" == "--local" ]]; then
  # Local build signs with the machine's identity (see setup_signing.sh), which keeps
  # the app's code identity stable if CI has no cert configured.
  bash scripts/build_app.sh
  gh release create "v$VERSION" \
    "dist/$APP_NAME-$VERSION-arm64.dmg" "dist/$APP_NAME-$VERSION-arm64.zip" \
    --title "$APP_NAME $VERSION" \
    --notes "Instalación nueva: descarga el DMG. Ya instalado: Ajustes → Buscar actualizaciones."
  echo "==> Publicado desde este Mac."
else
  echo "==> GitHub Actions está construyendo el release:"
  gh run list --workflow release.yml --limit 1 || true
  echo "    seguimiento: gh run watch \$(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
fi

echo "==> Cuando el release esté listo: AlejoVoice → Ajustes → Buscar actualizaciones"
