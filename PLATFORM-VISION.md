# FoundryQP — Platform Vision & Operating Model

> **One line:** The infra team runs the platform; every app team self-serves their own
> apps through a UI + Git — fewer clicks, more teams, no tickets.

This is the blueprint for turning FoundryQP from "one app deployed via GitOps" into a true
**Internal Developer Platform (IDP)** that many teams use independently.

---

## 1. The goal (in plain words)

- **Infra team (us)** owns and runs the *platform* only — the cluster, the deploy engine, the
  front door, the registry, the guardrails. We do NOT babysit individual apps.
- **App teams (everyone else)** own their *apps* end-to-end — code, image, config, ingress
  rules, scaling, deploys — and do it **themselves** through a **self-service UI + Git**.
- The platform makes the *right way the easy way*: a team fills a short form / runs one command,
  and they get a production-grade setup automatically (health checks, limits, isolation, security).

This is **Platform Engineering**: build the paved road once, every team drives on it.

---

## 2. The clean split — who owns what (the heart of the model)

| Layer | **Platform team (us)** owns | **App teams** own (self-service) |
|---|---|---|
| Cluster / nodes | ✅ Capacity, upgrades, scaling | — |
| Deploy engine (ArgoCD) | ✅ Runs it, scopes it | Use it to watch/sync *their* apps |
| Front door (ingress + LB) | ✅ The controller + LoadBalancer | ✅ **Their own ingress rules** (host/path) |
| Registry (OCIR) | ✅ Runs it, access | ✅ Push *their* images |
| Golden templates | ✅ Build + maintain the "paved road" | Fill in a few values |
| Guardrails (quota, netpol, PSA, RBAC) | ✅ Define + enforce | Live within them |
| Observability (metrics/dashboards) | ✅ Run the stack | ✅ View *their* app's metrics |
| Developer portal / UI | ✅ Build + run it | ✅ Use it to onboard + manage apps |
| **The app itself** | — | ✅ Code, image, config, secrets, replicas, deploys |

> The **interface** between the two = the golden template + the UI + the `gitops/<app>/` folder.
> App teams only ever touch a few values; they never touch cluster internals.

---

## 3. How an app team ships — the self-service flow

### Today (CLI — works now)
```
1. ./new-app.sh <app> <team> <image>     → generates gitops/<app>/ with all guardrails
2. create their secret out-of-band       → kubectl create secret (one-time)
3. git push                              → ArgoCD ApplicationSet auto-deploys
```

### Target (UI — fewer clicks, the vision)
```
1. Team opens the portal → clicks "Create New App"
2. Fills a short form: app name, image, replicas, ingress host/path, env/secrets
3. Clicks "Create"  → portal runs the template, opens a Git PR (or commits)
4. PR merged → ArgoCD deploys.  Team watches it go green in the same UI.
```
**Zero YAML by hand. Zero kubectl. Zero tickets to the infra team.**

---

## 4. What an app team controls (and what they don't)

They own everything inside **their** `gitops/<app>/` folder:
- **Image + version** (which build to run)
- **Replicas / scaling** (how many copies, HPA targets)
- **Ingress rules** — their own host/path routing (e.g. `myapp.qp.com → /`)
- **Config + secrets** (their `.env`, their pull secret)

They **cannot**: touch other teams' namespaces, exceed their resource quota, run privileged
pods, or change cluster-wide settings. The platform stops that automatically (Section 5).

---

## 5. Guardrails — so self-service ≠ chaos

Each app team gets an isolated "apartment", enforced by the platform:

| Guardrail | What it does |
|---|---|
| **Namespace per app/team** | Separate room — no name clashes, clean blast radius |
| **ResourceQuota** | "You get this much CPU/RAM" — one team can't starve others |
| **NetworkPolicy** | "Only your app talks to your DB" — tenant isolation *(needs a policy-enforcing CNI — see gaps)* |
| **Pod Security Admission** | Blocks privileged/root/no-limit pods at admission |
| **RBAC + ArgoCD Projects** | A team can only see/deploy **their own** apps in Git, the cluster, and the ArgoCD UI |

---

## 6. The UI layer (the "fewer clicks" piece)

