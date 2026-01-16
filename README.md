# Minimal Reproduction: SSA Field Manager Upgrade Bug

This folder contains a minimal reproduction case for the SSA field manager upgrade bug in provider-kubernetes.

## Problem Summary

When provider-kubernetes creates a Kubernetes ProviderConfig via an Object resource (namespaced `.m` APIs), the Object never becomes ready due to a bug in the SSA field manager upgrade detection.

**Root Cause:** The `needSSAFieldManagerUpgrade()` function checks if any managed field entry has:
1. `Operation == Update`
2. Manager name in `legacyCSAFieldManagers` set

But it doesn't check **what fields** the manager owns. The ProviderConfig controller adds finalizers using `crossplane-kubernetes-provider` as its field manager, which is also the default legacy CSA field manager name. This creates an Update entry for `metadata.finalizers` only, incorrectly triggering CSA->SSA migration.

## Prerequisites

- A Kubernetes cluster with Crossplane installed
- provider-kubernetes installed (either the buggy version to reproduce, or the fixed version to verify)
- kubectl configured to access the cluster
- kind (used by setup.sh)
- jq (used by patch.sh and check.sh)
- docker (used by patch.sh to locate the built image; if your context is kind, it will load the image)
- git (required only if using PROVIDER_REPO in patch.sh)

## Files

- `manifests/object.yaml` - Object resource that creates a ProviderConfig
- `manifests/providerconfig.yaml` - Reference ProviderConfig manifest (for comparison)
- `apply.sh` - Script to apply the test manifests
- `check.sh` - Script to check status and managed fields
- `cleanup.sh` - Script to remove test resources

## Reproduction Steps

### 0) (Optional) Reset only provider-kubernetes state

If you want to remove provider-kubernetes and repro artifacts without uninstalling Crossplane:

```bash
./reset.sh
```

### 1) Setup a kind cluster

```bash
./setup.sh
```

### 2) Install Crossplane and provider-kubernetes

If you don't already have Crossplane and provider-kubernetes installed, run:

```bash
./install.sh
```

### 3. Apply the test resources

```bash
./apply.sh
```

### 4. Check the status

```bash
./check.sh
```

**With the bug (unfixed provider):**
- The Object will show `READY: False` or `SYNCED: False`
- The Object will continuously try to sync
- You'll see the ProviderConfig's managedFields include an Update entry from `crossplane-kubernetes-provider` with only `f:metadata.f:finalizers`

**With the fix:**
- The Object will show `READY: True` and `SYNCED: True`
- No continuous update churn
- The fix correctly identifies that finalizer-only entries don't need CSA->SSA migration

### 5) Apply the fix (patch provider-kubernetes)

This rebuilds and deploys the fixed provider into the current cluster by
patching the existing Provider to point at a local dev xpkg and updating
its DeploymentRuntimeConfig image:

```bash
./patch.sh
```

You can also test a fork/branch by setting:

```bash
PROVIDER_REPO=git@github.com:you/provider-kubernetes.git \
PROVIDER_REF=my-branch \
./patch.sh
```

Optional overrides:
- `PROVIDER_DIR` to build from a local checkout
- `PROVIDER_CLONE_DIR` to control where the repo is cloned

### 6. Inspect managed fields (diagnostic)

```bash
kubectl get providerconfig.kubernetes.m.crossplane.io test-providerconfig -n default -o jsonpath='{.metadata.managedFields}' | jq .
```

Look for an entry like:
```json
{
  "manager": "crossplane-kubernetes-provider",
  "operation": "Update",
  "fieldsV1": {"f:metadata": {"f:finalizers": {}}}
}
```

This entry has NO `f:spec` key, so it should NOT trigger migration (fixed behavior).

### 7. Cleanup

```bash
./cleanup.sh
```

### Full run (setup -> install -> apply -> check -> patch -> check)

```bash
./full-test.sh
```

## The Fix

The fix adds a `hasSpecFields()` helper function that checks if the managed field entry owns any `f:spec` fields. The migration is only triggered when:

1. Operation is `Update` (CSA indicator)
2. Manager name is in the legacy CSA field managers set
3. **AND** the manager owns `f:spec` fields (new check)

This prevents false positives when other controllers (like the ProviderConfig controller) use the same field manager name for metadata-only updates.

## Related Files (in provider-kubernetes)

- `internal/controller/cluster/object/syncer.go` - needSSAFieldManagerUpgrade() and hasSpecFields()
- `internal/controller/namespaced/object/syncer.go` - Same functions (namespaced variant)
