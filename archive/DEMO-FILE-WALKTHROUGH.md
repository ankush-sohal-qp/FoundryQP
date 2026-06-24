# Demo File Walkthrough — what each file does + what to SAY

Read this once. Then in the demo, open any file and you know the story behind it.
Frame for the whole thing: **platform team builds/runs all of this once; app-teams only bring an image + a few config values.**

Order matters — the file numbers ARE the build order (foundation → app → guardrails → autonomy → monitoring).

---

## THE PLATFORM SKELETON (foundation an app-team never touches)

### `01-namespace.yaml` — the app's "apartment"
- **Declares:** Namespace `synthetic-data`.
- **Say:** "Every app-team gets its own namespace — an isolated apartment in the building. Their pods, secrets, quotas all live here, walled off from other teams."
- **Why:** Multi-tenancy. One team can't see or touch another's stuff.

### `02-postgres.yaml` — the database (a *pet*, not cattle)
- **Declares:** headless Service `postgres` + StatefulSet `postgres` + PVC (2Gi).
- **Say:** "The app's database. It's a **StatefulSet**, not a Deployment, because a DB has identity and must keep its disk — the PVC means data survives pod restarts. Credentials come from a Secret, never hardcoded."
- **Why StatefulSet vs Deployment:** stateless apps = cattle (replace freely); a DB = pet (stable name + stable storage).

### `03-redis.yaml` — the cache
- **Declares:** Service `redis` + Deployment `redis`.
- **Say:** "Cache/queue layer. Plain Deployment because it's disposable — losing it doesn't lose data."

### `04-app.yaml` — THE APP-TEAM'S ACTUAL DELIVERABLE
- **Declares:** Deployment `synthetic-data` (2 replicas) + Service + Ingress.
- **Say — this is the key file:** "Everything else in this folder is **us, the platform**. THIS file is all an app-team owns: their image + config. We give them heal/scale/route/monitor for free around it."
- **Point out 4 things in it:**
  1. **2 replicas + topologySpread** → "always 2 copies, spread across nodes — node dies, app survives."
  2. **readinessProbe (hits DB)** → "only gets traffic when its DB is actually reachable."
  3. **livenessProbe (tcpSocket:3001)** → "restarts a hung process — deliberately does NOT check the DB, so a DB outage doesn't restart-loop the whole app." (this is the fix we made)
  4. **resources requests/limits** → "the app's reserved 'slice' — guaranteed floor (request) and hard ceiling (limit)."
  - **Service** = internal load-balancer (port 80 → pod 3001). **Ingress** = the external route (host `synthetic.test`).
- **Why:** This is the entire "app-teams just ship their app" pitch, in one file.

---

## THE GUARDRAILS (why no single team can hurt the cluster)

### `05-networkpolicy.yaml` — the firewall between apps
- **Declares:** NetworkPolicy (default-deny + explicit allows).
- **Say:** "By default, nothing can talk to anything. We explicitly allow only what's needed — e.g. the app→postgres, app→redis. A compromised app can't scan or reach its neighbours."
- **Why:** Security/blast-radius at the network layer.

### `06-quota-rbac.yaml` — spending limits + who-can-do-what
- **Declares:** ResourceQuota + LimitRange + Role + RoleBinding.
- **Say:** "**ResourceQuota** = the team's total budget (can't exceed X CPU/RAM cluster-wide). **LimitRange** = sensible default per pod if a dev forgets to set one. **Role/RoleBinding** = the team can manage their own apps but not other namespaces or cluster settings."
- **Why:** A runaway team (or a bad loop) gets stopped by the quota instead of eating the whole cluster. This is the platform's guardrail.

### `07-oom-demo.yaml` — the blast-radius PROOF (demo prop)
- **Declares:** Deployment `memory-hog` (64Mi limit, grabs 150M → gets killed).
- **Say:** "This is a deliberate bad app that leaks memory. Watch — Kubernetes OOM-kills **only it**; synthetic-data and postgres stay untouched. One app's failure can't take down its neighbours."
- **Why:** Proves isolation live. (Apply it during the demo, show the OOMKill, delete it.)

---

## AUTONOMY (it runs itself)

### `10-hpa-autoscale.yaml` — autoscaling + the load generator
- **Declares:** HorizontalPodAutoscaler `synthetic-data` + Deployment `loadgen`.
- **Say:** "**HPA** = when average CPU crosses 50%, scale the app 2→6 pods automatically; drop back when quiet. **loadgen** = a tiny in-cluster traffic generator so we can trigger it live on Grafana. Scale-up is instant, scale-down is tuned to 30s so it's watchable."
- **Why:** "No one pages at 2am to add capacity — the platform adds and removes it on its own." (This is the merged single-HPA file; the old 10+11 duplicate was removed.)
- **Self-heal note:** there's no separate file for self-heal — it's the Deployment itself (kill a pod, the Deployment recreates it). Demo it with `kubectl delete pod`.

---

## MONITORING (we watch everything)

### `08-prometheus.yaml` — the metrics collector
- **Declares:** monitoring Namespace + ServiceAccount + ClusterRole/Binding (read-only cluster-wide) + ConfigMap (scrape config) + PVC (durable TSDB) + Deployment + Service.
- **Say:** "Prometheus scrapes CPU/memory/health from every pod and node every few seconds. The **PVC** means its history survives restarts — that was ephemeral before, now it's durable (we verified a restart keeps the data). The ClusterRole is **read-only** — it can see metrics, not change anything."
- **Why:** The data source behind every graph. The init-container chowns the disk so it runs non-root.

### `09-grafana.yaml` — the dashboards UI
- **Declares:** datasource ConfigMap + dashboard-provider ConfigMap + Deployment + Service.
- **Say:** "Grafana = the screen the team looks at. Prometheus is pre-wired as its data source, so it's connected on first open. Runs on port 4001 (3000 collided with the app's login redirect)."
- **Why:** Human-facing window into the platform. (Creds admin/****, anonymous on — PoC only, flag as roadmap.)

### `09b-grafana-dashboard.yaml` — the actual dashboard, as code
- **Declares:** ConfigMap `grafana-dashboard-synthetic` (the dashboard JSON).
- **Say:** "The dashboard itself is **provisioned from git**, not hand-clicked — so a fresh cluster rebuilds it automatically and it survives Grafana restarts. Source of truth is `dashboard.json`; `sync-dashboard.sh` keeps them in step."
- **Why:** Reproducibility — the whole platform comes back from git, including the dashboards.

---

## THE 30-SECOND VERSION (if asked "summarize what's here")
- **01–04**: the app and its data, declared as code. **04 is the only file an app-team writes.**
- **05–07**: guardrails — network firewall, spending quotas, RBAC. Proven by the OOM blast-radius demo.
- **10**: autonomy — autoscaling (+ self-heal from the Deployment itself).
- **08–09b**: monitoring — Prometheus collects, Grafana shows, all reproducible from git.

**One line:** "Of these 11 files, **one** is the app-team's job. The other ten are the platform we build and run so they don't have to."
