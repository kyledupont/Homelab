# Architecture

## Current state (2026-07-15)

```
Proxmox VE 9.2.2 (bare metal, 192.168.1.10, 32GB RAM)
│
├── Local storage
│   ├── local-lvm   — boot SSD (512GB) — Proxmox OS + original VM disks
│   └── ssd2-thin   — second SSD (512GB, M.2 SATA) — extra VM disk storage
│
├── automation01 (VMID 101) — 192.168.1.20 — 4 vCPU / 8GB RAM / 80GB disk
│   └── Docker Compose (Docker/Automation/)
│       ├── n8n            :5678
│       ├── portainer       :9443 (management UI, Docker Agent-connected to plex01)
│       ├── uptime-kuma     :3001 (v2.4.0)
│       └── homepage        :3000 (dashboard linking every service)
│
├── automation01 (cont.) — Docker Compose (Docker/MCP/)
│   ├── mcp-uptime-kuma      :3100 — custom TypeScript MCP server, Streamable HTTP transport,
│   │                                exposes Uptime Kuma status as a tool for Claude Code
│   └── mcp-n8n              :3101 — community MCP server (ghcr.io/czlonkowski/n8n-mcp),
│                                     Streamable HTTP + bearer auth, gives Claude Code n8n
│                                     node/docs/template knowledge + workflow management
│
├── truenas01 (VMID 200) — 192.168.1.40 — 4 vCPU / 8GB RAM / 32GB boot + 2x 4TB passthrough
│   └── TrueNAS SCALE Community Edition 25.10.4
│       └── pool "tank" — MIRROR (WD Red 4TB + HGST Ultrastar 4TB), resilvered 2026-07-15
│           └── dataset "media" — exported via NFS + SMB
│
├── plex01 (VMID 102) — 192.168.1.50 — 2 vCPU / 4GB RAM / 40GB disk
│   └── Docker Compose (Docker/Media/)
│       ├── plex             :32400 — media at /media, NFS-mounted from truenas01
│       └── portainer_agent  :9001  — lets automation01's Portainer manage this host
│
└── ubuntu-2404-cloudinit (VMID 9000, template) — reusable base for future Linux VMs
```

## Design decisions

- **One Ubuntu cloud-init template, cloned per VM** — every Linux VM (`automation01`, `plex01`) is a full clone of a single template (VMID `9000`) built from the official Ubuntu 24.04 cloud image, rather than repeating ISO installs. This is also the pattern Terraform will use once IaC provisioning is introduced.
- **Compute/storage separation** — `truenas01` owns the only physical data drive and exports it over the network (NFS/SMB); application VMs (`plex01`) consume storage remotely rather than holding their own data disks. `automation01` currently has no persistent-data dependency on TrueNAS yet (Docker named volumes only).
- **Docker host per functional group, not per app** — services are grouped onto VMs by role (`automation01` = automation/ops tooling, `plex01` = media), not one VM per container. Matches the "group by function" approach from the original plan rather than either extreme (single VM for everything, or a VM per service).
- **Multi-host container visibility via Portainer Agent** — Portainer on `automation01` manages `plex01` as a second registered "environment" via the Portainer Agent, rather than running a separate Portainer per VM.

## Boot / resilience behavior

What happens if Proxmox is rebooted or fully power-cycled:

| Layer | Mechanism |
|---|---|
| Physical power-on | BIOS "Restore on AC Power Loss" — must be verified in firmware, outside Proxmox's control |
| VM autostart | `onboot=1` set on all three VMs (`101`, `200`, `102`) |
| Boot order | `truenas01` (order=1, 60s delay) → `automation01` (order=2) → `plex01` (order=3), so TrueNAS's NFS export is ready before `plex01` tries to mount it |
| plex01's NFS mount | `/etc/fstab` uses `_netdev,nofail` — waits for networking before mounting, and won't hang/fail the boot if TrueNAS isn't up in time |
| Docker containers | Every service across both Docker hosts uses `restart: unless-stopped`; Docker daemon itself starts on boot by default, so containers recover automatically once their VM is up |
| TrueNAS NFS/SMB services | Configured with "Start on Boot" enabled in TrueNAS Services |