Three building blocks, in order of adoption effort:

1. **ArgoCD UI (we already have this)** — app teams *watch + sync* their apps. Scope it per team
   with **ArgoCD Projects + SSO** so each team sees only their own apps. Good for *managing*,
   not for *creating* apps.
2. **A thin self-service portal (custom web form)** — a small web app: form → runs the golden
   template → opens a Git PR. Closes the "create a new app with zero YAML" gap fastest, low effort.
3. **Backstage (the strategic target)** — the industry-standard developer portal (CNCF). Its
   *Software Templates* give true one-click app scaffolding, a *catalog* of every app/owner, and
   per-team scoped views. Heaviest to stand up, but it *is* the canonical answer to this exact
   vision. (Alternative: **Port** — a faster-to-adopt hosted IDP portal.)

**Recommendation:** ArgoCD-UI-scoped now → thin custom portal for onboarding → Backstage/Port
when the number of teams justifies the investment.

---

## 7. Current state vs target (gap analysis)

**Already built ✅**
- OKE cluster (managed Kubernetes)
- ArgoCD + **ApplicationSet** (auto-discovers `gitops/*` → one app per folder = the self-service spine)
- Golden templates (`new-app.sh` + `base/*.tmpl.yaml`)
- Per-app isolation (namespace + ResourceQuota + NetworkPolicy + RBAC) + Pod Security baseline
- OCIR registry, ingress-nginx + public LoadBalancer, metrics-server
- One real app (instant-answers) live + healthy; ArgoCD UI exposed

**Gaps to reach the full vision ❌**
- **Per-team RBAC scoping** — cluster RBAC + **ArgoCD Projects** + ArgoCD SSO so teams are walled off
- **Self-service UI for onboarding** — thin portal or Backstage (Section 6)
- **Git access model** — per-team folders with CODEOWNERS, or a repo per team
- **Secrets self-service** — Sealed Secrets or OCI Vault so teams manage secrets safely (no kubectl)
- **CI/CD** — auto build+push image on app-repo push (today the image step is manual)
- **NetworkPolicy enforcement** — current Flannel CNI does NOT enforce policies; needs Calico / OKE's network-policy add-on
- **Observability** — Prometheus + Grafana so teams self-serve their app metrics/alerts

---

## 8. Roadmap (phased)

- **Phase 1 — Foundation (DONE):** OKE + ArgoCD + ApplicationSet + golden templates + 1 real app + ArgoCD UI.
- **Phase 2 — Multi-tenancy hardening:** ArgoCD Projects + SSO + per-team RBAC + Git CODEOWNERS + enforced NetworkPolicy (Calico) + Sealed Secrets.
- **Phase 3 — The portal (the UI):** thin self-service form first, then Backstage/Port — one-click onboarding, app catalog, scoped views.
- **Phase 4 — Full automation:** CI/CD image pipeline, Prometheus/Grafana, Cluster Autoscaler.
- **Phase 5 — Infra as code:** the cluster itself via **Terraform** (already in `terraform/`), so the whole platform is reproducible.

---

## 9. Architecture (target)

```
                          ┌─────────────────────────────────────────┐
   App teams ──UI/form──▶ │   Developer Portal (Backstage / custom)  │
   (self-service)         │   "Create app", catalog, scoped views    │
                          └───────────────────┬─────────────────────┘
                                               │ opens PR / commit
                                               ▼
                                   ┌──────────────────────┐
                                   │  Git: FoundryQP repo  │  ← single source of truth
                                   │  gitops/<app>/ per team│
                                   └───────────┬───────────┘
                                               │ watch (pull)
   ┌───────────────────────────────────────────▼──────────────────────────────────┐
   │  OKE cluster (PLATFORM TEAM owns)                                              │
   │   ArgoCD ──deploy──▶ team-a/ns   team-b/ns   team-c/ns   (isolated apartments) │
   │   ingress-nginx + LB (front door) · OCIR (images) · metrics/Grafana · guardrails│
   └───────────────────────────────────────────────────────────────────────────────┘
```

---

*The principle throughout: the platform team builds the paved road once; every app team drives
on it themselves. Self-service by default, guardrails by design, tickets by exception.*
