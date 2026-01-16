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
"$SCRIPT_DIR/patch.sh"

echo ""
echo ">> Check (after fix)"
"$SCRIPT_DIR/check.sh"

echo ""
echo "=== Full test complete ==="
