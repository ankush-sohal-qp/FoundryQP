# FoundryQP

**An internal platform that turns "deploy my app" into a single `git push`.**

Build the road once. Then every team drives on it themselves — no tickets, no hand-written
YAML, no pinging the infra team at 2am to ship a change.

---

## The one idea (read this and you get 80% of it)

You don't *deploy* apps here. You *describe* them in Git, and the platform makes reality match.

```
edit a file  →  git push  →  app is live on the cluster
```

A controller called **ArgoCD** watches this repo around the clock. Whatever is written in
`gitops/` is exactly what runs on the cluster. Change a file → it deploys. Someone fiddles with
the cluster by hand → it quietly heals it back to match Git. Git is the single source of truth,
full stop.

No `kubectl`. No manual steps. No "it works on my machine."

---

## This isn't a slide. It's running.

A real app — `instant-answers` — is already live on the cluster, deployed entirely through this
flow and talking to its own database. Not a mockup, not a diagram — an actual workload you can
hit over HTTP, watch in the ArgoCD dashboard, and scale up or down. The live endpoints aren't
hardcoded here (they move with the environment) — grab the current ones from the platform team
or the ArgoCD dashboard.

---

## How it actually works (30-second version)

```
   YOU                         GitHub                    CLUSTER (Oracle Cloud / OKE)
 ┌────────────┐   git push   ┌────────────┐   watch    ┌──────────────────────────┐
 │ edit gitops/│ ───────────▶ │  FoundryQP │ ◀───────── │  ArgoCD  →  deploys apps │
 │ on laptop   │              │  (this repo)│            │  each app in its own room│
 └────────────┘              └────────────┘            └──────────────────────────┘
```

- **You** edit a file and push.
- **GitHub** holds the desired state (this repo).
- **ArgoCD** lives *on* the cluster, *reads* from GitHub, and *deploys* to the cluster.

---

## Shipping a new app (the paved road)

One command scaffolds everything — health checks, resource limits, network policy, security
hardening, the works. You don't hand-write 18 files and hope you didn't miss a guardrail.

```bash
# 1. Generate the app's setup (creates gitops/<your-app>/)
./k8s-lab/template/new-app.sh  my-app  my-team  bom.ocir.io/<ns>/my-app:v1

# 2. Give it its secrets (these stay OUT of Git, on purpose)
kubectl create namespace my-app
kubectl create secret generic my-app-env -n my-app --from-env-file=my.env

# 3. Push. That's the deploy.
git add gitops/my-app && git commit -m "ship my-app" && git push
```

ArgoCD notices the new folder, creates the app, and rolls it out. Done.

> **Rule of thumb:** one folder under `gitops/` = one app. Add a folder, push, you have a new app.
> Delete the folder, push, it's gone. The folder *is* the app.

---

## Updating an app

New code → build a new image with a new tag → flip one line in Git:

```bash
# after you've built + pushed my-app:v2 to the registry:
# in gitops/my-app/04-app.yaml change   ...:v1   →   ...:v2
git commit -am "my-app: deploy v2" && git push
```

ArgoCD does a rolling update — old pods keep serving until the new ones are healthy. Zero downtime.

---

## Why it doesn't turn into chaos

Every app gets its own walled-off apartment, enforced by the platform — not by trust:

- **Its own namespace** — no name clashes, clean blast radius.
- **A resource quota** — one greedy app can't starve the rest.
- **A network policy** — only your app talks to your database.
- **Pod security rules** — rootful / privileged / no-limit pods get rejected at the door.

So teams can self-serve freely, and still not step on each other.

---

## What's in here

```
gitops/                 ← the live desired state. ArgoCD watches this.
  _appset.yaml            the "watchman" — turns every folder below into a running app
  instant-answers/        our live app (deployment, mysql, service, ingress, policies)
k8s-lab/
  template/new-app.sh     the one command that scaffolds a new app
  template/base/          the golden templates every app is built from
  platform/               shared platform bits (postgres, redis, etc.)
terraform/              ← the cluster itself as code (reproducible infra)
PLATFORM-VISION.md      ← where this is headed (full Internal Developer Platform)
```

---

## Who does what

- **Infra team** runs the *platform*: the cluster, ArgoCD, the front door (ingress + load
  balancer), the registry, and the golden templates.
- **App teams** run their *apps*: their code, image, config, ingress rules, scaling, and deploys —
  all self-service through Git (and soon, a UI).

Nobody files a ticket to deploy. That's the whole point.

---

## Under the hood

Oracle Kubernetes Engine (OKE) · ArgoCD (GitOps) · OCIR (image registry) · nginx ingress +
OCI load balancer · Terraform (infra as code). Region: Mumbai.

---

## Where this is going

Right now it's a working platform with one real app on it. The plan is to make it a full
**Internal Developer Platform** — a UI for teams to onboard apps in a few clicks, per-team
access control, automated image builds (CI/CD), and dashboards. The full blueprint lives in
[`PLATFORM-VISION.md`](./PLATFORM-VISION.md).

*Build the road once. Let everyone drive.*
