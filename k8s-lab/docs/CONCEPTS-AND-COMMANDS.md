# Kubernetes — Concepts & Commands (Quick Reference)

A running cheat-sheet for the K8s platform PoC. Each entry: **what it is** (professional, plain
English) → **example/why** → **commands to check it live**. Only commands actually run and verified
in this lab are listed.

> Mental frame we use throughout: every infra decision is a *forced move* from a binding constraint.
> Find the constraint, the architecture follows.

---

## HA — High Availability

**What it is.** A design property where a system keeps serving even when one of its components fails.
The goal is to eliminate single points of failure by running redundant copies across independent
failure domains (pods, nodes, and ultimately data centers).

**Example / why.** If an app runs as a single pod on a single node and that node dies, the service is
down. With multiple replicas spread across multiple nodes, the loss of one pod or node is absorbed —
the remaining replicas continue serving while Kubernetes reschedules the lost ones. The same logic
scales up one level: replicate across data centers so a regional outage doesn't take the service down.
(Residency caveat: failover must stay inside the legal data boundary — an EU workload can only fail
over within EU regions.)

**Check it live.**
```bash
kubectl get nodes -o wide                      # how many independent nodes (failure domains) exist
kubectl get pods -o wide                        # are replicas spread across different nodes?
kubectl drain <node> --ignore-daemonsets        # simulate a node going away; pods reschedule elsewhere
kubectl uncordon <node>                          # bring the node back into scheduling
```

---

## HPA — Horizontal Pod Autoscaler

**What it is.** A Kubernetes controller that automatically adjusts the *number* of pod replicas for a
workload based on observed load (CPU, memory, or custom metrics). "Horizontal" means scaling out by
adding more identical pods, as opposed to "vertical" scaling (making one pod bigger).

**Example / why.** During a traffic spike, the HPA sees CPU cross its target (say 70%) and increases
replicas from 2 to 5; when the spike passes, it scales back down to 2. This removes the need for an
engineer to manually scale during load — it is a core piece of an autonomous platform. The HPA depends
on the **metrics-server** to read live CPU/memory usage.

**Check it live.**
```bash
kubectl top nodes                               # live CPU/memory per node (needs metrics-server)
kubectl top pods                                 # live usage per pod
kubectl autoscale deploy <name> --min=2 --max=8 --cpu-percent=70   # create an HPA
kubectl get hpa -w                               # watch replicas scale up/down with load
```

---

## Node

**What it is.** A worker machine in the cluster that actually runs pods. In production a node is a VM
or physical server; in this local lab minikube fakes each node with a Docker container.

**Example / why.** More nodes = more independent failure domains and more room for the scheduler to
place pods. A single-node cluster has no failure isolation — the node dies, everything dies. This lab
runs 2 nodes (1 control-plane `minikube` + 1 worker `minikube-m02`) so node-level HA can be demonstrated.

**Check it live.**
```bash
kubectl get nodes -o wide                        # list nodes, status, roles, IPs
minikube node add                                # add a worker node
```

---

## CNI — Container Network Interface

**What it is.** The networking layer that gives every pod an IP and lets pods on *different* nodes
talk to each other. Without a CNI plugin installed, newly added nodes stay `NotReady` and cross-node
pod traffic does not work.

**Example / why.** If the database pod lands on node-2 and the app pod on node-3, they can only
communicate if the CNI is wiring the pod network across nodes. In this lab the cluster initially had
no CNI, so added nodes were `NotReady`; installing **kindnet** brought them `Ready` and enabled
cross-node traffic (verified: pod on m02 pinged a pod on m03 with 0% packet loss).

**Check it live.**
```bash
kubectl get nodes                                # NotReady often means missing/broken CNI
kubectl get pods -n kube-system -l app=kindnet -o wide   # one network agent pod per node
# cross-node reachability test: exec into a pod and ping a pod IP on another node
kubectl exec <pod-on-nodeA> -- ping -c 3 <pod-IP-on-nodeB>
```

---

## metrics-server

**What it is.** A lightweight cluster component that collects CPU and memory usage from each node and
pod and exposes it through the metrics API. It is what powers `kubectl top` and feeds the HPA.

**Example / why.** Autoscaling decisions need a live signal of how loaded each pod is; the
metrics-server provides that signal. Without it, `kubectl top` returns "Metrics API not available" and
an HPA cannot make scaling decisions.

