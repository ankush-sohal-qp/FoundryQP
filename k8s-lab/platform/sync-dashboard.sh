#!/usr/bin/env bash
# Regenerate 09b-grafana-dashboard.yaml from platform/dashboard.json.
#
# Workflow when you tweak the dashboard in the Grafana UI and want it in git:
#   1) Export the live dashboard's INNER object back into dashboard.json:
#        kubectl -n monitoring get configmap grafana-dashboard-synthetic \
#          -o jsonpath='{.data.synthetic-data\.json}' | python3 -m json.tool > platform/dashboard.json
#   2) Run this script to rebuild the ConfigMap manifest from it:
#        ./platform/sync-dashboard.sh
#   3) kubectl apply -f platform/09b-grafana-dashboard.yaml   (then restart Grafana to reload)
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f dashboard.json ]]; then
  echo "dashboard.json not found in $(pwd)" >&2
  exit 1
fi

# Sanity: must be the RAW INNER object (no API wrapper), or file-provisioning silently shows blank panels.
if head -3 dashboard.json | grep -q '"dashboard"'; then
  echo "ERROR: dashboard.json looks like the {\"dashboard\": {...}} API wrapper." >&2
  echo "       File provisioning needs the inner object only. Strip the wrapper and retry." >&2
  exit 1
fi

{
  cat <<'HEADER'
# Grafana dashboard, provisioned as a ConfigMap so it's recreated on a fresh cluster
# (fixes the gap where the dashboard existed only live).
# Apply this file explicitly: `kubectl apply -f platform/09b-grafana-dashboard.yaml`.
# Do NOT run a bare `kubectl apply -f platform/` — this dir also holds dashboard.json (a source
# artifact, not a K8s object), which a directory-apply would choke on.
#
# IMPORTANT: the value under `synthetic-data.json` is the RAW INNER dashboard object
# (starts with "id"/"uid"/"title") — NOT the {"dashboard": {...}} API wrapper. Grafana's
# FILE provisioning (see 09-grafana.yaml's dashboard-provider) loads the inner object directly;
# the wrapper is only for the HTTP API and would make the panels fail to load.
#
# Source of truth is platform/dashboard.json. After editing the dashboard in the Grafana UI,
# re-sync both files with: ./platform/sync-dashboard.sh
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-synthetic
  namespace: monitoring
data:
  synthetic-data.json: |
HEADER
  sed 's/^/    /' dashboard.json
} > 09b-grafana-dashboard.yaml

echo "Wrote 09b-grafana-dashboard.yaml from dashboard.json"