Net effect: a full power cycle should bring the whole lab back up unattended, in the correct dependency order, assuming the BIOS setting above is actually enabled (not independently verified from software).

## Deviations from the original plan

- **TrueNAS was built earlier than planned, on an unmirrored single disk.** The original roadmap deferred TrueNAS until a second matching drive was purchased. It was built anyway to unblock the Plex media consolidation, running unmirrored for about a day as an accepted risk — **resolved 2026-07-15** when a second 4TB drive (HGST Ultrastar) was added and the pool extended into a proper mirror.
- **plex01 was not part of the original roadmap at all.** It was added to consolidate an existing, separate Plex server the user already ran, using TrueNAS storage as the shared backing store.
- **The 2TB backup drive from the original hardware inventory is currently not detected on the host** — needs investigation before it can serve its planned role as a backup target.
- **A second SSD was added and built into `ssd2-thin`**, a second LVM-Thin pool for VM disk storage — wasn't in the original plan, added opportunistically once the hardware was available. Same model as the boot SSD (M.2 SATA, not NVMe), so it relieves I/O contention across VMs rather than providing a raw speed increase.
- **Homepage dashboard was added ahead of the monitoring stack** — not in the original roadmap, added as a quick single-pane landing page for all services while Grafana/Prometheus/Loki remain unbuilt.
- **Uptime Kuma → n8n → Discord outage alerting was explored but deferred** — two designs were prototyped (webhook-push with batching, then poll-and-diff against Uptime Kuma's metrics endpoint) before the direction shifted toward n8n health-checking services directly over HTTP instead of depending on Uptime Kuma at all. Not yet built; see [LessonsLearned.md](LessonsLearned.md) for the intended design to resume from.
- **First custom MCP server built ahead of Phases 1-3 of the AI roadmap** — jumped straight to Phase 4 (custom MCP server) since a concrete need existed, skipping the originally-planned Ollama/Open WebUI and "learn MCP via community servers" steps for now. See [AI.md](AI.md).
- **New top-level `mcp-servers/` folder** — holds custom MCP server source code (TypeScript projects with their own `package.json`/`Dockerfile`), distinct from the `Docker/*` folders which mostly wrap published images rather than custom-built ones.
- **First real n8n workflow built 2026-07-18: `Daily Job & Learning Digest`** — built via `n8n-mcp` rather than the n8n UI, ahead of and unrelated to the still-deferred Uptime Kuma → n8n → Discord outage alerting workflow. Sends one daily Discord message combining job postings (JSearch/RapidAPI), YouTube learning picks, and top-5 news across Hacker News/Bleeping Computer/Wired/TLDR/Reddit. See [AI.md](AI.md) and [LessonsLearned.md](LessonsLearned.md) for full detail, including a required `mcp-n8n` SSRF config fix (`WEBHOOK_SECURITY_MODE=permissive`).

## Not yet built (from the original roadmap)

- Grafana / Prometheus / Loki / Alloy monitoring stack (Phase 3)
- Windows Server (`dc01`) — AD / DNS / GPO / PKI
- Windows 11 test VM (`win11-test01`)
- Terraform (VM provisioning as code)
- Ansible (configuration management)
- Kubernetes / K3s cluster
- Proxmox Backup Server (explicitly deferred until the lab is much larger)
- HashiCorp Vault (machine/app secrets manager) — see [Security.md](Security.md) for the full plan; human/admin passwords deliberately stay in Google Password Manager, not self-hosted

See [Network.md](Network.md) for IP assignments, [Storage.md](Storage.md) for disk/pool layout, [Security.md](Security.md) for the credential/secrets management plan, and [LessonsLearned.md](LessonsLearned.md) for gotchas encountered along the way.
