#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not found in PATH."
  exit 1
fi

ASDF_GO="$(asdf which go 2>/dev/null || true)"
if [ -n "$ASDF_GO" ]; then
  export PATH="$(dirname "$ASDF_GO"):$PATH"
fi

export GOCACHE="${GOCACHE:-/tmp/go-build}"
export GOMODCACHE="${GOMODCACHE:-/tmp/go-mod}"
mkdir -p "$GOCACHE" "$GOMODCACHE"

if [ ! -x "$SCRIPT_DIR/provider-source.sh" ]; then
  echo "provider-source.sh not found or not executable."
  exit 1
fi

"$SCRIPT_DIR/provider-source.sh"

echo "=== Building provider-kubernetes ==="
make -C "$PROVIDER_DIR" build
make -C "$PROVIDER_DIR" xpkg.build.provider-kubernetes
echo "=== Build complete ==="
