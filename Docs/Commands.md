# Common Commands

A running cheat sheet of commands used repeatedly across this lab, with enough context to know *when* to reach for each one. Pair with [LessonsLearned.md](LessonsLearned.md) for the *why* behind the gotchas these commands work around.

---

## Deploy workflow (the one that trips people up)

**Context**: edits made in this repo on the Windows dev machine do nothing on any VM until they're committed *and* pushed to GitHub — `git pull` on a VM fetches from the GitHub remote, not from this machine. This caused real confusion more than once (Homepage not starting, config changes not appearing) before the full chain was nailed down.

```bash
# On the Windows dev machine: commit + push (now done by the user, not asked each time)
git add <files>
git commit -m "..."
git push

# On the target VM: pull + redeploy
cd ~/homelab && git pull
cd Docker/<Automation|Media>
docker compose up -d
```

`docker compose up -d` only recreates containers whose config actually changed (image, env vars, volumes, etc.) — safe to run even if nothing changed.

---

## Deploying/updating an MCP server in Docker/MCP/

**Context**: `Docker/MCP/docker-compose.yml` runs one container per MCP server, all sharing one `.env` file in that folder. Adding a new server (e.g. `mcp-n8n`) means appending its vars to the *existing* `.env` rather than overwriting it — the file already holds working vars for the other service(s).

```bash
# Windows dev machine: commit + push as usual (see "Deploy workflow" above)

# On automation01
ssh kyle@192.168.1.20
cd ~/homelab && git pull
cd Docker/MCP
nano .env          # append the new service's vars — see .env.example for the full list
docker compose up -d   # only creates/recreates the container(s) whose config changed
docker logs mcp-n8n
curl http://192.168.1.20:3101/health
```

Then, on Windows: open a **new** Claude Code session (MCP servers only load at session start) and approve the new `.mcp.json` entry when prompted — same one-time approval gotcha as the first custom MCP server.

**AUTH_TOKEN note (n8n-mcp specifically)**: the same token value has to exist in two places — `Docker/MCP/.env`'s `AUTH_TOKEN` on the VM, and the local `N8N_MCP_AUTH_TOKEN` env var so `.mcp.json`'s `${N8N_MCP_AUTH_TOKEN}` substitution resolves. On Windows this is auto-loaded from `pw.env` via a PowerShell profile snippet — an interim measure until Vault (see [Security.md](Security.md)) replaces plaintext `pw.env`.

**SSRF note (n8n-mcp specifically)**: the `n8n_*` workflow-management tools (create/update/list/etc.) fail with `SSRF protection: Private IP addresses not allowed` against any self-hosted n8n, since its `N8N_API_URL` is always a private LAN address. Fix: add `WEBHOOK_SECURITY_MODE=permissive` to `Docker/MCP/.env` and recreate just that container:

```bash
cd ~/homelab/Docker/MCP
docker compose up -d mcp-n8n
```

---

## Testing an n8n workflow with a Schedule Trigger

**Context**: `n8n-mcp`'s `n8n_test_workflow` tool can only externally trigger webhook/form/chat-triggered workflows — n8n's public API has no endpoint to fire a Schedule (or Manual) trigger. Attempting it just returns an error saying so.

```
1. Open the workflow in the n8n editor (http://192.168.1.20:5678)
2. Click "Test workflow" (top-right) — runs every node once immediately, ignoring the schedule
3. Any node that failed turns red in the canvas
```

To inspect the result programmatically afterward (e.g. from Claude Code), use `n8n_executions`:
```
n8n_executions({action: "list", workflowId: "<id>", limit: 5})
n8n_executions({action: "get", id: "<execution-id>", mode: "error"})   # full failing node + upstream payload
```

---

## Proxmox: identifying disks safely

**Context**: `/dev/sdX` letters are **not stable** on this host — they've reassigned three separate times across sessions whenever a drive was added or the host rebooted. Never trust a remembered letter mapping, even from earlier in the same session. Always re-run this immediately before anything destructive or passthrough-related, and cross-check the serial number against known drives:

