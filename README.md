# Minimal Repro: provider-kubernetes SSA upgrade loop

Reproduces the Object-managed ProviderConfig readiness bug on namespaced `.m` APIs and validates the fix.

## Quick start

```bash
./full-test.sh
```

`full-test.sh` builds the provider in parallel with cluster setup and waits
before patching.
It will prompt for a provider source if `PROVIDER_DIR` or `PROVIDER_REPO`
is not set.

## Step-by-step

```bash
./setup.sh
./install.sh
./apply.sh
./check.sh
./build.sh
./patch.sh
./check.sh
./cleanup.sh
```

Reset provider-kubernetes only (keep Crossplane):

```bash
./reset.sh
```

## Patch against a fork/branch

`patch.sh` will prompt for a local directory or a repo/branch if none is provided.

```bash
PROVIDER_REPO=git@github.com:you/provider-kubernetes.git \
PROVIDER_REF=my-branch \
./patch.sh
```

Optional overrides:
- `PROVIDER_DIR` (build from a local checkout)
- `PROVIDER_CLONE_DIR` (clone location)

## Prereqs

- kind
- kubectl
- helm
- jq
- docker
- git (only if using `PROVIDER_REPO`)

## Diagnostic

```bash
kubectl get providerconfig.kubernetes.m.crossplane.io test-providerconfig -n default \
  -o jsonpath='{.metadata.managedFields}' | jq .
```