**Check it live.**
```bash
minikube addons enable metrics-server            # enable it (minikube)
kubectl top nodes                                # should print live CPU/memory, not an error
```

---

## Cluster

**What it is.** The whole system as one unit: the control plane (the brain) + all worker nodes (where
apps run) + the networking that connects them. One cluster ≈ the full setup of one data centre/region;
multi-DC means multiple clusters.

**Example / why.** Factory analogy — cluster = the whole factory, control plane = the manager's office,
nodes = shop-floor machines, pods = the work running on those machines. No single piece is the factory;
together they are. In this lab: `minikube` (control plane) + `minikube-m02` (worker) + Calico = one cluster.

**Check it live.**
```bash
kubectl cluster-info            # control plane + core services endpoints
kubectl get nodes -o wide       # every machine in the cluster
```

---

## Control Plane (the brain)

**What it is.** The set of components that *decide* what should happen and keep reality matching the
declared wish. It does NOT run your app — workers do. You declare desired state; the control plane
stores it, monitors it, and corrects drift. (Source: kubernetes.io production-environment docs.)

**The 4 components (verified on this cluster, all on the `minikube` node):**
| Component | Role (one line) | Analogy |
|---|---|---|
| **kube-apiserver** | Single entry point — every `kubectl`/component talks to it; validates + serves the API | front desk |
| **etcd** | Key-value store holding ALL cluster state (deployments, secrets, node info) | the notebook / truth |
| **kube-scheduler** | Picks WHICH node a new pod runs on (CPU/mem/taints/affinity) — chooses, doesn't start | seater |
| **kube-controller-manager** | Reconcile loop: desired == actual? If not, fix it (pod died → make a new one) | correction system |

**The flow when you `kubectl apply -f deploy.yaml`:**
```
1. kubectl → API server (validates)
2. API server → stores desired state in etcd
3. controller-manager sees "Deployment wants N pods"
4. scheduler chooses nodes for those pods
5. kubelet on the chosen worker node starts the containers
   → Control plane DECIDES. Workers EXECUTE.
```

**4 corrections / sharp points (don't get these wrong in the demo):**
1. **Scheduler assigns a pod to a node ONCE, at birth.** A running pod does NOT move itself to another
   node. If a node dies, a *new* pod is created and the scheduler re-chooses a node. Cattle, not pets.
   (This is exactly what the node-drain demo shows.)
2. **kubelet is NOT a control-plane component.** It's the agent on every *worker* node that actually
   starts/stops containers. Brain speaks (apiserver), kubelet is the hands. It runs the pods; the
   control plane only tells it what to run.
3. **Cloud Controller Manager does NOT apply to us.** It only exists on cloud-managed K8s (EKS/GKE/AKS)
   to wire cloud load-balancers/volumes/IPs. This lab (minikube) and the real fleet (bare OCI VMs) have
   no CCM. Know it exists; don't claim we have it.
4. **A running pod doesn't need the brain — only *change* does.** When the apiserver choked in this
   session (TLS timeout), pods on m02 kept serving. Control plane down = no new scaling/healing/deploys,
   but whatever is already running keeps running. (Senior-level point — say it in the demo.)

**Production reality (kubernetes.io) vs our PoC — be honest about this gap:**
- **HA control plane needs ≥3 machines**, and the control plane should be **separate from workers**.
  Our cluster has a **single control-plane node** = single point of failure. Fine for a PoC; NOT
  production. (This is the answer to "what if the brain dies?" — in prod you run 3 for etcd quorum.)
- Production also needs: RBAC + policies + resource limits, etcd **backups** (disaster recovery),
  cert rotation, multi-zone spread. Roadmap items, not in the PoC.

**Check it live.**
```bash
kubectl get pods -n kube-system          # see apiserver, etcd, scheduler, controller-manager pods
kubectl get componentstatuses            # control-plane component health (deprecated but quick)
# prove "running pod survives brain outage": kill apiserver briefly, app keeps serving (we saw this live)
```

---

_Add new concepts here as the PoC progresses (Deployment, Service, Ingress, Secret, ResourceQuota,
Probes, GitOps/ArgoCD) — same format: what it is → example/why → verified commands._
