# Resource Requests & Cost — the mental model

Source: Robusta/Newton webinar on CPU/memory request optimisation, cross-checked against our own
OKE testing. This is the single highest-leverage cost topic in Kubernetes. Read once; it changes
how you size every app in the fleet.

---

## The one sentence
**Cost in Kubernetes boils down to two numbers per container: the CPU request and the memory
request.** Get them right and the cluster is small and cheap; guess them and you waste up to ~69%.

---

## Request vs Limit (know the difference cold)

| | **request** | **limit** |
|---|---|---|
| **What** | Guaranteed minimum, reserved up front | Hard ceiling the pod may not cross |
| **CPU** | What the scheduler packs on → **sizes the cluster** | Throttles the pod past this value |
| **Memory** | Reserved so it isn't OOM-killed | Pod is OOM-killed if it exceeds |
| **Cost role** | **THE cost driver** (cluster capacity = sum of requests) | Minor for cost; matters for stability/security |

- Kubernetes **requires requests**; limits are optional.
- **CPU request is the most important number in K8s** — it decides how pods pack onto finite-core
  nodes, and therefore how many nodes you pay for.
- **HPA scales pod COUNT, not pod size.** The request is the "box size"; HPA just makes more boxes.
  Wrong request → every replica is wrong. Fix the request first. (VPA changes size but is complex/rare.)

---

## The 69% waste (the DoE number)
Studies find teams **over-provision CPU by ~69% on average** — purely by guessing requests high
"to be safe." That's a ~69% cost increase for nothing.

For us this **compounds**: today's EC2 boxes run ~70% idle (one app per box) AND requests would be
guessed → double waste. Right-sizing on a packed cluster reclaims both. This is the pitch, with a
number behind it.

---

## CPU limits: the part that flips our PoC

For **trusted internal teams** (which our fleet is): **consider dropping the CPU limit.**

- A CPU limit **throttles a pod even when the node has spare idle CPU** — it can't borrow it.
- That hurts exactly when you want headroom: traffic spikes, while the HPA/cluster-autoscaler is
  still adding capacity.
- A CPU **request already guarantees** the pod its slice — no other pod can starve it. So the
  "noisy neighbour" fear is usually a *wrong request*, not missing limits.

**Rule of thumb:**
- **Memory limit → YES** (OOM guard), set it ≈ the memory request.
- **CPU limit → optional / omit** for internal trusted apps, so they can burst into idle CPU.
- **CPU limit → KEEP** only for: untrusted workloads, multi-tenant clusters with unknown apps, or
  compute-as-a-service where you must cap users.

> NOTE on our code: `platform/04-app.yaml` currently sets `limits.cpu: "1"`. For an internal app
> that's arguably too strict — reconsider dropping the CPU limit (keep the memory limit). Decide
> per the trust model above.

---

## How to set requests right (measure, don't guess)

1. **Historical data** — look at CPU/memory **over weeks**, not one day. Use a percentile, not a
   transient spike:
   - **CPU request ≈ 99th-percentile** observed CPU.
   - **Memory request ≈ max observed memory + small buffer** (e.g. peak 210Mi → request ~220Mi).
2. **Profiling / stress test** — good for *initial* sizing before there's production history.
   (Stress-testing prod is possible but risky — careful.)
3. Both complement each other: profile to launch, then trust production history over time.

Tools to read usage: Grafana / Prometheus (we have these), Datadog, Sysdig, Dynatrace.

---

## `krr` — don't hand-size a fleet

[`krr`](https://github.com/robusta-dev/krr) (Robusta, open-source CLI):
- Reads ~**1 week of Prometheus** data.
- Recommends **99th-percentile CPU + max-memory+buffer** per workload.
- Outputs a per-pod/app table of recommended requests.

This is the exact tool for our "measure don't guess" principle **at fleet scale** — instead of
hand-tuning 30 apps, run `krr`, get the numbers, apply. Some teams wire its output into an
admission controller to enforce requests automatically. Pair with **Kubecost** for spend visibility.

---

## Restaurant analogy (if explaining to non-infra people)
- **Buffet** (eat anything, anytime) → *not* Kubernetes.
- **Order more of the same dish** when hungry → **HPA** (more replicas).
- **Pre-ordered fixed meals** (commit a quantity up front) → **resource requests** (fixed box size).
- **Pizza party** (estimate how many pizzas before the party) → CPU requests: predict ahead or
  waste / fall short.

---

## Our takeaways (action items)
1. **Reconsider `04-app.yaml` CPU limit** — internal app → likely memory-limit-only, drop CPU limit.
2. **Adopt `krr`** when the fleet lands → measured requests, no guessing, at scale.
3. **Quote the 69%** in the cost pitch — over-provisioning is real money, and we fix it.
4. Requests come from **Prometheus history (p99 CPU, max mem + buffer)**, never a laptop number.
