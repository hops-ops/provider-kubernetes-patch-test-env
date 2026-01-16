#!/bin/bash
set -e

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-minimal-repro}"
KIND_CONTEXT="kind-${KIND_CLUSTER_NAME}"

if ! command -v kind >/dev/null 2>&1; then
  echo "kind is required but not found in PATH."
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH."
  exit 1
fi

if kind get clusters | rg -q "^${KIND_CLUSTER_NAME}\$"; then
  echo "kind cluster '${KIND_CLUSTER_NAME}' already exists."
else
  echo "Creating kind cluster '${KIND_CLUSTER_NAME}'..."
  kind create cluster --name "${KIND_CLUSTER_NAME}" --wait 5m
fi

echo "Switching kubectl context to ${KIND_CONTEXT}..."
kubectl config use-context "${KIND_CONTEXT}"

echo ""
echo "=== Cluster ready ==="
echo "Next: run ./install.sh to install Crossplane and provider-kubernetes"
