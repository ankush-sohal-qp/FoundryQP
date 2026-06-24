#!/usr/bin/env bash
# Create (or update) the two Secrets the synthetic-data app depends on, from local env files.
#
# This is the documented, repeatable creation path for finding #2 (secrets were live but not
# scripted). Real secret VALUES are never committed — they live in gitignored *.env files you
# create from the *.env.example templates in this dir.
#
# Secrets created:
#   postgres-creds      <- secrets/postgres.env        (consumed by 02-postgres.yaml)
#   synthetic-data-env  <- secrets/synthetic-data.env  (consumed by 04-app.yaml via envFrom)
#
# SETUP (once):
#   cp secrets/postgres.env.example       secrets/postgres.env        && edit (fill CHANGEME)
#   cp secrets/synthetic-data.env.example secrets/synthetic-data.env  && edit (fill CHANGEME)
#   ./secrets/create-secrets.sh
#
# Re-running is safe: it `apply`s, so it updates in place without deleting.
set -euo pipefail
cd "$(dirname "$0")"

NS=synthetic-data

require() {
  if [[ ! -f "$1" ]]; then
    echo "ERROR: $1 not found. Copy it from $1.example and fill in the CHANGEME values." >&2
    exit 1
  fi
  if grep -q '=CHANGEME$' "$1"; then
    echo "ERROR: $1 still has CHANGEME placeholders. Fill in real values first." >&2
    grep -n '=CHANGEME$' "$1" >&2
    exit 1
  fi
}

require postgres.env
require synthetic-data.env

# Ensure namespace exists (no-op if already there).
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"

# --from-env-file builds one Secret key per line; dry-run|apply makes it idempotent (create OR update).
kubectl create secret generic postgres-creds \
  --namespace "$NS" --from-env-file=postgres.env \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic synthetic-data-env \
  --namespace "$NS" --from-env-file=synthetic-data.env \
  --dry-run=client -o yaml | kubectl apply -f -

echo "OK: postgres-creds and synthetic-data-env applied to namespace '$NS'."
echo "Note: restart the app to pick up changed env -> kubectl -n $NS rollout restart deploy synthetic-data"
