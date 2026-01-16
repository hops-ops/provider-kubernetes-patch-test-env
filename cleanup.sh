#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Cleaning up test resources ==="
echo ""

# Delete the Objects first (which should clean up the managed resources)
echo "Deleting Object resources..."
kubectl delete -f "$SCRIPT_DIR/manifests/object.yaml" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/manifests/object-configmap.yaml" --ignore-not-found

# Also delete the managed resources directly in case they weren't cleaned up
echo "Deleting test ProviderConfig (if exists)..."
kubectl delete providerconfig.kubernetes.m.crossplane.io test-providerconfig -n default --ignore-not-found

echo "Deleting test ConfigMap (if exists)..."
kubectl delete configmap test-configmap -n default --ignore-not-found

# Delete the default ProviderConfig
echo "Deleting default ProviderConfig..."
kubectl delete -f "$SCRIPT_DIR/manifests/default-providerconfig.yaml" --ignore-not-found

echo ""
echo "=== Cleanup complete ==="
