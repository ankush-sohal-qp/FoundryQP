This is a writing/synthesis task. The answer is the deliverable itself — no tools needed, nothing to run against a fleet the engineer can't yet touch. Here it is.

---

# The 10X SRE Battle-Plan for the Mumbai Fleet

You're a strong dev, new to big-infra SRE, onboarding with read-only-assumed authority. Read this once end-to-end before you do anything.

The single most important thing I can tell you: **your edge is not that you'll SSH faster than the current team. Your edge is that you'll move the fleet's knowledge out of people's heads and `~/.bash_history` into version-controlled, queryable, testable artifacts — and you'll make the invisible failure modes visible *before* they page.** That's the whole game. Everything below serves that.

And the second most important thing, which four separate adversarial reviews hammered: **almost every "obvious" first move in the raw research silently assumes access you do not have yet.** SSH to 28 boxes, `nginx -T`, `SHOW SLAVE STATUS`, installing node_exporter fleet-wide, creating an OCI state bucket, *tagging prod resources* — those are all writes or privileged reads. The org reality (YouTrack ticket flow for env vars, one infra owner, prod read gated) means your day-1 authority may be "a bastion and a couple of QA boxes," or even less. So the plan is gated, hard, on confirming access before each step — and it front-loads the things that are genuinely zero-authority.

---

## The core strategic insight

A hand-managed fleet has no map. The map lives in the current team's heads. **The unlock is replicating that map into a single, version-controlled, AI-readable source of truth — built from *measured* reality, not from assumptions — and then wiring it so it screams when reality and the map disagree.**

Everything flows from that one artifact:
- The SPOFs, the EOL software, the unmonitored boxes, the reboot-won't-survive landmines — they all *fall out* of building the map.
- Drift detection is just "diff the map against reality on a schedule."
- The AI infra-copilot is just "make the map conversational."
- Your credibility with the infra owner is "here's the as-built map and risk list nobody had written down" — which is how a read-only newcomer earns hands.

But — and this is the discipline the reviews demanded — **the map must be measured, not transcribed from this brief.** The brief says "likely replication," "ProxySQL pooler," "pulled onto boxes somehow." Those are hypotheses. ProxySQL might already be clustered. A replica might be writable (split-brain). You verify each one by *reading the box* before you write it down as fact. Never assert without reading. If you can't read it yet, it stays marked `UNVERIFIED` in the map.

---

## Why this phase order (and why observability before heavy IaC)

```
Phase 0  Access + Discovery        (zero-authority, days)
Phase 1  Knowledge Map / Risk List (read-only, week 1-2)   <- the unlock
Phase 2  Observability             (one pilot box, then roll via existing flow)
Phase 3  IaC control plane         (QA first, db last, needs granted authority)
Phase 4  The 10X differentiators   (built ON the map: drift, restore drills, copilot)
```

**Observability comes before heavy IaC, deliberately.** You cannot safely automate what you cannot see. If you start importing prod into OpenTofu and running converges before you have replication-lag, disk, and 5xx visibility, your first real `apply` could break something and you'd find out from a customer, not a graph. Observability is also lower-risk (passive scrapers, read-only exporters) and directly serves the engineer's stated "observable" goal. IaC is the higher-authority, higher-blast-radius work — it goes after you can watch the fleet and after you've earned per-env apply rights.

The reviews are unanimous on the within-phase rule too: **QA/LABS (10.13) first, then OPS (10.12), then PROD (10.11) last — db tier dead last of all.** You validate every unfamiliar command and every playbook on the throwaway env before it ever sees prod.

---

# Phase 0 — Access + Discovery

**Goal:** Know exactly what you're allowed to touch, as whom, and reverse-engineer the existing deploy mechanism — all without changing a single thing.

This phase is the one the raw research skipped and every reviewer flagged. Do not skip it.

