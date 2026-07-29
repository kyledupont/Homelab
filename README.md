# Kyle's Homelab

## Overview

This repository documents my self-hosted infrastructure for building, testing, and learning enterprise infrastructure engineering, automation, identity management, observability, virtualization, and AI workloads.

The lab is designed to mirror production environments as closely as possible while remaining cost effective for home use.

See **[my portfolio](https://kyledupont.github.io/)** for the professional front door onto this work, **[the system map](https://kyledupont.github.io/Homelab/)** for a live diagram of every host and how they connect, [Docs/Architecture.md](Docs/Architecture.md) for the current build, [Docs/Network.md](Docs/Network.md) and [Docs/Storage.md](Docs/Storage.md) for infrastructure detail, [Docs/AI.md](Docs/AI.md) for the AI/MCP/agents roadmap, [Docs/Security.md](Docs/Security.md) for the credential/secrets management plan, [Docs/Terraform.md](Docs/Terraform.md) for the IaC provisioning plan, [Docs/Ansible.md](Docs/Ansible.md) for the configuration-management plan, [Docs/Kubernetes.md](Docs/Kubernetes.md) for the K3s cluster, [Docs/SQL.md](Docs/SQL.md) for the Postgres/SQL exercises, [Docs/Portfolio.md](Docs/Portfolio.md) for the public portfolio website plan, [Docs/LessonsLearned.md](Docs/LessonsLearned.md) for what's been learned along the way, and [Docs/Commands.md](Docs/Commands.md) for a running cheat sheet of commonly used commands.

---

# Goals

- Infrastructure as Code (Terraform)
- Configuration Management (Ansible)
- Docker & Docker Compose
- Kubernetes (K3s)
- Build enterprise monitoring with Grafana
- Host a TrueNAS storage server
- Playground for Windows Server & Active Directory
- GitHub Actions CI/CD
- Experiment with local AI using an RTX 4000 GPU
- Model Context Protocol (MCP) and build a custom MCP server exposing this homelab's infrastructure to AI agents
- Build custom AI agents (e.g. via the Claude Agent SDK) that can operate against homelab services
- Integrate AI (Claude, local LLMs via Ollama) into n8n automation workflows
- Build an enterprise-style secrets management environment with HashiCorp Vault for machine/app secrets (see [Docs/Security.md](Docs/Security.md)) — human/admin logins stay in Google Password Manager, not self-hosted
- Document all infrastructure as code

---

# Hardware

## Server

| Component | Details |
|-----------|---------|
| Host | BOXX Workstation |
| CPU | TBD |
| RAM | 32 GB DDR4 |
| GPU | NVIDIA RTX 4000 |
| Boot Drive | 512 GB SSD |
| Second SSD | 512 GB SSD (M.2 SATA) — `ssd2-thin` LVM-Thin pool |
| Storage | 2x 4 TB NAS HDD (WD Red + HGST Ultrastar) — mirrored ZFS pool on truenas01 |

---

# Hardware Wishlist

- [x] Second 4TB+ NAS HDD — `tank` ZFS pool on truenas01 is now a mirror (resilvered 2026-07-15, 0 errors)
- [x] 2.5GbE switch — installed 2026-07-17; Proxmox actually ended up on the switch's 10G port (its 2.5G-tier NICs turned out to be 1G-only), Windows workstation on a 2.5G port. See [Docs/Network.md](Docs/Network.md).

---

# Hypervisor

- Proxmox VE 9.x
- Static IP
- Local SSD VM Storage

---

# Virtual Machines

| VM | Purpose | Status |
|----|----------|--------|
| automation01 | Docker — n8n, Portainer, Uptime Kuma | ✅ Running |
| truenas01 | TrueNAS SCALE — ZFS storage (NFS/SMB) | ✅ Running |
| plex01 | Docker — Plex, Portainer Agent | ✅ Running |
| dc01 | Windows Server (AD/DNS/GPO) | Planned |
| win11-test01 | Test workstation | Planned |
| k3s-master01 | Kubernetes — single-node K3s (control-plane + worker), see [Docs/Kubernetes.md](Docs/Kubernetes.md) | ✅ Running |
| k3s-worker01 | Kubernetes | Planned — add if RAM headroom allows |

---

# Docker Services

## Running

- n8n (automation01)
- Portainer + Agent (automation01, plex01)
- Uptime Kuma (automation01) — v2.4.0
- Homepage dashboard (automation01)
- Plex (plex01) — deliberately kept on its own VM so it can eventually be exposed to the internet (sharing outside the household) without widening `automation01`'s attack surface, see [Docs/Network.md](Docs/Network.md) "Remote access"
- mcp-n8n (automation01) — community MCP server giving Claude Code n8n node/workflow knowledge, see [Docs/AI.md](Docs/AI.md)
- Obsidian (testing) — vault at `S:\Obsidian\Dupontke`, `Homelab/Repo-Docs` auto-mirrored from this repo via git post-commit hook, see [Docs/Obsidian.md](Docs/Obsidian.md)
- PostgreSQL (automation01) — v17, deployed via the first real Ansible playbook 2026-07-23, see [Docs/Ansible.md](Docs/Ansible.md); real homelab-inventory schema + indexing/EXPLAIN ANALYZE/row-locking exercises run live 2026-07-28, see [Docs/SQL.md](Docs/SQL.md)

## Planned

- Grafana
- Prometheus
- Loki
- Alloy
- Redis
- Nextcloud
- Immich
- HashiCorp Vault (machine/app secrets — see [Docs/Security.md](Docs/Security.md))
- Open WebUI
- Ollama
- Pi-hole — network-wide DNS + ad blocking, and a likely candidate for the "Internal DNS" future project below (resolving friendly hostnames for the eventual reverse proxy). Deployed to `automation01` 2026-07-28; ad blocking confirmed actually working (verified via query log + a known ad domain resolving to `0.0.0.0`) after manually pointing one PC's DNS at it. Router-wide DHCP still not pointed at it — see [Docs/Network.md](Docs/Network.md).
- Dozzle — real-time Docker log viewer across hosts, for log review/debugging without shelling in
- Jellyfin — backup/potential replacement for Plex; standing it up alongside Plex to actually evaluate it, not a committed switch
- Homelable (network visual mapping — [github.com/Pouzor/homelable](https://github.com/Pouzor/homelable))
- Keycloak or Authentik — self-hosted OAuth2/OIDC/SAML identity provider for hands-on SSO testing (Okta has no self-hosted option); planned eventual auth layer for the MCP Gateway, see [Docs/AI.md](Docs/AI.md). Idea captured 2026-07-24, not started.
- Hermes Agent (self-hosted Discord IT-admin agent, via Ollama — see [Docs/AI.md](Docs/AI.md))
- MCP Gateway (Docker MCP Gateway) — fronts `homelab-uptime-kuma` + `n8n-mcp` (and future MCP servers) behind one authenticated proxy, see [Docs/AI.md](Docs/AI.md)
- Public-facing custom MCP server — internet-exposed, e.g. a Zendesk ticketing MCP, see [Docs/AI.md](Docs/AI.md)

---

# Storage

## Current

- `tank` pool (truenas01) — **mirrored** (WD Red 4TB + HGST Ultrastar 4TB), resilvered cleanly 2026-07-15
- `ssd2-thin` pool (Proxmox, second SSD) — extra VM disk storage / room for more VMs
- `tank/media` dataset — exported via NFS (plex01) and SMB (Windows access)
- `tank/postgres` dataset — exported via NFS (automation01 only, `192.168.1.20/32`), backs the PostgreSQL container's data directory instead of local disk, see [Docs/Ansible.md](Docs/Ansible.md)

## Future

- Snapshots
- Automated Backups
- Lock down NFS export to plex01's IP specifically

---

# Monitoring

Planned

- Grafana
- Prometheus
- Loki
- Node Exporter
- Windows Exporter

---

# Automation

- Terraform — automation01 imported and under Terraform management 2026-07-22; plex01 imported and k3s-master01 created 2026-07-24, see [Docs/Terraform.md](Docs/Terraform.md)
- Ansible — first playbook applied 2026-07-23 (PostgreSQL, `automation01`); widened same day to a second host, `plex01`, over a dedicated SSH keypair — see [Docs/Ansible.md](Docs/Ansible.md)
- GitHub Actions — self-hosted runner on automation01 auto-deploys Ansible playbooks on push to `main`, 2026-07-23, see [Docs/Ansible.md](Docs/Ansible.md)
- Kubernetes (K3s) — single-node cluster on `k3s-master01`, provisioned via Terraform + bootstrapped via Ansible, 2026-07-24, see [Docs/Kubernetes.md](Docs/Kubernetes.md)
- GitHub Pages — publishes the live [system map](https://kyledupont.github.io/Homelab/) (`Site/index.html`) automatically on every push that touches it, via `.github/workflows/deploy-pages.yml` on a GitHub-hosted runner (not automation01's — this job never touches the homelab network), 2026-07-24
- GitHub Pages, portfolio — [kyledupont.github.io](https://kyledupont.github.io/) is a separate repo (a GitHub *user site*, so it serves at the bare domain with no `/Homelab` in the URL), plain HTML/CSS/JS with no build step — GitHub Pages serves the repo root directly, no Action needed, 2026-07-24. See [Docs/Portfolio.md](Docs/Portfolio.md).

Planned

- Docker Compose

---

# Networking

Static IPs (see [Docs/Network.md](Docs/Network.md) for full detail)

| Device | Address |
|---------|---------|
| Proxmox | 192.168.1.209 |
| automation01 | 192.168.1.20 |
| truenas01 | 192.168.1.40 |
| plex01 | 192.168.1.50 |
| dc01 | Reserved: 192.168.1.30 |
| k3s-master01 | 192.168.1.60 |

---

# Progress

## Completed

- [x] Install Proxmox
- [x] Configure Static IP
- [x] Ubuntu cloud-init template + automation01 VM
- [x] Docker / Docker Compose
- [x] n8n
- [x] Portainer (+ multi-host via Agent)
- [x] Uptime Kuma
- [x] TrueNAS SCALE (NFS + SMB shares)
- [x] Plex (plex01, NFS-backed media)
- [x] ZFS mirror for tank pool
- [x] Second SSD wiped and built into an `ssd2-thin` LVM-Thin pool
- [x] Reboot resilience (VM autostart/order, NFS mount options)
- [x] Homepage dashboard (single landing page for all services)
- [x] Uptime Kuma upgraded 1.23.17 → 2.4.0
- [x] 2.5GbE switch installed — Proxmox on a 10G port, Windows workstation on 2.5G

## In Progress

- [x] Migrating existing media library onto TrueNAS — complete 2026-07-21
- [x] `/uptime-status` slash command confirmed working 2026-07-21 (was previously "added but not verified")
- [x] Proxmox internet speed confirmed 2026-07-21 — earlier "slow" reading was a tooling artifact (single-threaded `speedtest-cli` + a distant test server), the real Ookla CLI showed ~4974/5058 Mbps, matching an apparent ~5-Gig AT&T Fiber plan. See [Docs/Network.md](Docs/Network.md).
- [ ] Uptime Kuma → n8n → Discord outage alerting — design explored, not yet built (see LessonsLearned "Deferred")
- [x] First custom MCP server (`homelab-uptime-kuma`) — built, deployed, running on automation01, and confirmed connected via `/mcp` (see [Docs/AI.md](Docs/AI.md))
- [x] n8n-mcp community MCP server (`mcp-n8n`) — deployed to automation01 and confirmed connected via `/mcp` (see [Docs/AI.md](Docs/AI.md))
- [x] n8n-skills (14 skills + router skill) installed to `~/.claude/skills/`
- [x] First real n8n workflow built via `n8n-mcp`: `Daily Job & Learning Digest` (2026-07-18) — daily Discord message combining job postings (JSearch/RapidAPI), YouTube learning picks, and top-5 news across Hacker News/Bleeping Computer/Wired/TLDR/Reddit. See [Docs/AI.md](Docs/AI.md).
- [x] Obsidian vault publishing started (2026-07-19) — `Homelab/Repo-Docs` mirrored from this repo's `README.md`/`Docs/*.md` via a tracked git post-commit hook (`.githooks/post-commit`); see [Docs/Obsidian.md](Docs/Obsidian.md)
- [ ] Claude Desktop MCP access to the Obsidian vault (`mcp-obsidian` + Local REST API plugin) — config + plugin verified independently 2026-07-19, but Claude Desktop still isn't seeing the vault after a restart; root cause not yet diagnosed, deferred to next session — see [Docs/Obsidian.md](Docs/Obsidian.md)

## Planned

- [ ] Grafana / Prometheus / Loki monitoring stack
- [x] Terraform — provider (`bpg/proxmox`); full lifecycle proven on a disposable test VM (`tf-test01`: applied, SSH-verified, destroyed cleanly); then **`automation01` imported into Terraform state 2026-07-22** — see [Docs/Terraform.md](Docs/Terraform.md) for the full permission/import gotchas and what "Terraform-managed" now means for that VM. **`plex01` imported and applied 2026-07-24** (triggered an unplanned ~15-minute reboot — see Docs/Terraform.md "Gotchas hit").
- [x] Ansible — runs from `automation01` (control node can't be Windows natively — see [Docs/Ansible.md](Docs/Ansible.md)); first playbook applied 2026-07-23, secrets handled via Ansible Vault, not a plaintext `.env`.
- [x] PostgreSQL — deployed via that first Ansible playbook 2026-07-23 (v17, `automation01`), connected to and queried for real (not just a healthy-looking container) — see [Docs/Ansible.md](Docs/Ansible.md).
- [x] Ansible widened to a second, SSH-managed host — `plex01` added to inventory via a dedicated `automation01`-generated keypair, `deploy_plex.yml` applied and confirmed idempotent (unchanged container uptime), 2026-07-23 — see [Docs/Ansible.md](Docs/Ansible.md).
- [x] GitHub Actions — self-hosted runner on `automation01` (systemd service), auto-runs Ansible playbooks on push to `main`; push-trigger-only to stay safe on a public repo — see [Docs/Ansible.md](Docs/Ansible.md).
- [x] Kubernetes — single-node K3s cluster, `k3s-master01` provisioned via Terraform (2 vCPU/4GB RAM, chosen deliberately minimal given the lab's 32GB total budget) and bootstrapped via Ansible; kubectl access lives on `automation01`, same bastion-host pattern as Ansible/GitHub Actions. First real workload deployed, load-balancing verified over actual HTTP requests, then torn down (smoke test only) — 2026-07-24, see [Docs/Kubernetes.md](Docs/Kubernetes.md).
- [x] GitHub Pages — live [system map](https://kyledupont.github.io/Homelab/) of the whole lab's topology, deployed automatically via GitHub Actions on a GitHub-hosted runner — 2026-07-24.
- [ ] Windows Server (dc01) / AD
- [ ] AI Stack (Ollama / Open WebUI via RTX 4000)
- [ ] n8n workflows calling AI (Claude / local LLMs)
- [x] MCP fundamentals (run existing community MCP servers) — n8n-mcp adopted 2026-07-18
- [ ] Proxmox + TrueNAS MCP tools (Uptime Kuma tool already built)
- [ ] Custom AI agents (e.g. via the Claude Agent SDK) operating against homelab services
- [ ] Hermes Agent (self-hosted Discord IT-admin agent via Ollama, homelab troubleshooting + career-goal learning) — see [Docs/AI.md](Docs/AI.md)
- [ ] HashiCorp Vault (machine/app secrets — Docker deploy, KV engine, policies, AppRole) — see [Docs/Security.md](Docs/Security.md)
- [ ] Homelable (network visual mapping/monitoring, nmap discovery + live health status — [github.com/Pouzor/homelable](https://github.com/Pouzor/homelable))
- [ ] MCP Gateway (Docker MCP Gateway) — evaluated 2026-07-18, deferred past ~5 servers; now formally tracked here per user request 2026-07-23 — see [Docs/AI.md](Docs/AI.md)
- [ ] Public-facing custom MCP server (internet-exposed, e.g. Zendesk ticketing) — idea captured 2026-07-23, depends on Reverse Proxy/SSL work above — see [Docs/AI.md](Docs/AI.md)
- [x] Public portfolio website — built and live 2026-07-24 at [kyledupont.github.io](https://kyledupont.github.io/), a separate `kyledupont.github.io` repo, with a dark/light theme toggle shared with the system map — see [Docs/Portfolio.md](Docs/Portfolio.md)

---

# Future Projects

- Reverse Proxy
- SSL Certificates
- Internal DNS — Pi-hole (also covers network-wide ad blocking)
- Active Directory
- SSO Integration — Keycloak or Authentik (self-hosted, see [Docs/AI.md](Docs/AI.md))
- AI Automation
- Backup Automation
- Public-facing custom MCP server (internet-exposed) — see [Docs/AI.md](Docs/AI.md)
- Auto-deploy for non-Ansible config changes (e.g. Homepage) — mirrors the Ansible self-hosted-runner pattern; currently these need a manual `git pull` on `automation01` rather than deploying automatically on push

---

# Repository Structure

```
homelab/
│
├── ansible/
├── docker/
├── docs/
├── kubernetes/
├── terraform/
├── scripts/
├── diagrams/
└── README.md
```

---

# Technologies

- Proxmox (Self hosted sandbox to imitate Azure, GCP, AWS)
- Ubuntu Server
- Docker
- Docker Compose
- Kubernetes
- Terraform
- Ansible
- Grafana
- Prometheus
- Loki
- TrueNAS
- Windows Server
- PowerShell
- GitHub Actions
- GitHub Pages
- Python
- Bash
- Claude / Claude Agent SDK
- Model Context Protocol (MCP)
- Ollama
- Open WebUI

---

# License

Personal learning project.
