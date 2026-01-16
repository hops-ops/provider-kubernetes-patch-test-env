#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CROSSPLANE_VERSION="${CROSSPLANE_VERSION:-2.1.3}"
PROVIDER_K8S_VERSION="${PROVIDER_K8S_VERSION:-v1.2.0}"
PROVIDER_K8S_PACKAGE="${PROVIDER_K8S_PACKAGE:-xpkg.crossplane.io/crossplane-contrib/provider-kubernetes:${PROVIDER_K8S_VERSION}}"
PROVIDER_NAME="${PROVIDER_NAME:-crossplane-contrib-provider-kubernetes}"
RUNTIME_CONFIG_NAME="${RUNTIME_CONFIG_NAME:-runtimeconfig-${PROVIDER_NAME}}"
CLUSTERROLEBINDING_NAME="${CLUSTERROLEBINDING_NAME:-${PROVIDER_NAME}-cluster-admin}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH."
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required but not found in PATH."
  exit 1
fi

echo "=== Installing/Upgrading Crossplane (${CROSSPLANE_VERSION}) ==="
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace \
  --version "${CROSSPLANE_VERSION}"

echo "Waiting for Crossplane to be available..."
kubectl -n crossplane-system wait deployment crossplane --for=condition=Available --timeout=5m
kubectl -n crossplane-system wait deployment crossplane-rbac-manager --for=condition=Available --timeout=5m || true

echo "=== Installing/Upgrading provider-kubernetes (${PROVIDER_K8S_PACKAGE}) ==="
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: ${PROVIDER_NAME}
  namespace: crossplane-system
spec:
  package: ${PROVIDER_K8S_PACKAGE}
  packagePullPolicy: IfNotPresent
  runtimeConfigRef:
    apiVersion: pkg.crossplane.io/v1beta1
    kind: DeploymentRuntimeConfig
    name: ${RUNTIME_CONFIG_NAME}
---
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: ${RUNTIME_CONFIG_NAME}
spec:
  serviceAccountTemplate:
    metadata:
      name: ${PROVIDER_NAME}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${CLUSTERROLEBINDING_NAME}
subjects:
- kind: ServiceAccount
  name: ${PROVIDER_NAME}
  namespace: crossplane-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo "Waiting for provider-kubernetes to be healthy..."
kubectl wait provider.pkg "${PROVIDER_NAME}" --for=condition=Healthy --timeout=5m

provider_deployments="$(kubectl -n crossplane-system get deployment -l pkg.crossplane.io/provider="${PROVIDER_NAME}" -o name 2>/dev/null || true)"
if [ -n "$provider_deployments" ]; then
  kubectl -n crossplane-system wait deployment -l pkg.crossplane.io/provider="${PROVIDER_NAME}" --for=condition=Available --timeout=5m
else
  echo "No provider deployment with label pkg.crossplane.io/provider=${PROVIDER_NAME} found; skipping deployment wait."
fi

echo ""
echo "=== Setup complete ==="
echo "Next: run ./apply.sh, then ./check.sh"