### Deliverables
1. **An access inventory.** For each box/system: can I SSH? as what user? what does `sudo -l` say I can do? Do I have *any* OCI read API (`oci iam compartment list` returns data or 401)? Is there a bastion? The honest output is often "I can reach QA, I have a read-only SQL script for prod, everything else is a ticket." Write that down — it defines the whole rest of the plan's pace.
2. **The deploy-mechanism answer.** "Configs live in GitHub, pulled onto boxes somehow" — *somehow* is answerable by one conversation with the infra owner plus reading the config repo's `.github/workflows/`. It's one of: GH Actions + SSH/rsync (push), Ansible push, a webhook listener (`:9000`, `hooks.json`), a cron `git pull`/`ansible-pull`, or a hand-run `deploy.sh`. **You must know this before Phase 3** — because that existing puller is a *live writer*, and if you later point Ansible at the same nginx files without disabling it, you get a reload-fight outage. This is the single most important as-built fact to nail.
3. **A one-page authority + ownership note.** Not a RACI framework — one sentence of policy ("PR-only, no box edits, ask before anything stateful") plus a table: per tier, who owns it, what's the deploy path, safe-for-me-to-touch Y/N/ask. Capture the real escalation path (the infra owner, the YouTrack format) — don't invent per-host "owner" fields.
4. **Use OCI-native Monitoring as your first, truly-zero-write visibility.** The OCI Compute agent is very often *already installed and emitting* CPU/mem/disk/network. Reviewer-confirmed: this is the one observability win that requires no install, no permission, no risk. Open the OCI console, look at what's already there. This is your day-1 dashboard while you earn the right to install exporters.

### Exact tools
- `oci` CLI read calls (if you have the key) / OCI console.
- `sudo -l`, `id`, `groups` on whatever you *can* log into.
- The config repo, cloned and grepped read-only.
- A conversation with the infra owner. This is a tool. Use it. In a small single-owner shop, "collaborate with the owner" beats "build a shadow control plane to outshine him" — the latter is a relationship-destroying frame that gets your access revoked.

