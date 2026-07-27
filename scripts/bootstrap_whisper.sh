#!/bin/bash
# Clones and builds the vendored whisper.cpp static libs the Swift package links
# against. Used by a fresh local checkout and by CI, so both build the same commit.
set -euo pipefail

# Pinned so a whisper.cpp change never silently alters a release.
WHISPER_REF="080bbbe85230f624f0b52127f1ae1218247989f9"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VENDOR="vendor/whisper.cpp"

if [[ -f "$VENDOR/build/src/libwhisper.a" ]]; then
  echo "==> whisper.cpp already built"
  exit 0
fi

if [[ ! -d "$VENDOR/.git" ]]; then
  echo "==> Cloning whisper.cpp @ $WHISPER_REF"
  rm -rf "$VENDOR"
  mkdir -p "$VENDOR"
  git -C "$VENDOR" init -q
  git -C "$VENDOR" remote add origin https://github.com/ggml-org/whisper.cpp
fi

git -C "$VENDOR" fetch -q --depth 1 origin "$WHISPER_REF"
git -C "$VENDOR" checkout -q FETCH_HEAD

echo "==> Building whisper.cpp (Metal, static)"
cmake -S "$VENDOR" -B "$VENDOR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF >/dev/null
cmake --build "$VENDOR/build" -j"$(sysctl -n hw.ncpu)" --target whisper >/dev/null

echo "==> Done: $VENDOR/build"
