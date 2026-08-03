# Terraform

## Why this is in the plan

First step of the "Infrastructure as Code" phase from the original roadmap (Terraform provisions → Ansible configures → Kubernetes orchestrates, see [AI.md](AI.md)-style layering in the main learning-progress notes). Also directly job-market relevant — Terraform/HCL is a core platform-engineering skill, same reasoning as the earlier HashiCorp Vault decision (see [Security.md](Security.md)).

Status: **automation01 imported 2026-07-22; plex01 imported and k3s-master01 created from scratch 2026-07-24.** Full lifecycle proven: created a disposable test VM from scratch (`tf-test01`, applied → SSH-verified → destroyed cleanly), imported the real `automation01` VM into Terraform state, then — while applying an unrelated new VM (`k3s-master01`, see [Kubernetes.md](Kubernetes.md)) in the same working directory — `plex01.tf`'s long-staged import got applied for real too, which turned out **not** to be the non-disruptive no-op automation01's import was. See "Gotchas hit" below.

## Provider: `bpg/proxmox`

Chosen over the older `Telmate/proxmox` provider — more actively maintained, better cloud-init/clone support. Pinned to `~> 0.111` in [`Terraform/proxmox/provider.tf`](../Terraform/proxmox/provider.tf) (latest release as of 2026-07-21).

## What's built so far

`Terraform/proxmox/` — provider config, variables, and:

- **`automation01.tf`** — the real, actively-running `automation01` VM (VMID `101`: n8n, Portainer, Uptime Kuma), imported into Terraform state 2026-07-22. Built via `terraform plan -generate-config-out`, which reads the VM's actual live config from Proxmox and writes a matching resource block automatically — far less error-prone than hand-transcribing every attribute. `terraform plan` against it now shows only one cosmetic diff (`operating_system.type`, a Computed provider field — see "Gotchas hit"), no destructive changes. **automation01 is now Terraform-managed** — see "What changes when Terraform manages a running VM" below for what that means day to day.
- **`examples/tf-test01/`** (`main.tf` + `outputs.tf`, moved out of the active config 2026-07-22) — the disposable test VM used to learn the plan/apply/destroy cycle before touching anything real. Cloned from the Ubuntu 24.04 cloud-init template (VMID `9000`), static IP `192.168.1.21`, `kyle` cloud-init user — applied, SSH-verified, then destroyed cleanly. Kept as a reference pattern for provisioning a fresh VM from the template, but moved out of `Terraform/proxmox/`'s working directory so it doesn't get recreated on every `plan`/`apply` (Terraform only reads `.tf` files directly in the working directory, not subfolders).
- **`plex01.tf`** — second real-VM import (VMID `102`), built the same way as automation01 (`generate-config-out` + cleanup). **Applied 2026-07-24** — see the reboot gotcha below for what actually happened when it went from "planned clean" to "applied."
- **`k3s-master01.tf`** — first genuinely new VM created (not imported) since `tf-test01`, this time for real: VMID auto-assigned (`100`), 2 vCPU / 4GB RAM / 40GB disk, static IP `192.168.1.60`, cloned from the same template as every other host. Two SSH keys baked into cloud-init at creation instead of one — the Windows workstation's (personal access) and automation01's dedicated Ansible key (see [Ansible.md](Ansible.md) "Cross-host management") — so Ansible could reach it immediately with no manual `authorized_keys` retrofit like `plex01` needed. See [Kubernetes.md](Kubernetes.md) for what runs on it.
- **`classcompass01.tf`** — created 2026-08-03, same shape as `k3s-master01.tf` (VMID auto-assigned — landed on `103` — both SSH keys baked in at creation). Smaller footprint (2 vCPU / 2GB RAM / 20GB disk) since it's a small Next.js app, not a media server or K8s node. Static IP `192.168.1.21` — the same address the original `tf-test01` exercise validated as free, reused here since `tf-test01` itself was destroyed after that learning exercise. Hosts the `class-compass` app (separate repo) — split off onto its own VM for the same reason `plex01` was: keeps `automation01` off the public internet. See [Network.md](Network.md) and [Ansible.md](Ansible.md) for the rest of the setup.

