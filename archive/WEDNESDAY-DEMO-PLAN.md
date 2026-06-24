# Wednesday Demo — Plan of Action

**Goal:** Team ko dikhana ki K8s ek **Internal Developer Platform (IDP)** ke roop mein QP ke liye best pick kyun hai —
multi-DC, 100s apps, backups/uptime/logs ka bojh. Model: **hum platform banayenge + monitor karenge; app-teams apni
app khud deploy karengi** (= "you build it, you run it" ka successor, platform-engineering pattern).

**Demo vehicle:** `backend-synthetic-data` (real app, real image, real config) cluster mein properly running +
autonomy (heal/scale/isolate) + monitoring live.

**Deadline:** Wednesday (plan noted 2026-06-15).

---

## VERIFIED as-built (CURRENT — re-confirmed live 2026-06-16, assume nahi)

- **Mac:** 10 CPU / 16 GB. **Colima VM ab 6 CPU / 12 GB** (resize ho chuka — original 2/2 blocker fixed).
- **Cluster:** minikube **2-node** (`minikube` control-plane + `minikube-m02` worker), K8s v1.35.1,
  **Calico CNI**, dono nodes Ready, ~23h uptime.
- **Running:** ingress-nginx, kubernetes-dashboard, metrics-server, in-cluster registry,
  Prometheus + Grafana (monitoring ns), app stack (synthetic-data 2/2 + postgres + redis).
- **metrics-server:** ENABLED (HPA + `kubectl top` working).
- _(Original blocker snapshot — single-node 2CPU/2GB, metrics-server OFF — Phase 0 mein fix hua; details niche.)_
- **Image:** synthetic-data ka image moonstone monorepo se **local build** hoga (Dockerfile.backend, turbo).
  Registry creds ki zaroorat NAHI (minikube ke andar build).
- **App config:** `.env.development` mein real QP/AI-Router secrets plaintext hain → K8s **Secret** object mein
  jaayenge (ConfigMap mein NAHI). File git mein commit na ho — verify `.gitignore`.
- **App deps (boot):** Postgres(pgvector pg17) + Redis 7 + external QP OAuth + AI Router. Global prefix
  `/synthetic-data/api`. Health endpoint mojood (`@nestjs/terminus`). Metrics endpoint mojood
  (`@willsoto/nestjs-prometheus`).

---

## Architecture decision (websearch se confirm, 2026 best practice)

- "Infra hum, app team, monitor hum" = **Platform Engineering / IDP** — industry standard, Gartner: 80% bade orgs
  2026 tak platform team bana lenge. Direction SAHI.
- Self-service = **namespace-per-team + RBAC + ResourceQuota + NetworkPolicy** ("namespace-as-a-service").
- **Real multi-DC ka asli engine = GitOps (ArgoCD/Flux)**: team git mein YAML push kare → controller cluster pe
  sync kare. Yeh "wish + reconcile loop" ka org-scale version. + **multi-cluster** (har DC = apna cluster,
  central ArgoCD hub-and-spoke). **Cluster boundary = residency boundary** (EU cluster EU mein) — yehi
  compose-eu vs compose-qp ka K8s version.
- **Wednesday scope honesty:** poora IDP (Backstage + Crossplane + multi-cluster ArgoCD) = mahine ka kaam, Wednesday
  ka NAHI. Wednesday = **PoC jo vision proves**. Team ko bolna: "yeh PoC single-cluster hai; real version GitOps +
  multi-cluster + namespace-as-a-service pe khada hoga." Roadmap ko PoC bolke mat bechना.

---

## HA — do level (clarity ke liye)

- **Node-level HA** (pod/node mara → pods doosre node pe reschedule): **ek Mac, multi-node minikube** → Wednesday-ready.
- **Region-level HA** (poora DC mara → doosra DC le le): **do machine, do cluster + global LB** → baad mein / slide.
- **Residency catch:** EU app sirf EU boundary ke andar failover kar sakta hai (data border cross nahi). HA hamesha
  boundary ke andar.

---

## Plan of Action (forced-move order)

### Phase 0 — Foundation (BLOCKER fix) — ✅ DONE (2026-06-15)
- [x] Colima restart 6 CPU / 12 GB (tha 2/2).
- [x] metrics-server enable.
- [x] **2-node** cluster + **Calico** CNI (NOT 3-node/kindnet — woh flaky tha; rebuild with `--nodes 2 --cni calico`).

