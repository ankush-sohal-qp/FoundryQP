#!/usr/bin/env bash
# teardown-app.sh — remove an app the GitOps way: delete its folder from git, push, and let
# ArgoCD prune everything (pods, DB, redis, service, NLB, namespace). Mirror of deploy-app.sh.
#
# Usage:  ./teardown-app.sh <app-name>
# Example: ./teardown-app.sh synthetic-data-backend
#
# This is the honest "git is the source of truth" story: the app is gone from the cluster
# BECAUSE it's gone from git — not because someone ran kubectl delete by hand.
set -euo pipefail

APP="${1:?app-name required, e.g. ./teardown-app.sh synthetic-data-backend}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -d "gitops/$APP" ]; then
  echo "ERROR: gitops/$APP does not exist — nothing to tear down." >&2
  exit 1
fi

echo "==> 1/3  remove the app from git (this is the deploy-in-reverse)"
rm -rf "gitops/$APP"
git add -A "gitops/$APP"
git commit -q -m "teardown: remove $APP via GitOps

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push -q origin main
echo "    pushed — $APP removed from git"

echo "==> 2/3  delete the ArgoCD Application + namespace directly (don't wait for the poll)"
# ApplicationSet would prune on its next reconcile; we do it now so the demo is instant + frees the NLB.
kubectl delete application "$APP" -n argocd --ignore-not-found 2>&1 | sed 's/^/    /' || true
kubectl delete namespace "$APP" --wait=false --ignore-not-found 2>&1 | sed 's/^/    /' || true

echo "==> 3/3  done. ArgoCD will keep it pruned (it's gone from git)."
echo ""
echo "Verify it's gone:"
echo "  kubectl get ns $APP                 # NotFound"
echo "  kubectl get application -n argocd   # $APP absent"
echo ""
echo "NOTE: secrets were created out-of-band (B-plan) so they vanish WITH the namespace."
echo "      The OCI NLB takes ~1-2 min to fully de-provision and free its account limit."