### What NOT to do
- **Do NOT `nmap` the fleet.** Targeted `nc -z` from a box you're authorized on, if anything. A port-scan on day 2 is how you get flagged as the threat.
- **Do NOT run root-level `find / -maxdepth 5/6`** on prod — it traverses NFS mounts, generates real prod I/O, and hangs on stale mounts. If you must search a filesystem, scope it (`/etc/nginx`, `/home/*/.pm2`), never `/`.
- **Do NOT assume `pm2 startup` is read-only** — its behavior is version-dependent. Use `systemctl list-units | grep pm2` to learn boot-survival state instead.
- **Do NOT tag prod OCI resources.** (The knowledge-layer research called tagging "the headline win" — it's a *prod write*. It comes much later, as a reviewed change, if at all.)

### Done when
You can state, in writing: what you can access, the exact deploy mechanism end-to-end, who owns each tier, and you have OCI-native dashboards open for the boxes that already report. Zero changes made.

---

# Phase 1 — The Knowledge Map + Risk List

**Goal:** A measured, version-controlled, AI-readable as-built map of the fleet plus a ranked risk list. This is *the unlock* and it's the deliverable you show in week 2.

### Deliverables
1. **A `fleet-inventory` repo** (structure at the end of this doc) with two clearly-separated trust layers:
   - **FACTS** (machine-generated where possible): hostname, IP, env, tier, shape, what's listening, what's running, versions. If you have OCI read API, generate this with the **OCI Ansible inventory plugin** (`ansible-inventory --graph`) — it's read-only and reproducible. Critical gotcha: the plugin defaults to discovering only *public-IP* hosts; your fleet is almost all private, so you **must** set `hostname_format_preferences` to include `private_ip` or you'll see 3 of 28 boxes. If you have no OCI API yet, derive groups from the IP octets (2nd=env, 3rd=tier) — the scheme *is* your spec.
   - **MEANING** (hand-authored, the WHY): a flat YAML edge-list of dependencies keyed by *logical role* (not IP, so it survives re-IPing): `web → proxysql → mysql`, `run → redis`, plus a `blast_radius` and `why` field per critical node. This is the part no cloud API knows and the highest-value thing for both humans and an LLM.
   - **Every edge in the MEANING layer is measured before it's written.** `web→proxysql→mysql`: confirm by grepping app config for `:6033`/`proxysql1`. Replication topology: `SHOW SLAVE STATUS\G` (5.7 syntax — *not* the 8.0 `REPLICA` aliases) on each db node, stitch `Master_Host` (points up) against the primary's `SHOW SLAVE HOSTS` (points down). ProxySQL writer/reader split: SELECT-only on admin port `:6032` from `mysql_replication_hostgroups` + `runtime_mysql_servers` (trust `runtime_*`, not the base tables which can be stale). **Then cross-check ProxySQL's writer hostgroup against the actual MySQL primary — if they disagree, you've found a real bug.** Anything you can't measure yet is tagged `UNVERIFIED`.
2. **A ranked risk list.** This is where you earn authority. The likely top entries (each marked verified/unverified, with evidence):
   - **MySQL 5.7.38 is EOL (since Oct 21 2023).** No security patches for ~2.5 years; every MySQL-core CVE since is unpatched. This belongs near the *top* of the risk list, not silently transcribed. The 10X play is NOT "upgrade tomorrow" — it's: document the CVE exposure, then build and prove a tested 5.7→**8.4 LTS** (not 8.0, which is itself near EOL) or **Percona Server** upgrade runbook in LABS. De-risk it, then propose with evidence.
   - **proxysql1 is a likely SPOF** in front of all MySQL — *if* it's single-node (verify; it may already be paired/clustered). If single, it's probably the scariest availability risk on the fleet.
   - **Reboot-survival landmines:** boxes managed by hand often lack a `pm2-<user>.service` systemd unit / current `pm2 save` dump, or docker containers without `restart: unless-stopped`. These come back *empty* after a reboot. Catalog which boxes won't survive a reboot — highest-value finding you can produce changing nothing.
   - **Backup reality unknown:** `backupdb1` existing ≠ restorable. Flag "restore never tested" as a risk (Phase 4 proves it).
   - **Replication health unmonitored:** it could be broken *right now* and nobody would know until a failover. Also check `read_only=ON` on replicas — a writable replica is a split-brain footgun.
   - **Secrets flow:** map where DB/ProxySQL/app creds live and how they reach boxes. NOTE — the differentiator research claimed `password=synthetic_data_password` proves plaintext prod secrets; that line is prefixed `Local:` and is a dev placeholder. The docs actually show prod secrets are gated via the infra ticket flow. **Do not repeat that misread.** Still worth a `gitleaks` history scan of the config repos, but lead with the verified picture, not a false alarm.
3. **A topology diagram** rendered from the YAML. Use a **Mermaid block in a markdown file** (GitHub renders it natively) — *not* a `dot → SVG → CI` pipeline for five edges. That's ceremony.

### Exact tools
- OCI Ansible inventory plugin (facts, if API access) or octet-derived groups.
- Hand-authored YAML for the dependency graph.
- `gitleaks` for the history scan.
- Read-only SQL on MySQL (`SHOW SLAVE/MASTER STATUS`) and ProxySQL admin (`:6032`, SELECT-only — never `LOAD ... TO RUNTIME`).

### What NOT to do (consciously, for a 28-VM single-region fleet)
- **NOT NetBox / Diode / NetBox Assurance.** It's a Postgres+Redis+Django app sized for racks/cabling/hundreds of devices. You'd run more operational surface than the thing it documents. Write one decision-doc line: *"NetBox evaluated, deferred until >100 devices / physical-DC / multi-region / >1 maintainer."*
- **NOT Steampipe / CloudQuery / a graph DB.** Built for hundreds-to-thousands of resources and compliance reporting. A flat YAML repo + `git diff` beats them at 28 VMs.
- **NOT a multi-artifact build pipeline as the *starting* deliverable.** The knowledge-layer research proposed inventory.json + topology.yml + generated join + per-host stubs + SVG + llms.txt + Makefile-with-4-targets + 6-dir repo *before a single fact is verified*. That's a documentation product, not an SRE map. Start with the measured map + risk list. Add generation/rendering once facts are real.
- **NOT committing raw OCI API JSON as a "drift alarm."** It's dominated by ephemeral fields (timestamps, boot times, states) and will produce constant false-positive "drift" with no normalization layer. Real drift here is *config* drift (nginx/pm2/replication), which is Phase 4 — not OCI-resource drift on a fleet nobody is Terraforming yet.
- **NOT an MCP server / llms.txt yet.** A well-named folder is enough for one reader at this scale. MCP comes in Phase 4 only if you're querying daily.

### Done when
The repo contains a measured map (UNVERIFIED items clearly marked), a ranked risk list with evidence, and a Mermaid topology diagram — and you've shared it with the infra owner as "here's my understanding, correct me." That last step surfaces wrong assumptions cheaply and is how you build trust.

---

# Phase 2 — Observability

**Goal:** Make the invisible failure modes visible. Highest-leverage, lowest-risk path to "10X observable." Comes before heavy IaC because you can't safely automate a fleet you can't watch.

### The pick
**Prometheus + Grafana + Alertmanager** on one dedicated `mon1` VM in **OPS (10.12)** — never in prod's blast radius, never in unstable LABS. Exporters are passive listeners; scraping is pull-based; everything is config-as-code, matching how this team already runs nginx. Logs (Loki) come *later* — it's the second project, not a co-equal pillar.

### The sequencing the reviews forced (this is non-negotiable)
The raw research labeled "install Netdata + node_exporter on all 28 boxes" as "week-1, read-only." **It is not read-only** — installing daemons, opening ports, and adding systemd units are *writes on prod boxes you don't own.* Inverting safe sequencing here is exactly the arrogance that gets a new hire's access pulled. Correct order:

1. **OCI-native first** (Phase 0 already gave you this) — zero-write baseline visibility today.
2. **Stand up `mon1` in OPS** with Prometheus + Grafana + Alertmanager. This is *your* box in the safe env — fine to build.
3. **Instrument ONE non-prod box (QA/LABS) end-to-end** as a reviewed, reproducible pattern: node_exporter + the relevant tier exporter, scrape config, a dashboard, an alert. This is your pilot. It proves the pattern without touching prod.
4. **Only after sign-off, roll node_exporter to prod tier-by-tier via the team's existing config-as-code flow** — not snowflake SSH installs. The single write-authority the whole stack needs is the security-list rule allowing `mon1 → exporter ports` from mon1's IP only. Request *that*, explicitly.

### Exporters (all passive, read-only-safe)
- Every VM: `node_exporter`.
- db1/2/3, gldb1, backupdb1: `mysqld_exporter` (dedicated monitor user: `REPLICATION CLIENT, PROCESS, SELECT` only — no writes; store that credential carefully, not in git).
- proxysql1: **check first whether ProxySQL 2.x exposes native Prometheus metrics on the admin port** — simpler than the separate `proxysql_exporter` binary. Don't assume the exporter; verify the version.
- nginx (edge + per-env): `nginx-prometheus-exporter` via `stub_status` (a 3-line config add through the existing flow). **NOT the VTS module** — it requires recompiling nginx, a heavy fragile write on prod edge boxes. Get per-vhost 5xx from log parsing instead.
- docker1/2/3: `node_exporter` + a lightweight container-up/restart probe. **NOT cAdvisor** — its per-container firehose is high-cardinality overkill for "is it up / is it restart-looping" on 3 hosts.

### The first alerts that matter for THIS fleet
Ordered by "invisible-until-disaster":
1. **MySQL replication broken** (`slave_sql_running==0` or `slave_io_running==0`) → page. **Lagging** (`seconds_behind_master > 30 for 5m`, sustained — it spikes on big transactions, so alert on *sustained*) → ticket. This is the #1 invisible risk.
2. **ProxySQL backend SHUNNED/down** → page. The funnel for all app DB traffic.
3. **nginx 5xx spike** (>5% for 5m) → page on prod edge. Fastest user-facing-pain signal for a survey product.
4. **DB disk** (`predict_linear` full-in-4h, or <10%) → page. Disk-full = MySQL crash + corruption.
5. **pm2/worker crash-loop** (restart count climbing) → page. A looping worker looks "up" but processes nothing.
6. **NAT/egress down** (probe external through the per-env NAT) → page. Invisible to host metrics; breaks webhooks/mail/cert renewal.
7. **Backup STALE** (`time() - backup_last_success_timestamp > 26h`) → page. Alert on *staleness of a timestamp*, not a pushed "failed" metric (pushed metrics never expire and go stale silently). Textfile/Pushgateway pattern.
8. **TLS cert expiry** (`< 14d` ticket, `< 3d` page) via blackbox_exporter.
9. **Host down / OOM / high load** — free from node_exporter.
10. **Watchdog deadman** — a constantly-firing alert routed so it pages you when it *stops*. Plus an **OCI alarm** as the external dead-man's-switch for mon1 itself — you can't watch your own watcher from inside.

### What NOT to do
- **NOT SLOs + multi-window burn-rate alerting yet.** You cannot set a credible 99.5% target without weeks of baseline you don't have. Collect edge 5xx + latency for 30 days *first*, then discuss SLOs. MWMBR is a month-3+ topic.
- **NOT ELK / Thanos / Cortex / Mimir / Prometheus HA pairs.** One Prometheus is fine at 28 targets. Loki+Alloy (Promtail is deprecated — use **Alloy**) for logs is month 2-3, and watch mon1's RAM/disk when both Loki ingestion and 90-day Prometheus retention land — "split out when it grows" arrives faster than you'd think; size mon1 with headroom.
- **NOT VictoriaMetrics from day one.** Adopt it only when retention/cardinality actually hurts.
- **NOT Kubernetes to "run the monitoring stack."** It's 4 binaries on a VM.

### Critical things the research missed — do these
- **Secure mon1's web UIs.** Prometheus, Alertmanager, and Grafana have *no auth by default*. On a flat VCN, an unauthenticated Grafana is data-exfil + lateral-movement waiting to happen. Put auth on Grafana, bind Prometheus/Alertmanager to non-public interfaces, restrict by security-list.
- **Back up mon1's state as code.** Grafana dashboards and Alertmanager config live in git (provisioned, not clicked). Prometheus TSDB is ephemeral by design — accept that history is lossy, but never lose your *config* with the box.
- **PII / data governance.** This is a survey product holding respondent PII (GDPR / India DPDP). nginx access logs (IPs, query strings, tokens) and MySQL slow/error logs routinely contain PII/secrets. Before centralizing logs in Phase 2.5, have a redaction/retention answer. This alone is a reason logs come *after* metrics.
- **Runbooks + on-call reality.** An alert with no runbook and no defined recipient is noise. Don't wire pages to yourself at 3am for a fleet you don't yet understand and can't fix. Each alert links to a "what to do" doc; confirm the real escalation policy first.

### Done when
mon1 is up and secured in OPS, one QA box is fully instrumented as a reviewed pattern, node_exporter + the replication/disk/ProxySQL alerts are live on prod (rolled via the existing flow, post sign-off), and OCI watches mon1.

---

# Phase 3 — IaC Control Plane

**Goal:** A reproducible model of the fleet where `plan`/`--check` shows **zero changes** — i.e., the code matches reality so exactly that adopting IaC mutates nothing. This is higher-authority work; it comes after you can see the fleet and after you've earned per-env apply rights.

The mental model, drilled in by the IaC review and correct: **import does not change infrastructure — it teaches the tool what already exists. A resource is "done" when its plan is empty. Nothing gets recreated.**

### The tool decision — and a factual correction the IaC research got wrong
The IaC research recommended **OpenTofu** and then spent its longest section fighting OCI state-locking. Those two facts are causally linked and it never connected them:

- **Terraform now has a native `oci` state backend** (Terraform v1.12+) with built-in locking via OCI Object Storage's `If-None-Match` conditional writes. Oracle **deprecated** the S3-compat backend.
- **OpenTofu does NOT have the native `oci` backend** (issue #1011, still open as of 2026). Choosing OpenTofu forces you onto the deprecated S3-compat path and the `use_lockfile` uncertainty.

**So for THIS fleet, use Terraform** — the native `oci` backend means locking works out of the box and the entire "ScyllaDB+API-Gateway DynamoDB lock rig" strawman (genuinely absurd for 28 VMs) evaporates. This is the one place I'm overriding a layer's headline recommendation: OpenTofu vs Terraform is *not* a wash here; the native backend is a real Terraform-only advantage for exactly this setup. (If your org later mandates OpenTofu, it's a `s/terraform/tofu/` migration and you revisit locking then.)

### The honest authority sequencing
The "Phase 0 is fully read-only" promise from the IaC research is **false the moment you use a remote backend** — creating the state bucket + IAM policy is a *write* needing real authority. So:
- Phase 3 discovery and config generation use **local state** (or `plan` with generated config, no backend).
- **"Authority to create the state bucket" is an explicit, narrow first ask** — not assumed.

### Two-tool split (keep this in your head)
- **Terraform** = provisions VMs/network (the "what exists").
- **Ansible** = configures what's *on* the boxes (nginx/proxysql/mysql/app — the "what's installed"). Agentless (SSH only — nothing new on 28 boxes), `--check --diff` is first-class, de-facto standard for config-as-code-onto-VMs.

### Deliverables, in order
1. **Terraform: import QA (10.13) first** using **`import {}` blocks** (reviewable in a PR, plannable) — not the old CLI. Import in dependency order: compartment → VCN → subnets → security lists/route tables → NAT/IGW → instances → public IPs. Use `plan -generate-config-out` to draft HCL, then clean it until `plan` shows no changes. Put `prevent_destroy = true` on db tier, VCN, NAT, mail's public IP, backup host, and the state bucket *immediately* on import. Then OPS, then PROD. Per-env directories, **not workspaces** (separate state = blast-radius isolation; with 3 envs the copy-paste is trivial and the safety is worth it).
2. **Ansible: wrap the existing nginx config-as-code, don't rewrite it.** The current files become the role's `templates/`; add `validate: nginx -t %s` *before* reload and a reload-only-on-change handler. You've added test-before-reload, idempotency, and web1/web2 consistency without changing a directive. **But first — disable the existing puller on any host Ansible will co-manage**, or you get the reload-fight outage. This is the concrete hazard the research glossed.
3. **Add a smoke-test-after-reload**, not just `nginx -t`. `-t` won't catch a config that passes syntax but 502s. Keep last-known-good and `curl` the healthcheck in the handler; revert in 30 seconds if it fails.
4. **MySQL is the scary one — treat the my.cnf as part of the replication contract.** Manage `my.cnf` and users/grants via Ansible, but put `server-id`, `log-bin`, `read_only`, and `gtid` keys under `ignore_changes` / an explicit "never touch" list — a my.cnf diff that flips `read_only` or `server-id` on a replica breaks replication on next restart, and bouncing a backend shifts ProxySQL routing. **Capture existing replication topology + binlog/GTID positions + per-host server-id BEFORE importing anything.** Replication topology changes stay a supervised, documented, manual runbook operation — never a routine converge. db tier gets a maintenance window before any real apply, ever.

### CI/CD
- **PR → `plan` / `--check --diff` → posted as a PR comment → merge → apply.** Plan-on-PR is safe to enable while read-only (needs only read perms). Apply consumes the *saved plan artifact* (`plan -out=tfplan` → `apply tfplan`) so you apply exactly what was reviewed.
- **GitHub Environments** for gating: ops/qa can auto-apply; **`prod` requires a named reviewer's manual approval**. Branch protection on `main`. A `concurrency` group per env serializes applies.
- Auth: **a single least-privilege service user with a rotated API key in GH secrets is completely fine** for a 2-person ops team. Note OIDC/Workload Identity Federation as a someday-nice-to-have — *one line*, not a design section. It requires creating an Identity Propagation Trust you have no authority to build and don't need at this scale.

### The pm2 question (deferred, not ignored)
Long-term, **systemd units beat pm2** here: nginx already load-balances across web1/web2, so you don't need pm2's cluster mode; systemd gives you real cgroup caps (`MemoryMax`, `CPUQuota`), `Restart=on-failure`, journald logs, and a *declarative* unit file in git instead of imperative `pm2 save` drift. **But the migration is Phase 3.5+, not now.** First codify the *current* pm2 setup in Ansible as-is (template the ecosystem file, role-driven `pm2 startup`+`save`) so it's reproducible and changes runtime behavior zero. Then migrate role-by-role, starting with RUN workers (run1/2) — background, no nginx-upstream subtlety. Don't reach for Kubernetes/Swarm; containers-via-systemd on docker1/2/3 is plenty.

### What NOT to do
- **NOT OpenTofu** (see above — costs you the native backend).
- **NOT the Scylla/API-Gateway lock rig, NOT Terragrunt** (3 env dirs don't need a DRY framework), **NOT k8s/Swarm/Nomad, NOT ansible-pull / Chef / Puppet / Salt** (push-from-CI is simpler and more visible until ~100+ nodes), **NOT a private module registry, NOT multi-region state, NOT Sentinel/OPA.**
- **NOT a custom plan-JSON deletion-count gate script.** `prevent_destroy` + branch protection + manual prod approval + human-reviewed plans already cover "oops, 9 resources." Drop the bespoke script until there's evidence it's needed.
- **NOT a 3-module abstraction (network/compute/tier with for_each) on day one.** Start flatter — per-env `.tf` referencing one shared compute module. The "tier wraps compute, for_each over tiers" cleverness bites a new-to-IaC engineer when a plan does something surprising. Extract the tier module only once duplication actually hurts.
- **NOT native state encryption as a launch requirement.** Bucket access control + versioning is the 90% win; client-side encryption adds key-management burden (lose the key = unrecoverable state) a new SRE can get wrong. Later hardening, not launch.

### Done when
QA is fully under IaC with empty plans, the prod approval gate + promote-QA→OPS→PROD runbook exists, and you've presented *that runbook* as the artifact when asking for prod apply authority — db tier last and behind a maintenance window.

---

# Phase 4 — The 10X Differentiators

**Goal:** Built *on top of* the map (Phase 1) and the observability (Phase 2), these are what move you from "competent" to "top-1%." None of them require write authority on prod; all are read/detect/explain.

### Ordered by leverage
1. **Config-drift detection** — turns "config-as-code" from a lie into the truth. The killer use of Ansible here is *not* (yet) to configure — it's to **audit**: `ansible-playbook --check --diff` on a schedule. Zero changes reported = no drift. For nginx specifically, hash `nginx -T` (fully resolved running config) against what the repo would produce — catches the "edited live at 2am, never committed" snowflake directly. **Detect-and-alert before auto-remediate** — auto-apply on a fleet you don't fully understand causes the outage you were hired to prevent. The metric that matters: drift MTTD < 24h.
2. **Backup RESTORE drill** — the single most credible thing you can build, and the highest "betting the company and don't know it" risk. Replication is NOT a backup (a `DROP TABLE` replicates in milliseconds). A backup never restored is Schrödinger's backup. **Start with a ONE-TIME MANUAL restore drill** into a scratch box to prove it's restorable at all, and *time it* — that's your real RTO (most shops' "1 hour RTO" is 6 hours of fumbling); backup-age-vs-now is your real RPO. Only *automate* the drill later (a scheduled restore → `mysqlcheck`/row-counts/`CHECKSUM TABLE` → PASS/FAIL metric). **Caveat the research missed:** restoring prod data into LABS exposes respondent PII into your least-stable env — that's a data-governance landmine; mask/scrub or restore into an access-controlled scratch instance, not open LABS. For 16GB+ DBs prefer **Percona XtraBackup** over mysqldump — *after* you've confirmed what `backupdb1` actually runs today (don't prescribe the tool before reading the current state).
3. **The AI infra-copilot over the map** — *this* is where your LLM strength is a genuine fleet advantage, not a demo, **but only once the map in Phase 1 actually exists and has real data.** Expose the inventory YAML + dependency edges + `nginx -T` dumps via a small MCP/tool layer that answers "what depends on db2?", "which boxes are EOL?", "blast radius if proxysql1 dies?", "which vhosts route to run workers?". At 28 nodes a human reads the YAML in 10 seconds — so the copilot earns its keep on the *harder* jobs: **log-summarization/incident-triage** (correlate nginx error + mysql slow + pm2 logs across boxes at 3am → likely cause + matching runbook), **drift explanation** (diff → English → "this added a rate-limit on /api, not in any PR — intentional?"), and **PR review of config changes** using the dependency graph as context. The hard rule: **AI on the read/explain/summarize/correlate side = huge leverage. AI on the write/apply side = liability.** No LLM auto-remediation, no chatbot that runs arbitrary SSH, no "AI anomaly detection" before you have basic threshold alerts.
4. **Runbook automation** — codify the tribal procedures (add-vhost, MySQL failover, rebuild data1/admin1/mail1/gldb1 singletons). Phase 1: write them down. Phase 2: make them idempotent playbooks. The metric: % of alerts with a linked runbook.

### Things to flag but NOT personally drive (they're above your authority / org-level)
- **Cross-region backup copy** (single Mumbai region = a region event loses prod *and* backups). Real RPO gap — flag it loudly in the risk list; it's an org capex/IAM/architecture decision, not your personal roadmap.
- **SSH bastion / least-privilege access** — use **OCI Bastion** (native, ephemeral, nothing to patch) if proposing one. **NOT Teleport** (a whole auth/proxy cluster for 28 boxes is overkill) and **NOT HashiCorp Vault dynamic creds** (heavy distributed system, new SPOF, new on-call — OCI Vault is the native zero-new-infra answer the research itself admitted, then ignored).
- **proxysql1 HA** (a pair + keepalived/VIP, or per-app-node ProxySQL) — propose *after* the map verifies it's actually single-node and *after* observability proves the blast radius.

### What NOT to do
- **NOT a DORA-metrics scorecard in week 2.** DORA measures a CI/CD delivery pipeline you neither own nor see yet; you can't baseline change-failure-rate on changes you don't make. It's performative from a read-only newcomer. The credible week-2 baseline is the *risk list* (0% drift detection, backups never restore-tested, N SPOFs, 1 EOL engine) with a trendline — facts you measured, not a delivery-pipeline framework you can't populate.
- **NOT a shadow control plane to "quietly outrun the team."** In a single-infra-owner org that frame is a self-inflicted wound. The 10X path is collaboration *with* the owner — your map and drills make *his* life easier, and that's how you earn hands.

---

# The project: `questionpro-infra` (separate repo)

Separate from QuestionProX — ops has a different cadence and audience. It carries QuestionProX's philosophy (self-contained files, WHY-not-just-WHAT, decision logs with "when to reconsider", generated files marked and never hand-edited, trust-level-per-directory) but reorganized for fleet/topology/runbooks. **This is the *target* shape — you grow into it; you do not scaffold all of it before facts are verified.** Start with `fleet/`, `topology/`, and `risks.md`; everything else accretes as the phases land.

```
questionpro-infra/
├── README.md                      # what this is, how it's generated, TRUST LEVEL per dir
│
├── access/                        # ── PHASE 0 ──
│   ├── authority.md               #   what I can touch, as whom, sudo -l results, OCI read Y/N
│   ├── deploy-mechanism.md        #   the "somehow" — exact pull path, the live writer to disable
│   └── ownership.md               #   per-tier owner + escalation (infra owner, YouTrack format)
│
├── inventory/                     # ── FACTS (machine-generated, DO NOT HAND-EDIT) ──
│   ├── fleet.oci.yml              #   OCI Ansible plugin config (private_ip in hostname prefs!)
│   └── inventory.json             #   generated snapshot (NOT used as a drift alarm — config drift is)
│
├── topology/                      # ── MEANING (hand-authored, MEASURED, the WHY-graph) ──
│   ├── topology.yml               #   services + edges + blast_radius + why; UNVERIFIED tags
│   ├── ip-scheme.md               #   10.1x octet convention decoded
│   └── topology.md                #   Mermaid block (GitHub renders it; no SVG/CI pipeline)
│
├── fleet/                         # ── per-host WHY-docs (self-contained) ──
│   ├── _generated.md              #   joined table (regenerated, header says GENERATED)
│   ├── proxysql1.md               #   role, blast radius, SPOF status (verified?), reboot-survival
│   ├── db1.md … gldb1.md          #   replication role, server-id, read_only, EOL note
│   └── nginx-edge.md
│
├── risks.md                       # ── THE RANKED RISK LIST (your week-2 deliverable) ──
│                                  #   MySQL 5.7 EOL, proxysql SPOF, reboot landmines, untested
│                                  #   backups, unmonitored replication — each verified|UNVERIFIED
│
├── observability/                 # ── PHASE 2 ──
│   ├── mon1.md                    #   what runs on it, how it's secured, dashboards-as-code note
│   ├── exporters.md               #   per-tier exporter + ports + the monitor-user grant
│   ├── alerts/                    #   the 10 alert rules (Prometheus/Alertmanager YAML)
│   └── runbooks/                  #   one per alert — alert links here ("what to do")
│
├── iac/                           # ── PHASE 3 ──
│   ├── terraform/
│   │   ├── envs/{qa,ops,prod}/    #   per-env dirs (NOT workspaces), local state first
│   │   ├── modules/compute/       #   start with ONE shared module; extract more only when it hurts
│   │   └── backend.md             #   native oci backend (Terraform v1.12+), bucket = first ask
│   └── ansible/
│       ├── inventories/{qa,ops,prod}/
│       ├── roles/{common,nginx,proxysql,mysql,app_pm2,docker_host}/
│       │   # nginx: validate nginx -t + smoke-test-after-reload handler
│       │   # mysql: server-id/log-bin/read_only/gtid under ignore_changes
│       └── site.yml
│
├── differentiators/               # ── PHASE 4 ──
│   ├── drift-check.md             #   ansible --check + nginx -T hash; MTTD target < 24h
│   ├── restore-drill.md           #   manual first (timed = real RTO/RPO); PII-masking caveat
│   └── copilot/                   #   MCP over inventory+topology (built only once map is real)
│
└── decisions/                     # ── same format as QuestionProX, "when to reconsider" ──
    ├── terraform-over-opentofu-native-oci-backend.md
    ├── yaml-sot-over-netbox.md
    ├── prometheus-over-oci-native-as-system-of-record.md
    └── observability-before-iac.md
```

Conventions carried over: every file self-contained (no "see other doc"); generated files header-marked GENERATED and never hand-edited; `README.md` states each directory's trust level (`access/` `topology/` `risks/` = intent/measured; `inventory/` = machine reality); decision logs always include a "When to reconsider" so the deferrals (NetBox, OpenTofu, OIDC, Vault, Teleport, SLOs) are documented as *deliberate*, not ignorant — that's the senior signal.

---

## The through-line

Phases 0-1 need **zero authority** and produce the artifact (measured map + risk list) that earns you everything else. Phase 2 is **low-risk and directly serves "observable"** — pilot on one box, roll via the existing flow after sign-off. Phase 3 is **higher-authority** — request it narrowly, per-env, QA-first, db-last, with the promote runbook as your proof. Phase 4 is **read/explain/detect** leverage built on top, never write-to-prod automation.

The deepest 10X isn't any tool on this page. It's **moving the fleet's knowledge out of heads and `bash_history` into version-controlled, queryable, testable artifacts that scream when reality drifts** — and doing it *with* the infra owner, measured-not-assumed, prod-last, every step. Do that and you don't outshine the team that's SSH'd into these boxes for years; you become the person who quietly made the whole thing legible.