### Phase 1 — App properly running (CORE GOAL) — ✅ DONE (2026-06-15)
- [x] Postgres(pgvector, **port 5433** — local-dev match) + Redis as in-cluster pods + PVC.
- [x] synthetic-data image build + push to in-cluster registry.
- [x] `.env.development` → K8s **Secret** (DB host→`postgres`, port→`5433`, redis→`redis` overridden).
- [x] App Deployment(2 replicas) + Service + Ingress (`/synthetic-data/api`) + readiness/liveness probes.
- [x] Migrations run; app green — health `{"status":"ok"}`, DB up, both pods 1/1 on different nodes.

### Phase 2 — Self-service proof (platform role) — ✅ DONE (2026-06-16)
- [x] DB security: Postgres creds → `postgres-creds` Secret; NetworkPolicy lockdown (Postgres+Redis sirf
      `app=synthetic-data` se reachable — verified: outsider BLOCKED, insider CONNECTED).
- [x] ResourceQuota (cpu/mem/pods cap) + LimitRange (per-pod defaults) + RBAC Role/RoleBinding.
      Verified: team CAN manage own ns, CANNOT touch `default` ns or cluster nodes.
- NOTE: secrets base64 only (NOT encrypted-at-rest) — etcd-encryption/Vault = roadmap.

### Phase 3 — Autonomy proof (demo ka DIL) — ✅ DONE (2026-06-16)
- [x] **Pod kill → self-heal** — maara pod, 0s mein naya, 33s mein Ready, deployment wapas 2/2. (verified)
- [x] **Node drain → pods shift** — m02 drain (fail simulate); saare pods control-plane pe auto-reschedule;
      service kabhi fully down nahi (min 1/2 bana raha); app ne postgres re-attach ka wait + retry karke
      khud recover kiya. (verified) — LEARNING: stateful re-attach pe dependent app temporarily crashloops,
      par K8s khud retry karke theek karta hai. "fail hua par apне aap sambhal gaya" = autonomous proof.
      m02 uncordon karke wapas laaya.
