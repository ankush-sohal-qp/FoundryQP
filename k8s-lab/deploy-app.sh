#!/usr/bin/env bash
# deploy-app.sh — onboard the synthetic-data backend from the golden template, end to end:
# generate -> add postgres/redis -> create secrets out-of-band -> git push -> ArgoCD deploys.
# Mirror of teardown-app.sh. This is the live "one command spins up a full stateful app" demo.
#
# Usage:  ./deploy-app.sh [app-name]
#         (defaults to synthetic-data-backend)
#
# Prereqs: a valid OCI session (oci session authenticate --profile-name oktest6 ...) and the
# secret backups in the scratch dir (created when the previous instance was torn down).
set -euo pipefail

APP="${1:-synthetic-data-backend}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRATCH="${SECRET_BACKUP_DIR:-/private/tmp/claude-501/-Users-ankushsohal-Developer-questionPro-infraX/6f203686-1b07-49ca-b32a-3ac3ca3037c2/scratchpad}"
cd "$REPO_ROOT"

echo "==> 1/5  generate $APP from the golden template (LoadBalancer + OCIR pull + 30s readiness)"
PULL_SECRET=ocir-secret SERVICE_TYPE=LoadBalancer READINESS_DELAY=30 \
  ./k8s-lab/template/new-app.sh "$APP" data-team \
  bom.ocir.io/bm7gzqslzqdh/synthetic-data:v1 2 3001 150m 256Mi

echo "==> 2/5  add postgres + redis (stateful deps the template doesn't generate)"
# stable source of truth: the scratch backups (recovered once, survive teardown/redeploy cycles).
# rewrite the namespace to the new app name.
for f in 02-postgres.yaml 03-redis.yaml; do
  if [ -f "$SCRATCH/bak-$f" ]; then
    sed "s/namespace: synthetic-data\$/namespace: $APP/" "$SCRATCH/bak-$f" > "gitops/$APP/$f"
  elif [ -f "gitops/synthetic-data/$f" ]; then
    sed "s/namespace: synthetic-data\$/namespace: $APP/" "gitops/synthetic-data/$f" > "gitops/$APP/$f"
  else
    echo "ERROR: no source for $f (looked in $SCRATCH/bak-$f and gitops/synthetic-data/$f)" >&2
    echo "       run: git show <commit>:gitops/synthetic-data/$f > $SCRATCH/bak-$f" >&2
    exit 1
  fi
done

echo "==> 3/5  app-specific fixes: readiness path + baseline PSA (root image)"
sed -i '' "s|path: /$APP/api/health|path: /synthetic-data/api/health|" "gitops/$APP/04-app.yaml"
sed -i '' 's|pod-security.kubernetes.io/enforce: restricted|pod-security.kubernetes.io/enforce: baseline|' "gitops/$APP/01-namespace.yaml"

echo "==> 4/5  namespace + secrets out-of-band (B-plan; REDIS_HOST -> 'redis')"
kubectl create namespace "$APP" --dry-run=client -o yaml | kubectl apply -f -
for s in ocir-secret postgres-creds; do
  python3 -c "import json;d=json.load(open('$SCRATCH/bak-$s.json'));d['metadata']['namespace']='$APP';print(json.dumps(d))" | kubectl apply -f -
done
python3 -c "
import json,base64
d=json.load(open('$SCRATCH/bak-synthetic-data-env.json'))
d['metadata']['namespace']='$APP'; d['metadata']['name']='$APP-env'
d['data']['REDIS_HOST']=base64.b64encode(b'redis').decode()
print(json.dumps(d))" | kubectl apply -f -

echo "==> 5/5  git push (the deploy) + nudge ArgoCD"
git add "gitops/$APP"
git commit -q -m "onboard $APP from the golden template (full stateful app)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push -q origin main
kubectl annotate applicationset apps -n argocd argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true

echo ""
echo "DONE. Watch it come up:"
echo "  kubectl get pods -n $APP -w"
echo "Public IP (NLB provisions in ~2-3 min):"
echo "  kubectl get svc $APP -n $APP -w"
