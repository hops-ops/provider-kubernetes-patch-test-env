#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found in PATH."
  exit 1
fi

echo "=== Resetting provider-kubernetes repro state (keeping Crossplane) ==="

if [ -x "$SCRIPT_DIR/cleanup.sh" ]; then
  "$SCRIPT_DIR/cleanup.sh" || true
fi

providers="$(kubectl get providers.pkg.crossplane.io -o json | jq -r '.items[] | select(.spec.package | test("provider-kubernetes")) | .metadata.name' || true)"
if [ -z "$providers" ]; then
  echo "No provider-kubernetes Providers found."
  exit 0
fi

runtimeconfigs=""
for p in $providers; do
  rc="$(kubectl get provider.pkg.crossplane.io "$p" -o jsonpath='{.spec.runtimeConfigRef.name}' 2>/dev/null || true)"
  if [ -n "$rc" ]; then
    runtimeconfigs="${runtimeconfigs}"$'\n'"${rc}"
  fi
done
runtimeconfigs="$(printf '%s\n' "$runtimeconfigs" | sed '/^$/d' | sort -u)"

sa_names=""
for rc in $runtimeconfigs; do
  sa="$(kubectl get deploymentruntimeconfig.pkg.crossplane.io "$rc" -o jsonpath='{.spec.serviceAccountTemplate.metadata.name}' 2>/dev/null || true)"
  if [ -n "$sa" ]; then
    sa_names="${sa_names}"$'\n'"${sa}"
  fi
done
sa_names="$(printf '%s\n' "$sa_names" | sed '/^$/d' | sort -u)"

if [ -n "$sa_names" ]; then
  names_json="$(printf '%s\n' $sa_names | jq -R . | jq -s .)"
  crbs="$(kubectl get clusterrolebinding -o json | jq -r --argjson names "$names_json" '.items[] | select(.subjects[]? | .kind=="ServiceAccount" and .namespace=="crossplane-system" and (.name as $n | $names | index($n))) | .metadata.name' | sort -u)"
  if [ -n "$crbs" ]; then
    echo "Deleting ClusterRoleBindings for provider-kubernetes service accounts..."
    for crb in $crbs; do
      kubectl delete clusterrolebinding "$crb" --ignore-not-found
    done
  fi
fi

echo "Deleting provider-kubernetes Providers..."
for p in $providers; do
  kubectl delete provider.pkg.crossplane.io "$p" --ignore-not-found
done

for p in $providers; do
  kubectl delete providerrevisions.pkg.crossplane.io -l "pkg.crossplane.io/package=${p}" --ignore-not-found
done

if [ -n "$runtimeconfigs" ]; then
  echo "Deleting DeploymentRuntimeConfigs..."
  for rc in $runtimeconfigs; do
    kubectl delete deploymentruntimeconfig.pkg.crossplane.io "$rc" --ignore-not-found
  done
fi

echo ""
echo "=== Reset complete (Crossplane left intact) ==="