- [x] **HPA + load → auto scale** — HPA 2→6 @ CPU 50%. Load-gen se CPU 384%+ → HPA ne 6 tak scale-up kiya
      (RE-VERIFIED 2026-06-16, clean — sab 6 pods Running, 3 per node, no FailedCreate). Load hata →
      Scale-up fast (window 0s, +4/15s), scale-down deliberate.
      ► REPEATABLE NOW: `kubectl apply -f platform/10-hpa-autoscale.yaml` (ONE file = HPA + in-cluster
        loadgen Deployment; replaces the old 10-hpa-loadgen + 11-hpa-demo split). Scale-down window
        tuned to 30s so it's watchable live. Stop load: `kubectl -n synthetic-data scale deploy loadgen
        --replicas=0`. Teardown: `kubectl delete -f platform/10-hpa-autoscale.yaml` + `kubectl -n
        synthetic-data scale deploy synthetic-data --replicas=2`.
      ► QUOTA BUMPED for clean scale: `limits.cpu` 4→10, `limits.memory` 6Gi→8Gi (06-quota-rbac.yaml).
        Reason: 6 app pods ×1 core + pg/redis ≈ 8.1 core peak — 4-core cap would block at pod 3-4.
        Decision (Ankush, 2026-06-16): show CLEAN HPA 2→6, NOT the quota-block framing.
      [historic] Pehle quota=4 pe load pods ResourceQuota ne BLOCK kiye the (`Forbidden: exceeded quota`)
        — woh "runaway team blocked" moment ab quota=10 pe nahi aayega (deliberately traded away).
- [x] **Memory OOM → blast-radius isolation** — `memory-hog` (64Mi limit, 150M grab) → OOMKilled+CrashLoop,
      par synthetic-data (restarts unchanged) + postgres (restarts=0) bilkul UNTOUCHED. (verified)
      Har container ka apna memory cgroup → ek app ka leak neighbours ko nahi le doobta.

### Phase 4 — Monitoring ("hum sirf monitor karenge") — ✅ DONE (2026-06-16)
- [x] Prometheus + Grafana IN-CLUSTER (NOT Grafana Cloud — self-hosted = "apni infra khud monitor").
      `monitoring` ns: 08-prometheus.yaml (scrapes nodes + cadvisor + app /metrics), 09-grafana.yaml
      (Prometheus pre-wired as datasource). Grafana admin password = from `grafana-admin` Secret (not committed).
- [x] Custom dashboard `Synthetic Data Platform — Live` (app RSS/pod, node heap, pod CPU, pod memory,
      running-pod count (stat), node CPU — all live).
      ► REPRODUCIBLE NOW: provisioned from a ConfigMap (`09b-grafana-dashboard.yaml`), NOT pushed via
        API — so `kubectl apply -f platform/09b-grafana-dashboard.yaml` recreates it on a fresh cluster
        and it survives Grafana restarts. Source of truth = `platform/dashboard.json` (raw INNER object,
        no API wrapper); after UI edits, re-sync with `./platform/sync-dashboard.sh`.
        NOTE: apply manifests by file (as documented), not `kubectl apply -f platform/` — that dir holds
        `dashboard.json` (a source artifact, not a manifest) which a bare dir-apply would choke on.
- [x] Verified live: self-heal (pod kill → new pod spike in graphs) + HPA scale-up 2→6 visible on
      "Running app pods" panel under load.
- ACCESS: `kubectl -n monitoring port-forward svc/grafana 4001:3000` → http://localhost:4001/d/synthetic-data-platform
  (Grafana on 4001, not 3000 — 3000 collides with the frontend's OAuth redirect.)

## ⚠️ DEMO-DAY GOTCHAS (aaj live fate — Wednesday inse bachो)
1. **HPA vs ResourceQuota tension** — HPA scale chahta tha (CPU 500%+) par pods `FailedCreate` huye
   kyunki `limits.cpu` quota cap hit ho gaya (har app pod 1 core maangta; 4-core quota mein 2 pods =
   3.9 core, naye ke liye jagah nahi). **This is by-design, not a bug** — it's the real platform-eng
   tension (autoscaler wants more, guardrail says no). DECIDE which to show:
     - HPA scale demo → quota `limits.cpu` ≥ 8-10 (headroom).
     - Quota-guardrail demo → keep quota small; when HPA blocks, SAY "platform stopped a runaway team".
2. **Don't touch the Deployment while HPA is active** — patching/annotating it triggers a NEW ReplicaSet
   (rolling update) → extra pods (saw 8 instead of 6). For HPA demo: ONLY apply load, let HPA scale.
3. **Load generator must be a Deployment, not `kubectl run ... -- "while..."`** — the inline-shell run
   pods exited immediately (Completed, exitCode 0, loop never ran). Use a proper loadgen Deployment.
4. **Stateful (Postgres) re-attach on node-drain** takes time; dependent app crashloops briefly then
   self-recovers. Expected — narrate it as "failed but healed itself", don't panic-fix.
5. **STALE FailedCreate events on screen** — `kubectl -n synthetic-data get events` shows OLD
   `exceeded quota: limited: limits.cpu=4` warnings from earlier quota=4 testing. They are NOT current
   (quota is now 10). During the demo DON'T run bare `get events` (audience sees scary "forbidden"
   lines that look like a live failure). If you need events, scope to recent:
   `kubectl -n synthetic-data get events --sort-by=.lastTimestamp | tail -15`. They age out on their
   own (~1h default TTL).

### Phase 5 — GitOps (vision clincher) — NICE-TO-HAVE
- [ ] ArgoCD: git change → cluster auto-sync. Multi-DC ka asli engine.
- [ ] Time na bache → slide pe roadmap.

---

## Execution approach
- Pehle **Phase 0 + 1 end-to-end** (foundation + app actually running) — sabse risky (image/DB/secrets/boot).
  Wo chal gaya → baaki phases (heal/scale/monitor) fast.
- **Wednesday must-have:** Phase 0→4. **Nice-to-have:** Phase 5.

## Gotchas hit & solved (real, is session mein)
- **Colima default 2CPU/2GB** — resize zaroori (`colima stop` → `colima start --cpu 6 --memory 12`). Cluster restart hua, data bacha.
- **Multi-node bina CNI = workers NotReady** — `minikube node add` ne warning di. Fix: kindnet install
  (`kubectl apply -f https://raw.githubusercontent.com/aojea/kindnet/main/install-kindnet.yaml`). Cross-node ping verified.
