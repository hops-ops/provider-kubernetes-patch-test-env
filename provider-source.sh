#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PROVIDER_DIR="${PROVIDER_DIR:-}"
PROVIDER_REPO="${PROVIDER_REPO:-}"
PROVIDER_REF="${PROVIDER_REF:-}"
PROVIDER_CLONE_DIR="${PROVIDER_CLONE_DIR:-/tmp/minimal-repro-provider-kubernetes}"

if [ -z "$PROVIDER_DIR" ] && [ -z "$PROVIDER_REPO" ]; then
  if [ ! -t 0 ]; then
    echo "Set PROVIDER_DIR or PROVIDER_REPO/PROVIDER_REF before running."
    exit 1
  fi
  echo "Select provider source:"
  echo "  1) Local directory"
  echo "  2) Git repo/branch"
  read -r -p "Choice [1/2]: " choice
  case "$choice" in
    1|local|l)
      read -r -p "Local path: " PROVIDER_DIR
      ;;
    2|repo|r)
      read -r -p "Repo URL: " PROVIDER_REPO
      read -r -p "Branch/tag/SHA (optional): " PROVIDER_REF
      ;;
    *)
      echo "Invalid choice."
      exit 1
      ;;
  esac
fi

if [ -n "$PROVIDER_REPO" ]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "git is required but not found in PATH."
    exit 1
  fi
  if [ -d "$PROVIDER_CLONE_DIR/.git" ]; then
    echo "Updating provider repo in $PROVIDER_CLONE_DIR..."
    git -C "$PROVIDER_CLONE_DIR" fetch --all --tags
  else
    echo "Cloning provider repo to $PROVIDER_CLONE_DIR..."
    rm -rf "$PROVIDER_CLONE_DIR"
    git clone "$PROVIDER_REPO" "$PROVIDER_CLONE_DIR"
  fi
  if [ -n "$PROVIDER_REF" ]; then
    git -C "$PROVIDER_CLONE_DIR" checkout "$PROVIDER_REF"
  fi
  PROVIDER_DIR="$PROVIDER_CLONE_DIR"
fi

if [ -z "$PROVIDER_DIR" ] || [ ! -d "$PROVIDER_DIR" ]; then
  echo "Missing provider repo at ${PROVIDER_DIR:-<unset>}"
  exit 1
fi

if [ ! -d "$PROVIDER_DIR/build/makelib" ]; then
  echo "Initializing build submodule..."
  (cd "$PROVIDER_DIR" && git submodule update --init --recursive)
fi

export PROVIDER_DIR
