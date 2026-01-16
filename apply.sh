#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Applying test resources ==="
echo ""

# First, apply the default ProviderConfig (needed for provider-kubernetes to work)
echo "Applying default ProviderConfig..."
kubectl apply -f "$SCRIPT_DIR/manifests/default-providerconfig.yaml"

echo "Waiting for default ProviderConfig to be ready..."
sleep 2

# Apply the Object resource (which will create another ProviderConfig)
echo "Applying Object resource (ProviderConfig - demonstrates bug)..."
kubectl apply -f "$SCRIPT_DIR/manifests/object.yaml"

# Apply a contrasting Object resource (which will create a ConfigMap)
echo "Applying Object resource (ConfigMap - works normally)..."
kubectl apply -f "$SCRIPT_DIR/manifests/object-configmap.yaml"

echo ""
echo "=== Resources applied ==="
echo ""
echo "Run ./check.sh to monitor status"
echo "Run ./cleanup.sh to remove test resources"
