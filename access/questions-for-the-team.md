# Questions for the infra owner  (PHASE 0)

Ask these in one conversation. They fill the blanks faster than any amount of grepping,
and asking them well is itself how a read-only newcomer earns trust. Collaborate — do NOT
frame this as "I'm building something to outrun you." Frame: "help me build the as-built map
nobody's written down yet."

1. How does an nginx config change actually reach the boxes today, end to end?
   (Confirms deploy-mechanism.md. The #1 question.)

2. What's my access? What am I allowed to read on prod, what's QA-only, what needs a ticket?
   (Confirms authority.md.)

3. Is the MySQL setup primary→replica replication? Async or semi-sync? GTID or binlog-position?
   Which box is the primary right now? Are the replicas read_only?

4. Is proxysql1 a single node, or is it paired/clustered? What happens to DB traffic if it dies?

5. What does backupdb1 do exactly — what tool (mysqldump / XtraBackup), what schedule,
   and has a restore EVER been tested? What's our real RTO/RPO if db1 dies right now?

6. After a reboot, do the pm2 apps and docker containers come back automatically on every box,
   or are some brought up by hand?

7. Where do DB / app / ProxySQL credentials live, and how do they get onto the boxes?
   (Map the real flow — don't assume plaintext, don't assume Vault.)

8. Who owns what (web/run/data/db/mail), and what's the escalation path + ticket format
   for an infra change?

(Bonus if time: What's hurt most in the last 6 months — what actually broke? That tells you
 where the real risk is, better than any audit.)
