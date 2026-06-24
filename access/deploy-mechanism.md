# The Deploy Mechanism — the "somehow"  (PHASE 0)

TRUST: measured by hand.

"nginx configs live in GitHub, pulled onto boxes somehow." *Somehow* is the single most
important as-built fact to nail — because that puller is a LIVE WRITER. In Phase 3, if I
point Ansible at the same nginx files without first disabling this puller, I get a
reload-fight outage. Answer this completely before Phase 3.

## How to find it (read-only)
Clone the nginx/config repo and grep — do NOT run anything on the boxes yet:

    git clone <config-repo> && cd <config-repo>
    ls -la .github/workflows/        # GH Actions push (SSH/rsync)?
    find . -name '*.yml' -path '*playbook*'   # Ansible push?
    find . -name 'hooks.json' -o -name 'deploy.sh'   # webhook listener / hand-run script?
    grep -rn 'rsync\|scp\|ssh\|ansible\|webhook\|git pull' . | grep -iv node_modules

On a box I'm authorized on (read-only):
    crontab -l ; sudo crontab -l          # cron git pull / ansible-pull?
    systemctl list-units | grep -i 'hook\|webhook\|deploy'   # webhook listener service?
    ss -ltnp | grep -E ':9000|:8080'      # webhook listener port?

## The answer (fill in)
Mechanism is one of:  [ ] GH Actions + SSH/rsync (push)  [ ] Ansible push
                      [ ] webhook listener  [ ] cron git pull / ansible-pull  [ ] hand-run deploy.sh

Exact end-to-end path (repo → trigger → lands on box → reload):
→

The live writer I must disable before co-managing nginx with Ansible:
→

## Done when
I can draw the full path from "edit config in repo" to "nginx reloads on nginx1",
and I know exactly what to disable before Ansible touches those files.
