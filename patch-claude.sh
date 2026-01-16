#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVIDER_DIR="$SCRIPT_DIR/../provider-kubernetes"
IMAGE_NAME="provider-kubernetes-patched"
IMAGE_TAG="claude-fix"
FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"

echo "=============================================="
echo "=== Building and Deploying Patched Provider ==="
echo "=============================================="

# Detect architecture
GOOS=$(go env GOOS)
GOARCH=$(go env GOARCH)
echo ""
echo "Building for: ${GOOS}/${GOARCH}"

# Step 1: Initialize git submodules if needed
echo ""
echo "=== Step 1: Checking git submodules ==="
cd "$PROVIDER_DIR"
if [ ! -f "build/makelib/common.mk" ]; then
    echo "Initializing git submodules..."
    git submodule update --init --recursive
else
    echo "Submodules already initialized"
fi

# Step 2: Build the Go binary
echo ""
echo "=== Step 2: Building Go binary ==="
cd "$PROVIDER_DIR"

# Create output directory
mkdir -p "bin/${GOOS}_${GOARCH}"

# Build the provider binary
echo "Compiling provider..."
CGO_ENABLED=0 GOOS=${GOOS} GOARCH=${GOARCH} go build \
    -ldflags "-X github.com/crossplane-contrib/provider-kubernetes/internal/version.Version=claude-patched" \
    -o "bin/${GOOS}_${GOARCH}/provider" \
    ./cmd/provider

echo "Binary built: bin/${GOOS}_${GOARCH}/provider"

# Step 3: Build Docker image
echo ""
echo "=== Step 3: Building Docker image ==="
cd "$PROVIDER_DIR"

# For kind on Mac, we need linux binaries
if [ "$GOOS" != "linux" ]; then
    echo "Cross-compiling for linux/${GOARCH}..."
    mkdir -p "bin/linux_${GOARCH}"
    CGO_ENABLED=0 GOOS=linux GOARCH=${GOARCH} go build \
        -ldflags "-X github.com/crossplane-contrib/provider-kubernetes/internal/version.Version=claude-patched" \
        -o "bin/linux_${GOARCH}/provider" \
        ./cmd/provider
fi

docker build \
    --build-arg TARGETOS=linux \
    --build-arg TARGETARCH=${GOARCH} \
    -t "$FULL_IMAGE" \
    -f cluster/images/provider-kubernetes/Dockerfile \
    .

echo "Docker image built: $FULL_IMAGE"

# Step 4: Load image into kind cluster
echo ""
echo "=== Step 4: Loading image into kind cluster ==="

# Get the kind cluster name from current context
CONTEXT=$(kubectl config current-context)
if [[ "$CONTEXT" == kind-* ]]; then
    CLUSTER_NAME="${CONTEXT#kind-}"
    echo "Loading into kind cluster: $CLUSTER_NAME"
    kind load docker-image "$FULL_IMAGE" --name "$CLUSTER_NAME"
else
    echo "WARNING: Current context ($CONTEXT) doesn't appear to be a kind cluster."
    echo "Attempting to load anyway..."
    # Try to find a kind cluster
    KIND_CLUSTERS=$(kind get clusters 2>/dev/null || echo "")
    if [ -n "$KIND_CLUSTERS" ]; then
        CLUSTER_NAME=$(echo "$KIND_CLUSTERS" | head -1)
        echo "Found kind cluster: $CLUSTER_NAME"
        kind load docker-image "$FULL_IMAGE" --name "$CLUSTER_NAME"
    else
        echo "ERROR: No kind cluster found. Please load the image manually:"
        echo "  kind load docker-image $FULL_IMAGE --name <cluster-name>"
        exit 1
    fi
fi

# Step 5: Patch the provider deployment
echo ""
echo "=== Step 5: Patching provider deployment ==="

# Find the provider-kubernetes deployment
DEPLOYMENT=$(kubectl get deployment -n crossplane-system -l pkg.crossplane.io/provider=provider-kubernetes -o name 2>/dev/null | head -1)

if [ -z "$DEPLOYMENT" ]; then
    # Try alternative label
    DEPLOYMENT=$(kubectl get deployment -n crossplane-system -o name 2>/dev/null | grep provider-kubernetes | head -1)
fi

if [ -z "$DEPLOYMENT" ]; then
    echo "ERROR: Could not find provider-kubernetes deployment"
    echo "Available deployments in crossplane-system:"
    kubectl get deployment -n crossplane-system
    exit 1
fi

echo "Found deployment: $DEPLOYMENT"

# Patch the deployment to use our image
echo "Patching deployment to use image: $FULL_IMAGE"
kubectl patch "$DEPLOYMENT" -n crossplane-system --type='json' -p="[
  {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/image\", \"value\": \"$FULL_IMAGE\"},
  {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/imagePullPolicy\", \"value\": \"Never\"}
]"

# Wait for rollout
echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status "$DEPLOYMENT" -n crossplane-system --timeout=120s

echo ""
echo "=== Patch Complete ==="
echo ""
echo "The patched provider is now running. Run ./check.sh to verify the fix."
echo ""
echo "To revert to the original provider, you can:"
echo "  1. Delete and recreate the Provider resource, or"
echo "  2. Run: kubectl rollout undo $DEPLOYMENT -n crossplane-system"
