#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Minimal Repro: Full Test Run ==="
echo ""

if [ ! -x "$SCRIPT_DIR/setup.sh" ]; then
  echo "setup.sh not found or not executable."
  exit 1
fi

if [ ! -x "$SCRIPT_DIR/install.sh" ]; then
  echo "install.sh not found or not executable."
  exit 1
fi

if [ ! -x "$SCRIPT_DIR/apply.sh" ]; then
  echo "apply.sh not found or not executable."
  exit 1
fi

if [ ! -x "$SCRIPT_DIR/check.sh" ]; then
  echo "check.sh not found or not executable."
  exit 1
fi

if [ ! -x "$SCRIPT_DIR/patch.sh" ]; then
  echo "patch.sh not found or not executable."
  exit 1
fi

if [ ! -x "$SCRIPT_DIR/build.sh" ]; then
  echo "build.sh not found or not executable."
  exit 1
fi

if [ ! -x "$SCRIPT_DIR/provider-source.sh" ]; then
  echo "provider-source.sh not found or not executable."
  exit 1
fi

if [ -z "${PROVIDER_DIR:-}" ] && [ -z "${PROVIDER_REPO:-}" ] && [ -t 0 ]; then
  . "$SCRIPT_DIR/provider-source.sh"
fi

build_pid=""
echo ">> Build provider in background"
"$SCRIPT_DIR/build.sh" &
build_pid=$!

echo ">> Setup cluster"
"$SCRIPT_DIR/setup.sh"

echo ""
echo ">> Install Crossplane and provider-kubernetes"
"$SCRIPT_DIR/install.sh"

echo ""
echo ">> Apply manifests"
"$SCRIPT_DIR/apply.sh"

echo ""
echo ">> Check (before fix)"
"$SCRIPT_DIR/check.sh"

echo ""
echo ">> Patch provider-kubernetes"
if [ -n "$build_pid" ]; then
  wait "$build_pid"
fi
SKIP_BUILD=1 "$SCRIPT_DIR/patch.sh"

echo ""
echo ">> Check (after fix)"
"$SCRIPT_DIR/check.sh"

echo ""
echo "=== Full test complete ==="
