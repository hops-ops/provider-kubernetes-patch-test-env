#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "=== COMPARISON: ProviderConfig vs ConfigMap ==="
echo "=============================================="

echo ""
echo "=== Object Status (Both) ==="
kubectl get object.kubernetes.m.crossplane.io test-object-providerconfig test-object-configmap -n default -o wide 2>/dev/null || echo "Objects not found"

echo ""
echo "--- ProviderConfig Object (BUG CASE) ---"
echo ""
echo "Object Conditions:"
kubectl get object.kubernetes.m.crossplane.io test-object-providerconfig -n default -o jsonpath='{range .status.conditions[*]}  {.type}: {.status} ({.reason}){"\n"}{end}' 2>/dev/null || echo "  No conditions found"

echo ""
echo "ProviderConfig Managed Fields (looking for Update from crossplane-kubernetes-provider):"
kubectl get providerconfig.kubernetes.m.crossplane.io test-providerconfig -n default -o jsonpath='{.metadata.managedFields}' 2>/dev/null | jq -r '.[] | select(.manager == "crossplane-kubernetes-provider") | "  Manager: \(.manager)\n  Operation: \(.operation)\n  Fields: \(.fieldsV1 | keys | join(\", \"))\n"' 2>/dev/null || echo "  Could not retrieve managed fields"

echo ""
echo "--- ConfigMap Object (CONTROL CASE) ---"
echo ""
echo "Object Conditions:"
kubectl get object.kubernetes.m.crossplane.io test-object-configmap -n default -o jsonpath='{range .status.conditions[*]}  {.type}: {.status} ({.reason}){"\n"}{end}' 2>/dev/null || echo "  No conditions found"

echo ""
echo "ConfigMap Managed Fields:"
kubectl get configmap test-configmap -n default -o jsonpath='{.metadata.managedFields}' 2>/dev/null | jq -r '.[] | "  Manager: \(.manager)\n  Operation: \(.operation)\n  Fields: \(.fieldsV1 | keys | join(\", \"))\n"' 2>/dev/null || echo "  Could not retrieve managed fields"

echo ""
echo "=== Diagnosis ==="

# Check ProviderConfig Object status
PC_READY=$(kubectl get object.kubernetes.m.crossplane.io test-object-providerconfig -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
PC_SYNCED=$(kubectl get object.kubernetes.m.crossplane.io test-object-providerconfig -n default -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}' 2>/dev/null)

# Check ConfigMap Object status
CM_READY=$(kubectl get object.kubernetes.m.crossplane.io test-object-configmap -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
CM_SYNCED=$(kubectl get object.kubernetes.m.crossplane.io test-object-configmap -n default -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}' 2>/dev/null)

echo ""
echo "ProviderConfig Object: Ready=$PC_READY, Synced=$PC_SYNCED"
echo "ConfigMap Object:      Ready=$CM_READY, Synced=$CM_SYNCED"
echo ""

if [ "$CM_READY" = "True" ] && [ "$PC_READY" = "False" ]; then
    echo "BUG CONFIRMED:"
    echo "  - ConfigMap Object is Ready (no conflicting field manager)"
    echo "  - ProviderConfig Object is NOT Ready (bug triggered)"
    echo ""
    echo "The ProviderConfig controller uses 'crossplane-kubernetes-provider' as its"
    echo "field manager for finalizers, which incorrectly triggers CSA->SSA migration."
elif [ "$PC_READY" = "True" ] && [ "$CM_READY" = "True" ]; then
    echo "FIX WORKING: Both Objects are Ready!"
    echo "The hasSpecFields() check correctly identifies that finalizer-only"
    echo "managed field entries don't need CSA->SSA migration."
else
    echo "Status unclear - objects may still be reconciling."
    echo "Wait a few seconds and run ./check.sh again."
fi
