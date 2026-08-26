# Kubernetes

## Why this is in the plan

Last step of the original "Infrastructure as Code" phase order — Terraform provisions → Ansible configures → **Kubernetes orchestrates** (see [Terraform.md](Terraform.md)). Deliberately last, not first: Docker Compose fundamentals needed to be solid before layering orchestration concepts on top, so the pain K8s actually solves (no self-healing, no declarative reconciliation, manual `docker compose up -d` after every crash) would be felt firsthand first.

Career-relevant the same way Terraform/Ansible/Vault were: container orchestration is close to table-stakes vocabulary for platform/IAM engineering roles now — "can run a container" (Docker Compose) reads differently in an interview than "can operate a platform" (K8s).

Status: **Single-node K3s cluster built and verified 2026-07-24** — `k3s-master01` provisioned via Terraform, K3s installed via Ansible, a real workload deployed and confirmed reachable over HTTP with traffic load-balanced across pods, then torn down (it was a smoke test, not a service worth keeping running).

## Why K3s, and why single-node

**K3s over full/vanilla Kubernetes (kubeadm):** K3s is a CNCF-certified, fully API-compatible Kubernetes distribution built specifically for resource-constrained environments — ships as a single ~70MB binary, SQLite instead of a separate etcd cluster, no standalone control-plane components to run. Everything that transfers to real-world/CKA-relevant K8s knowledge (`kubectl`, manifests, Deployments/Services/Ingress) is identical — K3s isn't "K8s for beginners," it's the same API surface with lighter plumbing underneath.

**Single-node over `k3s-master01` + `k3s-worker01`:** this lab's entire hardware budget is 32GB RAM on one physical box, and roughly 12GB+ of that was already committed to `automation01` (8GB) and `plex01` (4GB) before K3s entered the picture, on top of whatever `truenas01` needs for ZFS ARC and Proxmox's own host overhead. A second K8s node would mean paying for an entire second VM's OS + kubelet overhead just to prove "multi-node scheduling" — real value, but not proportionate to the RAM cost right now. K3s's default mode runs control-plane and worker in the same node/process, so one VM gets a fully functional cluster. Nothing about starting single-node forecloses adding `k3s-worker01` later — a second node joins with one command (`k3s agent` + a join token) whenever there's RAM headroom for it.

## What's built

### The node: `k3s-master01`, via Terraform

[`Terraform/proxmox/k3s-master01.tf`](../Terraform/proxmox/k3s-master01.tf) — a genuinely new VM (not an import, unlike `automation01`/`plex01`), same clone-from-template pattern as the original `tf-test01` exercise:

- 2 vCPU / 4GB RAM / 40GB disk, static IP `192.168.1.60` (next free slot in the `.2`-`.63` safe range per [Network.md](Network.md))
- `agent.enabled = false` — the reusable template (VMID `9000`) still has no `qemu-guest-agent`, same known limitation as every other clone in this lab
- **Two SSH keys baked into cloud-init at creation**, not one: the Windows workstation's (personal access, matches every other VM) and `automation01`'s dedicated Ansible key (see [Ansible.md](Ansible.md) "Cross-host management"). This is a small improvement over how `plex01` got its Ansible access — that one needed a manual `authorized_keys` append after the fact, since the key didn't exist yet when `plex01` was originally built. Baking both in at VM-creation time means Ansible could reach `k3s-master01` immediately with zero retrofit steps.

**Side effect worth knowing about**: applying `k3s-master01.tf` ran `terraform apply` against the whole `Terraform/proxmox/` working directory, which also contains `plex01.tf` — staged and plan-reviewed weeks earlier but never actually applied. That import went through in the same run and triggered an unplanned ~15-minute reboot of `plex01` (self-healed automatically via `restart: unless-stopped`, no data loss, but real downtime). Full detail in [Terraform.md](Terraform.md)'s "Gotchas hit" — not repeating it here since it's a Terraform-behavior lesson, not a Kubernetes one, but flagging it since it happened in the same session.

**Proxmox's dashboard can look alarming here — it isn't.** `k3s-master01` shows ~99% memory used in Proxmox's Summary tab. That's *not* real memory pressure — checked directly via `free -h` inside the VM: actual usage is ~1.1GB of 3.8GB, the rest is reclaimable disk cache (`buff/cache`), no swap in use, no OOM-kill events in `dmesg`. Root cause of the misleading dashboard number: `agent.enabled = false` (see above) means Proxmox can't see inside the guest to report real usage, so it's most likely showing the VM's static 4096MB allocation rather than actual load. **Trust `free -h` from inside the guest over Proxmox's summary graph for any VM without the guest agent.**

### The cluster: K3s, via Ansible

[`Ansible/playbooks/install_k3s.yml`](../Ansible/playbooks/install_k3s.yml) — a **one-time bootstrap**, not ongoing config management. This is the deliberate split from [Terraform.md](Terraform.md)'s "Terraform provisions → Ansible configures → Kubernetes orchestrates": once the cluster exists, day-to-day workload changes go through `kubectl`/manifests, not Ansible. The playbook:

1. Installs K3s via the official install script (`curl -sfL https://get.k3s.io | sh -`), guarded with `creates: /usr/local/bin/k3s` so re-running the playbook is a safe no-op rather than re-installing every time.
2. Waits for the node to report `Ready` (retry loop, same pattern as `deploy_postgres.yml`'s `pg_isready` wait).
3. **Fetches the kubeconfig back to `automation01`** (`/etc/rancher/k3s/k3s.yaml` → `~/.kube/config`), then rewrites its embedded `https://127.0.0.1:6443` server address to `k3s-master01`'s real IP — the file is only meaningful running commands *on* `k3s-master01` otherwise.
4. Installs a standalone `kubectl` binary on `automation01` (official `dl.k8s.io` release, guarded the same `creates:` way).

New inventory group in [`Ansible/inventory.ini`](../Ansible/inventory.ini): `[k3s_hosts]`, separate from `[docker_hosts]` since this is conceptually a different kind of host (a K8s node, not a Docker Compose target), even though the SSH mechanics (automation01's dedicated key) are identical to `plex01`'s.

### Where `kubectl` actually lives: automation01, not Windows

Same reasoning as Ansible's control-node decision: `automation01` is already the SSH-reachable bastion host for this lab (Ansible runs from there, the GitHub Actions runner lives there), so it picked up "the machine you run `kubectl` from" too rather than setting up a third tool location. From `automation01`:

```bash
export KUBECONFIG=/home/kyle/.kube/config
kubectl get nodes
```

### First real workload: deployed, verified, torn down

[`Kubernetes/manifests/hello-world.yaml`](../Kubernetes/manifests/hello-world.yaml) — a `Deployment` (2 replicas, `nginxdemos/hello:plain-text`) + a `NodePort` `Service`. Verified past "pods say Running" — actually curled it repeatedly from outside the cluster and confirmed real HTTP responses alternating between both pod IPs, proving the Service's load-balancing actually works, not just that pods exist:

```
Server address: 10.42.0.10:80   Server name: hello-world-57cf9c5bdc-44k47
Server address: 10.42.0.9:80    Server name: hello-world-57cf9c5bdc-8xcvv
```

Torn down immediately after verifying (`kubectl delete -f`) — it was a smoke test with no ongoing purpose, and minimizing idle RAM footprint was an explicit goal for this whole phase. The manifest stays in the repo; reapply it anytime with `kubectl apply -f Kubernetes/manifests/hello-world.yaml` to re-verify the cluster from scratch.

## K3s does not use Docker

Worth stating explicitly, since it's a very common assumption: **`k3s-master01` has no Docker installed at all** — confirmed directly (`docker: command not found`). K3s talks straight to `containerd` (visible in `kubectl get nodes -o wide`'s `CONTAINER-RUNTIME` column: `containerd://2.3.2-k3s2`), skipping Docker Engine entirely. This used to not be true — Kubernetes ran everything through Docker via a compatibility layer called `dockershim` until it was removed in Kubernetes 1.24 (2022). `containerd` isn't a competing project; it's the same low-level engine Docker Engine has been built on top of since 2017 — Kubernetes just talks to that piece directly instead of going through the rest of what Docker Engine bundles (the CLI, `docker build`, Compose).

**Practical consequence for the "migrate a Docker Compose service" open question below**: Kubernetes manifests have **no equivalent to Compose's `build:` directive** — they can only reference an already-built image by name. Anything currently using `build:` (like `mcp-uptime-kuma`, compiled fresh on `automation01` on every deploy) would need an explicit build-and-push step to a registry *before* a K8s manifest could reference it — `k3s-master01` has no Docker to build with locally the way `automation01` does. Services already using a plain `image:` (Postgres, Plex) don't have this problem — the same image reference just moves into a Deployment's `image:` field unchanged.

## Running it

From `automation01`:

```bash
export KUBECONFIG=/home/kyle/.kube/config
kubectl get nodes
kubectl apply -f ~/homelab/Kubernetes/manifests/<file>.yaml
kubectl get pods -A
```

Bootstrap (only needed once, or after a node rebuild):

```bash
cd ~/homelab/Ansible
ansible-playbook -i inventory.ini playbooks/install_k3s.yml
```

## Open questions / next steps

- [ ] Migrate a real Docker Compose service onto the cluster (per the original roadmap's phrasing, "migrate Docker Compose services over") — this is the actual valuable exercise, not just standing up an empty cluster. Candidate: something low-stakes first, not Postgres/Plex. A service already using plain `image:` (not `build:`) is the easier first target — see "K3s does not use Docker" above for why `build:`-based services need an extra step first.
- [ ] Exercise Traefik (K3s's bundled default Ingress controller, already installed and running in `kube-system` — confirmed during setup) instead of `NodePort` — real hostname-based routing rather than a raw port.
- [ ] Persistent storage: no `StorageClass` beyond K3s's default `local-path` provisioner has been exercised yet. Would need an NFS-backed option (matching the `tank/postgres`/`tank/media` pattern) for anything stateful.
- [ ] Add `k3s-worker01` if/when RAM headroom allows — the naming convention and join mechanism are already known, just not needed yet at this scale.
- [x] Host-level monitoring closed 2026-08-25 — `node_exporter` runs on `k3s-master01` as a native systemd service (this host has no Docker daemon, so it can't run the same containerized node-exporter as `automation01`/`plex01`) and is scraped by Prometheus on `automation01`, see [Architecture.md](Architecture.md).
- [ ] No monitoring *inside* the cluster yet — the systemd node_exporter above only covers the host, not Kubernetes-native signals (pod/container resource usage, cluster/node conditions). Would need `kube-state-metrics` and/or `cAdvisor` deployed as cluster workloads and added as their own Prometheus scrape targets. Loki still not started either way.
