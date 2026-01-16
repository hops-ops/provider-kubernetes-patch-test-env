#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH."
  exit 1
fi

ASDF_GO="$(asdf which go 2>/dev/null || true)"
if [ -n "$ASDF_GO" ]; then
  export PATH="$(dirname "$ASDF_GO"):$PATH"
fi

export GOCACHE="${GOCACHE:-/tmp/go-build}"
export GOMODCACHE="${GOMODCACHE:-/tmp/go-mod}"
mkdir -p "$GOCACHE" "$GOMODCACHE"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found in PATH."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not found in PATH."
  exit 1
fi

if [ ! -x "$SCRIPT_DIR/provider-source.sh" ]; then
  echo "provider-source.sh not found or not executable."
  exit 1
fi

"$SCRIPT_DIR/provider-source.sh"


PROVIDER_NAME="$(kubectl get providers.pkg.crossplane.io -o json | jq -r '
  [.items[] | select(.spec.package | test("provider-kubernetes"))]
  | map(select(.spec.package | test("xpkg.crossplane.internal/dev") | not))
  | (if length > 0 then .[0].metadata.name else empty end)
')"

if [ -z "$PROVIDER_NAME" ]; then
  echo "Could not find an installed provider-kubernetes Provider."
  echo "Ensure provider-kubernetes is installed before running patch.sh."
  exit 1
fi

RUNTIME_CONFIG_NAME="$(kubectl get provider.pkg.crossplane.io "${PROVIDER_NAME}" -o jsonpath='{.spec.runtimeConfigRef.name}')"
if [ -z "$RUNTIME_CONFIG_NAME" ]; then
  echo "Provider ${PROVIDER_NAME} does not reference a DeploymentRuntimeConfig."
  exit 1
fi

echo "=== Building provider-kubernetes fix ==="
if [ "${SKIP_BUILD:-}" != "1" ]; then
  make -C "$PROVIDER_DIR" build
  make -C "$PROVIDER_DIR" xpkg.build.provider-kubernetes
else
  echo "SKIP_BUILD=1 set; using existing build artifacts."
fi

echo "=== Syncing local xpkg cache into Crossplane ==="
make -C "$PROVIDER_DIR" local.xpkg.sync

XPKG_FILE="$(ls "$PROVIDER_DIR"/_output/xpkg/linux_amd64/provider-kubernetes-*.xpkg | head -n1)"
if [ -z "$XPKG_FILE" ]; then
  echo "Could not locate built xpkg in $PROVIDER_DIR/_output/xpkg/linux_amd64"
  exit 1
fi

XPKG_VERSION="$(basename "$XPKG_FILE" | sed 's/^provider-kubernetes-//' | sed 's/\.xpkg$//')"
DEV_PKG="xpkg.crossplane.internal/dev/provider-kubernetes:${XPKG_VERSION}.gz"

echo "=== Patching Provider '${PROVIDER_NAME}' to use ${DEV_PKG} ==="
kubectl patch provider.pkg.crossplane.io "${PROVIDER_NAME}" --type merge -p \
  "{\"spec\":{\"package\":\"${DEV_PKG}\",\"packagePullPolicy\":\"Never\"}}"

IMAGE_REPO="$(docker images --format '{{.Repository}}:{{.Tag}}' | rg 'provider-kubernetes-amd64' | head -n1)"
if [ -z "$IMAGE_REPO" ]; then
  echo "Could not find a local provider-kubernetes-amd64 image."
  echo "Ensure the image was built successfully before patching."
  exit 1
fi

CTX="$(kubectl config current-context 2>/dev/null || true)"
if [[ "$CTX" == kind-* ]]; then
  if ! command -v kind >/dev/null 2>&1; then
    echo "kind is required but not found in PATH."
    exit 1
  fi
  KIND_CLUSTER_NAME="${CTX#kind-}"
  echo "=== Loading image into kind cluster: ${KIND_CLUSTER_NAME} ==="
  kind load docker-image "${IMAGE_REPO}" --name "${KIND_CLUSTER_NAME}"
fi

echo "=== Patching DeploymentRuntimeConfig '${RUNTIME_CONFIG_NAME}' to use ${IMAGE_REPO} ==="
kubectl patch deploymentruntimeconfig.pkg.crossplane.io "${RUNTIME_CONFIG_NAME}" --type merge -p \
  "{\"spec\":{\"deploymentTemplate\":{\"spec\":{\"selector\":{},\"strategy\":{},\"template\":{\"spec\":{\"containers\":[{\"name\":\"package-runtime\",\"image\":\"${IMAGE_REPO}\",\"args\":[\"--debug\"]}]}}}}}}"

echo "Waiting for provider to be healthy..."
kubectl wait provider.pkg "${PROVIDER_NAME}" --for=condition=Healthy --timeout=5m

echo ""
echo "=== Patch applied ==="
echo "Run ./check.sh to verify readiness."
