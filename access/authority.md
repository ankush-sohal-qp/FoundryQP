# Access & Authority Inventory  (PHASE 0)

TRUST: measured by hand. Fill this BEFORE doing anything else. Change nothing while filling it.

This file defines the pace of the entire rest of the plan. The honest answer is often
"I can reach QA, I have a read-only SQL script for prod, everything else is a ticket."
Write THAT down — don't aspire, record reality.

## OS fact (verify per box — do NOT assume Rocky 8 fleet-wide)
Run on each box you can reach: `cat /etc/os-release` and `uname -m`.
Record per tier — different tiers may run different versions.
→

## OCI API access
- [ ] `oci iam compartment list` returns data (not 401)?     →  YES / NO  (paste result)
- [ ] Console access? read-only or more?                      →
- [ ] Which compartment(s) is the fleet in?                   →

## Per-box SSH reality
For every box I can reach, record: user, `id`, `groups`, and `sudo -l`.
Do NOT assume; run it. (`sudo -l` is read-only and tells you exactly what you can escalate.)

| Host                         | Env  | Can SSH? | As user | sudo -l (summary)        | Safe to touch? |
|------------------------------|------|----------|---------|--------------------------|----------------|
| ops1.mu.questionpro.net      | OPS  |          |         |                          |                |
| ops2.mu.questionpro.net      | OPS  |          |         |                          |                |
| infradocker1.mu...           | OPS  |          |         |                          |                |
| labs1 / labsnginx1           | LABS |          |         |                          |                |
| qa1 / qadocker1 / qanginx1   | QA   |          |         |                          |                |
| web1 / web2                  | PROD |          |         |                          |                |
| run1 / run2                  | PROD |          |         |                          |                |
| data1 / admin1               | PROD |          |         |                          |                |
| nginx1 / nginx2 / nginxint1  | PROD |          |         |                          |                |
| db1 / db2 / db3 / gldb1      | PROD |          |         |                          |                |
| proxysql1                    | PROD |          |         |                          |                |
| docker1 / docker2 / docker3  | PROD |          |         |                          |                |
| mail1 / backupdb1            | PROD |          |         |                          |                |

## Bastion
- [ ] Is there a bastion / jump host?   →
- [ ] OCI Bastion service in use?        →

## My standing policy (one sentence)
e.g. "PR-only, no box edits, ask the infra owner before anything stateful."
→

## Done when
I can state in writing exactly what I can access, as whom, and what I'm allowed to change.
