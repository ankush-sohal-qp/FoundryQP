#!/usr/bin/env bash
# new-app.sh — generate a complete, consistent base for a new app from the golden templates.
#
# Usage:
#   ./new-app.sh <app-name> <team> <image> [replicas] [port] [cpu_req] [mem_req] [ingress_host]
#
# Example:
#   ./new-app.sh audience-backend audience-team bom.ocir.io/bmpasgoonhpi/audience:v1 3 3000 200m 512Mi audience.test
#
# Output: template/apps/<app-name>/*.yaml  (ready to `kubectl apply -f`)
# This is the ONLY thing an app-team runs to onboard. No hand-editing 18 places, no missed guardrail.

set -euo pipefail

# ---- args (with sensible defaults) -----------------------------------------
APP_NAME="${1:?app-name required (e.g. audience-backend)}"
TEAM="${2:?team required (e.g. audience-team)}"
IMAGE="${3:?image required (e.g. bom.ocir.io/ns/audience:v1)}"
REPLICAS="${4:-2}"
PORT="${5:-3000}"
CPU_REQUEST="${6:-150m}"
MEM_REQUEST="${7:-256Mi}"
INGRESS_HOST="${8:-${APP_NAME}.test}"

# ---- optional behaviour via env vars (keeps the positional interface stable) -----
#   PULL_SECRET=ocir-secret   -> private-registry images (adds imagePullSecrets)
#   SERVICE_TYPE=LoadBalancer -> direct public OCI NLB (else ClusterIP behind nginx Ingress)
#   READINESS_DELAY=30        -> initialDelaySeconds for DB-dependent apps (default 15)
PULL_SECRET="${PULL_SECRET:-}"
SERVICE_TYPE="${SERVICE_TYPE:-ClusterIP}"
READINESS_DELAY="${READINESS_DELAY:-15}"

# derived values (memory limit = 3x request, quota = headroom for replicas)
MEM_LIMIT="${MEM_REQUEST%Mi}"; MEM_LIMIT="$((MEM_LIMIT * 3))Mi"
HEALTH_PATH="/${APP_NAME}/api/health"
# quota: enough for replicas + DB/redis + a little burst
QUOTA_CPU_REQ="2"
QUOTA_MEM_REQ="3Gi"
QUOTA_MEM_LIM="8Gi"

# ---- build the conditional blocks the templates reference -------------------
# imagePullSecrets: emit the block only when a pull secret was named.
if [ -n "$PULL_SECRET" ]; then
  IMAGE_PULL_SECRETS="imagePullSecrets:
        - name: ${PULL_SECRET}"
else
  IMAGE_PULL_SECRETS="# (public image — no imagePullSecrets needed)"
fi

# externalTrafficPolicy: Local is ONLY valid on LoadBalancer/NodePort, invalid on ClusterIP.
if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
  TRAFFIC_POLICY="externalTrafficPolicy: Local"
else
  TRAFFIC_POLICY="# (ClusterIP — externalTrafficPolicy not applicable; reached via Ingress)"
fi

# Ingress only makes sense for the ClusterIP path. A LoadBalancer app is already public via NLB.
if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
  INGRESS_BLOCK="# (SERVICE_TYPE=LoadBalancer — public via OCI NLB directly, no Ingress)"
else
  INGRESS_BLOCK="---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAME}
spec:
  ingressClassName: nginx
  rules:
    - host: ${INGRESS_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${APP_NAME}
                port:
                  number: 80"
fi

# ---- locate templates + output dir -----------------------------------------
# Output goes STRAIGHT into gitops/<app>/ — the directory the ArgoCD ApplicationSet watches.
# That closes the self-service loop: render -> git push -> ApplicationSet auto-creates the
# Application -> deployed. No copy step, no `argocd app create`, no `kubectl apply`.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/base"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO_ROOT/gitops/$APP_NAME"

if [ ! -d "$BASE_DIR" ]; then echo "ERROR: base templates not found at $BASE_DIR" >&2; exit 1; fi
mkdir -p "$OUT_DIR"

# ---- fill every {{PLACEHOLDER}} in each template ---------------------------
# Scalars via sed; the multi-line conditional blocks (pull-secret, traffic-policy, ingress)
# via python so embedded newlines + YAML indentation survive intact.
render() {
  sed \
    -e "s|{{APP_NAME}}|${APP_NAME}|g" \
    -e "s|{{TEAM}}|${TEAM}|g" \
    -e "s|{{IMAGE}}|${IMAGE}|g" \
    -e "s|{{REPLICAS}}|${REPLICAS}|g" \
    -e "s|{{PORT}}|${PORT}|g" \
    -e "s|{{CPU_REQUEST}}|${CPU_REQUEST}|g" \
    -e "s|{{MEM_REQUEST}}|${MEM_REQUEST}|g" \
    -e "s|{{MEM_LIMIT}}|${MEM_LIMIT}|g" \
    -e "s|{{HEALTH_PATH}}|${HEALTH_PATH}|g" \
    -e "s|{{INGRESS_HOST}}|${INGRESS_HOST}|g" \
    -e "s|{{SERVICE_TYPE}}|${SERVICE_TYPE}|g" \
    -e "s|{{READINESS_DELAY}}|${READINESS_DELAY}|g" \
    -e "s|{{QUOTA_CPU_REQ}}|${QUOTA_CPU_REQ}|g" \
    -e "s|{{QUOTA_MEM_REQ}}|${QUOTA_MEM_REQ}|g" \
    -e "s|{{QUOTA_MEM_LIM}}|${QUOTA_MEM_LIM}|g" \
    "$1" \
  | IMAGE_PULL_SECRETS="$IMAGE_PULL_SECRETS" TRAFFIC_POLICY="$TRAFFIC_POLICY" INGRESS_BLOCK="$INGRESS_BLOCK" \
    python3 -c 'import os,sys
s=sys.stdin.read()
for k in ("IMAGE_PULL_SECRETS","TRAFFIC_POLICY","INGRESS_BLOCK"):
    s=s.replace("{{%s}}"%k, os.environ.get(k,""))
sys.stdout.write(s)'
}

for tmpl in "$BASE_DIR"/*.tmpl.yaml; do
  out_name="$(basename "$tmpl" .tmpl.yaml).yaml"
  render "$tmpl" > "$OUT_DIR/$out_name"
done

# ---- guard: did any placeholder slip through unfilled? ----------------------
if grep -rq "{{" "$OUT_DIR"; then
  echo "WARNING: some {{PLACEHOLDERS}} were not filled:" >&2
  grep -rno "{{[A-Z_]*}}" "$OUT_DIR" >&2
fi

echo "✓ Generated base for '$APP_NAME' (team: $TEAM) -> $OUT_DIR"
echo "  files: $(ls "$OUT_DIR" | tr '\n' ' ')"
echo ""
echo "Next steps (self-service GitOps flow):"
echo "  1. Create its secret out-of-band (stays OUT of git, B-plan):"
echo "       kubectl create namespace ${APP_NAME}"
echo "       kubectl create secret generic ${APP_NAME}-env -n ${APP_NAME} --from-env-file=YOUR.env"
echo "       # + a docker-registry pull secret 'ocir-secret' if the image is in private OCIR"
echo "  2. Commit + push — that's the deploy:"
echo "       git add gitops/${APP_NAME} && git commit -m 'onboard ${APP_NAME}' && git push"
echo "  The ApplicationSet (gitops/_appset.yaml) auto-detects the new folder, creates the"
echo "  ArgoCD Application, and deploys it. No kubectl apply, no argocd app create."