**Why import automation01 instead of leaving it out of Terraform entirely:** this is what "codify existing infrastructure" actually means in practice — writing a resource block that matches a real, already-running VM and importing it into state, then iterating on `terraform plan` until it shows (near-)zero changes. It's a better exercise than `tf-test01` precisely because it's less forgiving: a resource block that doesn't match reality can make `apply` try to "fix" perceived drift by modifying or recreating a VM real services depend on — which is exactly why `tf-test01` came first, to learn the mechanics somewhere with zero stakes.

## What changes when Terraform manages a running VM

Once a VM is imported, Terraform believes it owns that resource's configuration — this cuts both ways:

- **Want to change automation01's config?** Edit `automation01.tf`, `terraform plan`, `terraform apply` — Terraform makes the real change on Proxmox.
- **Change it manually instead** (Proxmox UI, `qm set`, like before)? The next `terraform plan` shows that as **drift** — a diff between what's declared and what's real — and an unnoticed `apply` afterward would try to revert it back to whatever the `.tf` file says. From here, VM-level config changes to automation01 should go through Terraform, not ad hoc `qm` commands, or the two drift apart. (What runs *inside* the VM — Docker containers, n8n workflows — is untouched by any of this; that's Ansible's/Docker Compose's domain, not Terraform's.)
- **Does an `apply` bring the VM down?** Depends what's changing. CPU cores, memory, tags, description, and network device changes all apply live, no downtime. Changing `boot_order` or resizing a disk (since `disk` isn't in our `hotplug` list) requires a reboot — and since `reboot_after_update = true` (the provider's default, present in the imported config), Terraform performs that reboot **automatically** as part of `apply` rather than asking first. Worth being deliberate about timing specifically for disk-size/boot-order changes; everything else (including routine RAM/CPU bumps) is safe to apply anytime.

## One-time setup — Proxmox API token (manual, do this first)

Terraform authenticates to Proxmox via an API token, not the root password. Creating the user/token is done in the Proxmox web UI — not scriptable from outside it — but **the actual permission grants are much easier via the Proxmox node's built-in Shell (`pveum` CLI) than the Permissions page's GUI**, see "Gotchas hit" below for why.

1. **Datacenter → Permissions → Users → Add** — create a dedicated user, e.g. `terraform@pve` (realm: Proxmox VE authentication server). Using a dedicated user instead of `root@pam` is the least-privilege move — same principle behind everything else in [Security.md](Security.md).
2. **Datacenter → Permissions → API Tokens → Add** — User: `terraform@pve`, Token ID: `terraform`, leave **Privilege Separation** checked. **Copy the generated secret immediately — Proxmox only shows it once.**
3. Copy [`terraform.tfvars.example`](../Terraform/proxmox/terraform.tfvars.example) to `terraform.tfvars` in the same folder (already gitignored) and paste the full token (`terraform@pve!terraform=<uuid>`) into `proxmox_api_token`.
4. Grant the **token itself** (not just the user — see gotcha below) permissions across the three domains a VM clone touches, via node **pve → Shell** in the Proxmox web UI:
   ```bash
   pveum acl modify /                        --tokens 'terraform@pve!terraform' --roles PVEVMAdmin
   pveum acl modify /storage                 --tokens 'terraform@pve!terraform' --roles PVEDatastoreUser
   pveum acl modify /sdn/zones/localnetwork   --tokens 'terraform@pve!terraform' --roles PVESDNUser
   ```

## Gotchas hit (2026-07-22 – 2026-07-23)

### API tokens with Privilege Separation don't inherit the user's permissions
Granting `PVEVMAdmin` to the plain user `terraform@pve` did nothing for the token — with Privilege Separation enabled (the default, and the right choice for least-privilege), **the token is its own principal** (`terraform@pve!terraform`) and needs its own explicit ACL grants, conceptually the same as a scoped OAuth app registration being distinct from the user who owns it. The token also **didn't show up in the Permissions page's "Add: User Permission" dropdown** — a real Proxmox UI gap — so the reliable path is the `pveum acl modify` CLI via the node's built-in Shell (no SSH setup needed, it's a browser-based root shell right in the Proxmox web UI).