```bash
ls -la /dev/disk/by-id/ | grep -v part
lsblk
```

Use the `/dev/disk/by-id/...` path (not `/dev/sdX`) in any `qm set` or `wipefs`/`blkdiscard` command, since the by-id path is stable across reboots.

---

## Proxmox: VM management (`qm`)

```bash
# List all VMs and their state
qm list

# Show a VM's full config (useful before modifying disks)
qm config <vmid>

# Start / graceful shutdown / stop (hard power-off, avoid unless hung)
qm start <vmid>
qm shutdown <vmid>
qm stop <vmid>

# Clone the reusable Ubuntu cloud-init template (VMID 9000) for a new Linux VM
qm clone 9000 <new-vmid> --name <hostname> --full
qm set <new-vmid> --memory <MB> --cores <n>
qm resize <new-vmid> scsi0 <size>G
qm set <new-vmid> --ipconfig0 ip=192.168.1.X/24,gw=192.168.1.254
qm set <new-vmid> --ciuser kyle
# SSH key: paste the .pub file's contents via the web UI's Cloud-Init tab rather than
# fighting a Windows-path/host-path mismatch with --sshkeys

# Pass a physical disk through to a VM (always set serial= to avoid TrueNAS's
# "duplicate serial numbers" pool-creation error)
qm set <vmid> --scsiN /dev/disk/by-id/<...>,serial=<unique-label>

# Autostart + boot ordering (so dependent VMs — e.g. anything mounting NFS from
# truenas01 — come up after it, not before)
qm set <vmid> --onboot 1 --startup order=<N>,up=<seconds>
```

---

## Docker Compose (per-VM stacks)

```bash
# Bring a stack up / recreate changed containers
docker compose up -d

# Pull latest images for the pinned tag (won't jump major versions on purpose —
# e.g. louislam/uptime-kuma:1 never pulls a :2 release)
docker compose pull
docker compose up -d

# Logs for a single service (first-run tokens, crash diagnosis, etc.)
docker logs <container_name>

# Recreate just one service after an env/image change
docker compose up -d <service_name>

# Restart policy check — confirms a container will survive a daemon/VM restart
docker inspect <container_name> --format '{{.HostConfig.RestartPolicy.Name}}'
```

**Before a major version bump on anything with persistent data**: clone the named volume and test against a throwaway container first, rather than upgrading the live one blind.

```bash
docker run --rm -v <volume>:/from -v <volume>_test:/to alpine sh -c "cp -av /from/. /to/"
docker run -d --name <name>-test -p <test-port>:<container-port> -v <volume>_test:/app/data <image>:<new-tag>
# confirm it migrates/starts cleanly on the test port, then cut production over for real
docker rm -f <name>-test && docker volume rm <volume>_test
```

---

## TrueNAS / ZFS

```bash
# Confirm pool topology and health — disks must be nested under a shared
# "mirror-0" line to actually be a mirror; separate top-level entries means
# an (undesired) stripe instead
zpool status tank
```

Mirroring an existing single-disk pool is done via the TrueNAS web UI: **Storage → (pool) → Extend** on the existing vdev, not the CLI.

---

## Networking

```bash
# Confirm actual negotiated link speed (relevant once the 2.5GbE switch is installed —
# the switch alone doesn't help until connected NICs also negotiate up)
ethtool <interface>

# Windows equivalent
Get-NetAdapter | Select-Object Name, LinkSpeed
```

---

## SSH access

All Linux VMs use key-based auth only (ed25519 keypair on the Windows workstation, `C:\Users\dupon\.ssh\id_ed25519`) — cloud-init images don't set a password, so there's no password fallback.

```bash
ssh kyle@192.168.1.20   # automation01
ssh kyle@192.168.1.50   # plex01
```

TrueNAS (`192.168.1.40`) and Proxmox (`192.168.1.10`) are managed via their web UIs rather than routine SSH.
