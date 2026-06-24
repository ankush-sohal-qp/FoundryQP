# Network Architecture — OCI 3-VCN design  (PHASE 1, from DevOps training notes)

TRUST: from training notes (Ankush), reasoned + structured. Mark UNVERIFIED items before asserting on a box.
All times: PDT (the whole fleet runs on PDT 2026, even though it's the Mumbai/mu region — note the TZ choice).

## OS baseline
- Training notes say **Rocky Linux 8, x86_64** (NOT Ubuntu). Status: **UNVERIFIED per box** —
  confirm with `cat /etc/os-release` on each tier before assuming; some tiers may differ in version.
- IF Rocky 8 confirmed, RHEL-family idioms apply: `dnf`/`yum` (no `apt`), `firewalld` (no `ufw`),
  SELinux (likely enforcing — bites Ubuntu people hardest: denies nginx custom ports/paths, file
  contexts), `systemd`, nginx from the `nginx`/EPEL repo. Write OS-agnostic until confirmed.
- Note: Rocky 8 maintenance-ends 2029-05-31. Rocky 8->9 path is a deliberate later decision,
  not now — track alongside the MySQL 5.7 EOL risk. Don't act on it pre-verification.

## The 3-VCN architecture
Three separate VCNs (Virtual Cloud Networks = isolated virtual networks), not one flat network:

| VCN          | CIDR          | Purpose                                  |
|--------------|---------------|------------------------------------------|
| Production   | 10.11.0.0/20  | live customer-facing workloads           |
| Development  | 10.12.0.0/20  | dev/staging                              |
| Management   | 10.13.0.0/20  | ops/admin/monitoring/bastion             |

NOTE — conflict to resolve: the earlier India-Infrastructure sheet grouped servers as
10.11=PROD, 10.12=OPS, 10.13=QA+LABS. This 3-VCN note says 12=Development, 13=Management.
Likely the SHEET's octet labels and the VCN names are just named differently for the same ranges
(OPS≈Management, QA/LABS≈Development). VERIFY which naming is canonical before relying on it.

### Subnets — each VCN has Public + Private
- **Public subnet** — has a route to the Internet Gateway. Things that must be reachable from
  the internet (or reach out directly) live here: the public-facing nginx / load balancer edge.
- **Private subnet** — NO direct internet route inbound. App/run/data/db all live here.
  This is the security backbone: a DB box has no public IP and cannot be reached from the internet
  at all. Reachable only from inside the VCN (or via peering / bastion).

## NAT Gateway — outbound only, single egress IP
- Private-subnet boxes reach the internet **outbound only** through a NAT Gateway.
- **All applications egress with the SAME public IP** (the NAT's IP). This is why outbound calls
  (webhooks, license checks, mail relays, package pulls) all appear to come from one IP — useful
  for whitelisting QuestionPro's egress on a third party's side.
- NAT is one-directional: outbound works, the internet cannot initiate a connection back in.
  (Internet Gateway = bidirectional, for public subnet; NAT Gateway = outbound-only, for private.)

## Local Peering (VCN-to-VCN, same region)
- VCNs are isolated by default. **Local Peering Gateways (LPG)** connect two VCNs so their private
  subnets can talk — e.g. Production <-> Development.
- Your analogy is right: it's like running a LAN cable (RJ45) directly between two otherwise-separate
  networks. Traffic stays on Oracle's backbone, never touches the internet.
- "One way" in the notes = the peering/route is set up so communication is allowed in a controlled
  direction (route rules + security lists gate WHO can talk to WHOM). Peering itself is a two-ended
  link, but the ROUTE RULES + SECURITY LISTS decide the allowed direction/ports. VERIFY the exact
  allowed direction on the boxes — "one way" is a security-rule fact, not a peering property.

## IPSec VPN — cross-DC / cross-region private interaction
- **IPSec** = encrypted tunnel over the public internet between this OCI network and another
  data center / region / on-prem. Used for **cross-DC communication, specifically DB interaction**
  (e.g. replication or app->DB across DCs) without exposing DB traffic to the open internet.
- Mental model: peering = same-region private link (LAN cable). IPSec = encrypted tunnel BETWEEN
  far-apart networks (a private wire dug across the internet). Different tools, both keep traffic private.

## Route rules + Security lists — "you can't ping from anywhere"
- **Route rules** (route tables) decide WHERE a subnet's traffic can go (IGW / NAT / LPG / IPSec).
- **Security lists** (and/or NSGs) are the stateful firewall: which IPs/ports may enter or leave.
- That's why you can't just ping any box from anywhere — ICMP/ports are denied unless a security
  rule explicitly allows the source. This is the OCI equivalent of AWS security groups + NACLs.
  On Rocky8 there's ALSO `firewalld` on the host — so traffic is gated TWICE (cloud + host firewall).

## Cloudflare — the true front door (whitelabel)
- Real request path starts at **Cloudflare**, not nginx. Cloudflare does DNS + proxy + TLS +
  **custom hostnames** for whitelabel URLs (customers' own domains pointed at QuestionPro).
- So the public edge is: customer domain -> Cloudflare -> (public IP / IGW) -> nginx.
- Full request flow lives in topology/request-flow.md.

## What's still UNVERIFIED here (confirm on boxes / with owner)
- [ ] Canonical naming: is 10.12 "Development" or "OPS"? 10.13 "Management" or "QA+LABS"?
- [ ] Is there ONE NAT per VCN or shared? Confirm the egress IP(s).
- [ ] Exact peering direction(s) and which security rules enforce them.
- [ ] IPSec: which remote DC/region, and is it DB replication or app traffic?
- [ ] Where Prometheus (mon) lives — Management VCN is the logical home.