### Proxmox splits permissions by resource domain, not by "task"
Cloning a VM with a disk and a network device touches **three separate permission domains** — VM/compute (`VM.Clone`, path `/vms/<template-id>`), storage (`Datastore.AllocateSpace`, path `/storage/<datastore>`), and SDN/networking (`SDN.Use`, path `/sdn/zones/<zone>`) — and no single built-in role spans all three. Hit each one as a separate 403 in turn: `PVEVMAdmin` (compute) → `PVEDatastoreUser` (storage) → `PVESDNUser` (network, since Proxmox 9's SDN model wraps even plain Linux bridges like `vmbr0` in an implicit `localnetwork` zone for permission-checking purposes). All three are now granted at broad-enough paths (`/`, `/storage`, `/sdn/zones/localnetwork`) that future VMs/storage pools shouldn't repeat this.

### Template (VMID 9000) doesn't have `qemu-guest-agent`
`terraform apply` sat at "Creating..." for 5+ minutes with the VM already visible and booted in Proxmox — turned out to be `agent { enabled = true }` waiting (up to its 15-minute timeout) for a guest-agent response that was never going to come, confirmed via the VM's Summary tab showing "guest agent not running" despite a live login prompt on the console. Fix: set `agent.enabled = false` and switch from DHCP to a **static IP** (`192.168.1.21`, matching how every other host in this lab is already assigned per [Network.md](Network.md)) so IP discovery never depends on the agent at all. Confirmed the IP was actually free first via `Test-Connection`/ping before assigning it. Installing the agent in the template itself would be the more complete long-term fix (benefits every future clone) — not yet done, noted as an open item below.

### Importing an existing VM: Computed fields don't converge to zero-diff no matter what you write
Getting `automation01`'s `plan` down to zero changes wasn't fully achievable — `operating_system.type` kept showing as a diff (`+ type = "other"`) regardless of whether the config set it to `null`, `"other"`, or omitted the block entirely. Root cause: it's a Computed attribute the provider resolves to its own default at plan time rather than something reconciled against the config value — the "current state" from import genuinely has no cached value for it yet, since the import/refresh path doesn't populate every Computed field the way a full `Read` after `apply` does. **Lesson: for imports, a few single-attribute, non-destructive diffs on Computed fields are normal and not a sign the resource block is wrong** — the thing to actually scrutinize in the plan is whether anything shows as `-/+ create replacement` (destroy+recreate) or changes a hardware-affecting attribute unexpectedly; a lone `~ update in-place` on a cosmetic field like this is safe to just apply.

### `mac_addresses` is a live-agent-reported Computed field — never pin it as a literal value
The generated config for `automation01` included a hardcoded `mac_addresses` list — not just the primary NIC's MAC, but every Docker-internal interface's MAC too (`docker0`, `br-*`, `veth*`, matching `network_interface_names` from the guest agent). Docker regenerates those veth MACs whenever containers get recreated, so a second `plan` run later showed several of them as "changed" — false drift from a field that was never stable to begin with. Fix: dropped `mac_addresses` from the resource block entirely (it's Computed/observed, not something meant to be declared) — applied the same fix preemptively to `plex01.tf`, even though its generated value happened to come back empty that time. **General lesson: any live-agent-reported attribute reflecting ephemeral in-guest state (container networking, dynamic interfaces) should never be pinned as a literal value in a generated config** — check what a field actually represents before accepting whatever `-generate-config-out` wrote down.

### A "cosmetic" Computed-field diff during import isn't reliably non-disruptive — plex01's import triggered a real ~15-minute reboot
This directly revises the previous gotcha's conclusion. `automation01`'s import showed a lone `operating_system.type` diff and appeared to apply with zero disruption, so the working assumption became "a single Computed-field diff on import is safe to just apply." **`plex01`'s import (2026-07-24) showed the identical single-attribute diff — and this time Terraform actually rebooted the VM to apply it.** Confirmed after the fact via `uptime` on `plex01` (`up 15 min`, boot time matching the apply's own "Modifying... 15m23s" duration almost exactly) — not inferred, directly observed. `reboot_after_update = true` (the provider's default, present in both `automation01.tf` and `plex01.tf`) means Terraform performs a required reboot automatically rather than asking first, so nothing in the `plan` output or the apply itself flagged this as happening.

No lasting harm — `restart: unless-stopped` on Plex/the Portainer agent brought both containers back up automatically once the VM did, and Plex's actual data (NFS-mounted media, a separate config volume) is untouched by a VM-level reboot — but it was real, unplanned downtime (~15 minutes) on a service with users beyond just the account owner. **Revised lesson: treat *any* first-time import's `apply` as reboot-risk regardless of how cosmetic the planned diff looks, and apply during a low-traffic window if the target VM has active users** — "it's just a Computed field" was not a reliable predictor of impact here. Why `automation01`'s import didn't show the same visible disruption is unconfirmed — it may well have rebooted too and simply gone unnoticed, since nothing on it was being actively watched in that moment the way Plex's live containers were checked here.

### A destroyed resource's `.tf` file doesn't stop wanting to exist
After `terraform destroy` on `tf-test01`, its resource block was still sitting in `main.tf` — so the very next `plan` showed "1 to add" for it again (destroy removes it from real infrastructure *and* state, but not from the declared config). Not a bug, just something to remember: once a resource's learning purpose is served, either remove it from the working directory's `.tf` files or move it somewhere Terraform won't auto-load it (moved to `examples/tf-test01/` here, since Terraform only reads `.tf` files directly in its working directory, not subfolders).

## Running it

**Careful: `Terraform/proxmox/` now manages real VMs directly** (`automation01`, `plex01`, `k3s-master01`), not just a disposable test resource. `terraform plan` before `apply`, always — check the plan for anything unexpected before approving, and remember that even a single-attribute Computed-field diff can mean a real reboot (see "Gotchas hit").

```bash
cd Terraform/proxmox
terraform init
terraform plan      # review before ever applying — especially now that automation01 is in scope
terraform apply
```

To experiment with provisioning a fresh VM again without touching automation01, copy `examples/tf-test01/*.tf` back into `Terraform/proxmox/` (or a separate working directory), `apply`, then `destroy` when done — same disposable pattern as before.

## Open questions / next steps

- [x] `terraform destroy` on `tf-test01` — confirmed clean 2026-07-22, full create/destroy lifecycle proven.
- [x] `terraform import` against `automation01` — complete 2026-07-22, see "Gotchas hit" below for the full trail.
- [x] `terraform apply` on `plex01.tf` — applied 2026-07-24, triggered an unplanned ~15-minute reboot, see "Gotchas hit" above.
- [ ] Install `qemu-guest-agent` in the template (VMID `9000`) so future clones can use DHCP + agent-based IP discovery if wanted — not required (static IP works fine without it) but the more complete fix.
- [ ] Remote state (currently local `terraform.tfstate`, gitignored) — fine solo, but worth learning a remote backend eventually since that's standard in team environments.
- [x] Ansible phase started 2026-07-23 — see [Docs/Ansible.md](Ansible.md) (PostgreSQL deployed, running from automation01, NFS-backed storage on truenas01).
- [x] Kubernetes phase started 2026-07-24 — `k3s-master01` created via Terraform, K3s installed via Ansible, first workload deployed and verified — see [Docs/Kubernetes.md](Kubernetes.md).