- **`minikube image build` sirf control-plane pe image daalta hai** → workers pe `ErrImageNeverPull`.
  `minikube image load` mere setup mein image cache se *uda* deta tha. Mac↔worker direct SSH (192.168.49.x:22)
  Mac se reachable NAHI (Colima-internal network).
  **Solution = registry addon:** `minikube addons enable registry` → control-plane se image registry ClusterIP pe
  push → manifest `image: localhost:5000/<img>` + `imagePullPolicy: IfNotPresent` (har node ka registry-proxy
  localhost:5000 serve karta hai). Yeh multi-node ka sanctioned tareeka — ad-hoc copy se bachо.
- **kindnet CNI multi-node pe FLAKY** — node delete/re-add + cluster restart ke baad cross-node routing PERMANENTLY
  toot gayi (same-node OK, cross-node 100% packet loss). kindnet restart se bhi theek nahi hua. App↔Postgres alag
  node pe → connect fail → migration crashloop → CPU thrash → apiserver choke. Sab isi ek root se.
  **Solution = clean rebuild with Calico:** `minikube delete` → `minikube start --nodes 2 --cni calico`.
  Calico stable nikla — cross-node 0% loss, restart pe nahi toota. **Seekh: multi-node minikube ALWAYS start se
  `--cni calico` + `--nodes N` ke saath banao; baad mein `node add` + kindnet mat karो.**
- **Resource sizing:** Colima 12GB, cluster `--cpus 3 --memory 5000` per node × 2. 3-node 6-core VM pe thrash hua;
  2-node zyada stable.

## Open / UNVERIFIED (proceed se pehle ya dauraan dekhna)
- synthetic-data image build pehli baar — boot pe external QP/AI calls fail ho sakti hain; platform-story phir bhi
  intact (app up+healthy+monitored) rakhni hai, end-to-end generation Wednesday ka goal NAHI.
- `.gitignore` mein `.env.*` hai ya nahi — secrets leak check.
- Team ka exact expectation: naya K8s platform vs current-setup-standardize — confirm.

---

## Production-readiness status (honest framing for "is this production?")
This is a **strong platform-engineering PoC**, NOT a production cluster. Be precise about both.

### Hardened (done + verified live, 2026-06-16)
- **Reproducible repo** — dashboard provisioned via ConfigMap (`09b-grafana-dashboard.yaml` + `sync-dashboard.sh`);
  secrets creation scripted (`secrets/create-secrets.sh` + `*.env.example`, real values gitignored).
- **Liveness decoupled from DB** — app liveness is `tcpSocket:3001` (process-alive), readiness keeps the DB check.
  Prevents DB-outage restart loops. (verified: rolled 2/2 clean.)
- **Prometheus TSDB durable** — 5Gi PVC at `/prometheus` + `Recreate` strategy + 7d retention + chown initContainer.
  (VERIFIED: deleted the pod, WAL/chunks survived on the same PVC, 6/6 targets up after restart.)
- **Baseline workload hardening** — app + Prometheus: `allowPrivilegeEscalation:false`, `capabilities.drop:[ALL]`,
  `seccompProfile:RuntimeDefault`. Prometheus also runs `runAsNonRoot` (uid 65534).
- **Single HPA source** — `10-hpa-autoscale.yaml` (merged; removed the 10+11 duplicate-HPA footgun).

### Still roadmap (real production work — name it, don't hide it)
- **Control-plane HA** — single minikube control-plane + embedded etcd, no etcd backup, single host = single failure
  domain. Production needs 3+ control-plane nodes, separated/backed-up etcd, LB'd apiserver, multi-zone.
- **App can't run non-root yet** — image currently runs as UID 0 and writes to `/`. Real fix = rebuild image with a
  non-root user + writable `/tmp` volume, then add `runAsNonRoot`/`readOnlyRootFilesystem` to 04-app.yaml.
- **No alerting** — no Prometheus rules, no Alertmanager. ("metrics monitoring", not full observability — also no
  centralized logs / tracing.)
- **Grafana demo creds + anonymous auth** (`09-grafana.yaml`) — fine for PoC, replace with real auth + secret for prod.
- **No PodDisruptionBudget**, secrets are base64-not-encrypted (etcd-encryption/Vault), no GitOps (Phase 5).

### One-line verdict for the room
"Platform skeleton + metrics-monitoring PoC: self-heals, autoscales, network-isolated, resource-guarded, hardened
at the workload level, reproducible from git. Control-plane HA, non-root images, alerting, and GitOps are the
roadmap to production."
