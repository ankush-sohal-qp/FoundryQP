# Ranked Risk List  (PHASE 1 deliverable)

TRUST: each item is verified | UNVERIFIED with evidence. This is what earns you authority —
"here's the as-built risk list nobody had written down." Update status as you measure each.

These are HYPOTHESES from the infra mapping until measured on a real box. Do not assert them
as fact until the Evidence column is filled from reality.

| # | Risk | Status | Evidence / how to verify | 10X fix (deferred, not now) |
|---|------|--------|--------------------------|------------------------------|
| 1 | **MySQL 5.7.38 is EOL** (since 2023-10-21). ~2.5yrs of unpatched core CVEs. | UNVERIFIED (version per sheet) | `SELECT VERSION();` on each db node | Build & PROVE a 5.7→8.4 LTS (or Percona) upgrade runbook in LABS first, then propose with evidence. NOT upgrade-tomorrow. |
| 2 | **proxysql1 is a SPOF** in front of ALL MySQL traffic. | UNVERIFIED (may be paired) | Is it single-node? `SELECT * FROM runtime_proxysql_servers;` on :6032; ask owner | ProxySQL pair + keepalived/VIP, or per-app-node ProxySQL. After map + observability prove blast radius. |
| 3 | **Reboot-survival landmines** — pm2 apps / docker containers that come back EMPTY after reboot. | UNVERIFIED | `systemctl list-units | grep pm2`; `pm2 save` dump freshness; docker `restart:` policy | Codify pm2 in Ansible as-is (Phase 3), later migrate to systemd units. |
| 4 | **Backup never restore-tested** — backupdb1 existing ≠ restorable. | UNVERIFIED | Ask owner; check what tool/schedule; has a restore EVER run? | One-time MANUAL timed restore drill into scratch box = real RTO/RPO (Phase 4). PII-mask if restoring to LABS. |
| 5 | **Replication health unmonitored** — could be broken NOW, found only at failover. | UNVERIFIED | `SHOW SLAVE STATUS\G` (5.7 syntax) per replica: Slave_IO/SQL_Running, Seconds_Behind_Master | Replication-lag/broken alert is alert #1 in Phase 2. |
| 6 | **Writable replica / split-brain risk.** | UNVERIFIED | `SELECT @@read_only;` on each replica (should be ON) | — |
| 7 | **ProxySQL writer hostgroup may disagree with actual MySQL primary** (real routing bug). | UNVERIFIED | Cross-check `:6032` runtime_mysql_servers writer HG against the real primary | — |
| 8 | **DB disk fill** on 128GB data disks → MySQL crash + corruption. | UNVERIFIED | `df -h` on db nodes; growth rate | predict_linear disk alert in Phase 2. |
| 9 | **Single-region** — a Mumbai region event loses prod AND backups (no cross-region copy). | UNVERIFIED | Ask: is there any off-region backup copy? | Cross-region backup copy. ORG decision — flag loudly, don't personally drive. |
| 10 | **Secrets flow unknown** — where do db/proxysql/app creds live, how do they reach boxes? | UNVERIFIED | Map the real flow; `gitleaks` history scan of config repos | Map it. Do NOT assume plaintext (a prior research pass misread a `Local:` dev placeholder as proof of plaintext prod secrets — that was wrong). |
| 11 | **Singletons with no rebuild runbook**: data1, admin1, mail1, gldb1. | UNVERIFIED | Are these single-instance? rebuild documented? | Runbook each (Phase 4). |

Note on baseline metrics: the credible week-2 baseline is THIS list (0% drift detection,
backups never restore-tested, N SPOFs, 1 EOL engine) with a trendline — NOT a DORA scorecard
(you don't own a delivery pipeline yet; DORA from a read-only newcomer is performative).
