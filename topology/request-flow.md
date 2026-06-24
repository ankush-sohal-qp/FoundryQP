# Request Flow & Storage Layout  (PHASE 1, from DevOps training notes)

TRUST: from training notes (Ankush), reasoned + structured. UNVERIFIED until confirmed on boxes.

## The request flow (external)
```
Customer / whitelabel domain
      │  (DNS + TLS + custom hostname)
      ▼
  CLOUDFLARE  ──────────────  the real front door; whitelabel URLs resolved here
      │  HTTPS :443
      ▼
  NGINX (edge, public subnet)  ── reverse proxy / router
      │   decides WHERE to send the request based on host/path:
      ├──► WEB tier   (web1/web2)
      ├──► RUN tier   (run1/run2 — workers/jobs)
      └──► DATA tier  (data1)
              │
              ▼
        app ──► ProxySQL (:6033) ──► MySQL (db1/2/3, gldb1)
```
nginx is the **router/decider**: one public entrypoint, fans out to the right internal tier.

## Ports — the two nginx roles
- **:443 — public / external** access. Internet-facing requests come in encrypted over 443
  (terminated at Cloudflare and/or nginx). This is the customer-facing door.
- **:80 — internal**, used for **download requests on the internal nginx**. i.e. internal-only
  traffic (downloads, internal services) rides plain :80 on the internal nginx (nginxint1),
  which is not exposed to the internet.
- Takeaway: there are effectively TWO nginx roles — public edge (443, external) and internal
  (80, downloads / internal). Don't conflate them. VERIFY exact vhost/port mapping with `nginx -T`.

## Storage layout — two disks, deliberate split
Each box has **two volumes** (`sda` and `sdb`), and the split is intentional:

| Volume | OCI type      | Mounted as          | Holds                                        |
|--------|---------------|---------------------|----------------------------------------------|
| sda1   | **Boot volume**  | `/` (OS root)    | OS + **nginx** ("nginx is always on OS data")|
| sdb    | **Block volume** | data mount       | **application data** (app payloads, DB data) |

Key rules from the notes:
- **"We don't have data on disk storage"** = no application DATA sits on the boot/OS disk.
  The OS disk is OS + nginx only. App data lives on the separate block volume.
- **Boot volume** = OS + nginx config/binaries. **Block volume** = application data.
- Why this matters operationally:
  - You can detach/snapshot/grow the data (block) volume independently of the OS.
  - Rebuilding a box's OS doesn't risk the app data (different volume).
  - **nginx living on the boot/OS volume** means nginx config is part of the OS image lifecycle,
    not the data volume — consistent with config-as-code (config comes from git, not the data disk).
- **Block volumes are encrypted** (per the earlier sheet's "Data Disks (encrypted)" column).

## NFS — shared volumes
- **NFS = shared volume** mounted across multiple boxes (e.g. web1+web2 share the same files,
  uploads/exports visible to all app nodes). This is how a multi-node web tier serves the same
  content and why the sheet tagged the web tier "WEB/NFS/API".
- Operational watch-outs (carry into observability): an NFS stale/unmounted condition silently
  breaks the app; a root-level `find /` traverses NFS and hangs. Alert on NFS mount health.

## Shape / CPU sizing (open question)
You asked "how much CPU required" — that's a per-tier sizing decision, not a single number.
Current sheet baseline: app tiers 4cpu/8GB, DB 4cpu/16GB, nginx-internal/edge-secondary 2cpu/4GB.
Real sizing = driven by observed load (Phase 2 metrics tell you if 4cpu is right or wasteful).
Don't guess shapes before you can SEE utilization. Record the question, answer it with data.

## CI/CD note — Jenkins
- **Jenkins "Batch 3"** is used for **per-node, data-related builds** (individual node builds for
  data jobs). So the build/deploy tooling here is **Jenkins**, not (or in addition to) the
  GH-Actions-style flow assumed earlier. This is a concrete correction to the deploy-mechanism
  question — VERIFY: is nginx config-as-code also Jenkins-driven, or separate? (access/deploy-mechanism.md)

## UNVERIFIED — confirm on boxes / with owner
- [ ] Exact host/path -> tier routing rules in nginx (`nginx -T` on edge + internal).
- [ ] Is TLS terminated at Cloudflare, at nginx, or both (end-to-end)?
- [ ] Block-volume mount path and filesystem; which tiers mount NFS and from where.
- [ ] Jenkins scope: does it also deploy nginx config, or only app/data builds? Batch 1/2 vs Batch 3?
