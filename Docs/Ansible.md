# Ansible

## Why this is in the plan

Second step of the "Infrastructure as Code" phase (Terraform provisions → **Ansible configures** → Kubernetes orchestrates — see [Terraform.md](Terraform.md)). Also directly job-market relevant, same reasoning as Terraform/Vault: Ansible is a core platform/IAM-engineering skill, and it's specifically strong in exactly the kind of on-prem/config-management work this lab targets.

Status: **First playbook applied and verified 2026-07-23** — PostgreSQL deployed on `automation01`, storing its data on `truenas01` (NFS) rather than local disk, connected to and queried for real (`PostgreSQL 17.10`). **Widened to a second, cross-host target same day** — `plex01` brought under management over real SSH (see "Cross-host management" below). **Widened to a third target 2026-08-03** — `classcompass01`, see "Third target: classcompass01" below.

## Where Ansible runs: automation01, not the Windows workstation

Unlike Terraform (a self-contained Go binary with a native Windows build), **Ansible's control node has to be Linux, macOS, or WSL — it does not run natively on Windows.** Two options were weighed:
- Set up WSL2 on the Windows workstation and run Ansible from there.
- Install Ansible on `automation01` (already a Linux Docker host with SSH reachability) and run playbooks from there after a `git pull`.

**Chosen: automation01.** Fits the existing edit → commit → push → pull → deploy workflow ([Commands.md](Commands.md)) exactly as-is, no new environment to learn on the Windows side, and mirrors how Ansible is actually run in most real environments — a dedicated control/bastion host, not individual engineers' laptops.

Installed via `sudo apt-get install -y ansible` → `ansible [core 2.16.3]` (Ubuntu 24.04's package).

## Inventory: automation01 (local) + plex01 + classcompass01 (SSH)

[`Ansible/inventory.ini`](../Ansible/inventory.ini) has three hosts in `docker_hosts`: `automation01` (`ansible_connection=local` — manages the host it's running on directly), `plex01` (real SSH, `192.168.1.50`), and `classcompass01` (real SSH, `192.168.1.21`).

## Cross-host management: a dedicated SSH keypair for automation01

`automation01` previously had **no SSH keypair of its own** — only an `authorized_keys` file for accepting incoming connections from the Windows workstation, which is a one-way door and useless for automation01 to reach *other* hosts. Fixed by generating a keypair dedicated to Ansible rather than reusing anything else:

```bash
# On automation01
ssh-keygen -t ed25519 -f ~/.ssh/ansible_ed25519 -N '' -C 'automation01-ansible-control'
```

No passphrase — matches how every other key-based auth path in this lab already works unattended (Ansible itself, the GitHub Actions runner), and it's scoped down anyway (`kyle`'s normal permissions on the target, nothing broader). The public key was appended to `plex01`'s `~/.ssh/authorized_keys` (not overwritten — that file already had the Windows workstation's key), and `inventory.ini` points at it explicitly via `ansible_ssh_private_key_file` rather than relying on default key discovery, so it's obvious from the inventory alone which key Ansible uses.

`truenas01` is not part of this yet — see "Open questions."

## Secrets: Ansible Vault, not a plaintext `.env`

The Postgres password is generated randomly (`openssl rand -base64 24`), then encrypted with `ansible-vault encrypt_string` before ever touching a file that gets committed:

- [`Ansible/host_vars/automation01/vault.yml`](../Ansible/host_vars/automation01/vault.yml) — the encrypted password (`vault_postgres_password`), **safe to commit** — that's the entire point of Ansible Vault, the ciphertext is meaningless without the vault password.
- The vault password itself lives at `Ansible/.vault_pass` **on automation01 only**, generated directly there via `openssl rand -base64 32`, gitignored (`**/.vault_pass`), never synced through git. Same handling pattern as Terraform's `terraform.tfvars` — the encrypted/templated config is version-controlled, the actual key that unlocks it isn't.
- The playbook renders `Ansible/templates/postgres.env.j2` into `Docker/Postgres/.env` at runtime, substituting the decrypted password — the plaintext password only ever exists on disk inside that gitignored `.env` file (same as every other service's secrets in this repo), never in git history.

## Gotcha hit: `group_vars` vs `host_vars`

First playbook run failed with `'postgres_compose_dir' is undefined` — the non-secret vars (`Ansible/host_vars/automation01/vars.yml` today) were originally placed under `group_vars/automation01/`. **`group_vars/<name>/` only applies to a *group* named `<name>`** — `automation01` is a host in the `docker_hosts` group, not a group itself, so those variable files were silently never loaded. Fix: moved both the vars and vault files to `Ansible/host_vars/automation01/`, which is the correct convention for host-specific variables. Easy mistake since the file structure looks nearly identical either way and Ansible doesn't error on an unused `group_vars` directory — it just silently doesn't apply.

## Storage: NFS-backed on truenas01, not a local Docker volume

Postgres's data directory lives on `tank/postgres` (a new dataset on `truenas01`), NFS-mounted at `/mnt/postgres` on automation01 — same pattern as `plex01`'s media mount, chosen over a local named Docker volume once it came up that local storage isn't durable and has no backups. `docker-compose.yml` bind-mounts `/mnt/postgres:/var/lib/postgresql/data` directly rather than using a named volume.

**Two real gotchas hit getting this working:**

- **NFS export network typo silently blocked the mount.** The TrueNAS NFS share was created restricted to `196.168.1.20/32` (a typo — should've been `192`.168.1.20). `showmount -e` still listed the export fine (export visibility isn't access-controlled), but actually mounting failed with `access denied by server`. Diagnosed by explicitly test-mounting from automation01 rather than trusting the share existed correctly just because it appeared in TrueNAS's UI.
- **NFS root-squash broke Postgres's own startup script.** The official `postgres` image's entrypoint runs as root specifically to `chown`/`chmod` its data directory to the `postgres` user before dropping privileges — but NFS servers by default map an incoming client's root to an unprivileged "nobody" (root squash), so that chown was silently rejected (`Operation not permitted`), and the container crash-looped forever on the same two failing commands. **Fix: set "Maproot User: root" / "Maproot Group: root"** on the TrueNAS NFS share (Sharing → NFS → Advanced Options) — scoped to just that one export, already network-restricted to automation01's IP alone, so the blast radius of granting root-equivalent NFS access is small. This is a known, common gotcha for **any** containerized app that needs to manage ownership on its own NFS-mounted data directory, not specific to Postgres.

The playbook itself handles the NFS side declaratively before ever starting the container: installs `nfs-common`, ensures the mount point exists, mounts `tank/postgres` persistently (`ansible.posix.mount`, `_netdev,nofail` — same options as `plex01`'s fstab entry), and explicitly verifies the mount is actually active via `mountpoint -q` before proceeding — otherwise Docker would silently create the bind-mount path as an empty local directory if the NFS mount wasn't there yet, masking the intended NFS storage entirely without any error.

## What the first playbook does

[`Ansible/playbooks/deploy_postgres.yml`](../Ansible/playbooks/deploy_postgres.yml):
1. Confirms Docker is present (does **not** install it — that's a bigger, separate concern; this playbook assumes Docker already exists, which it does on every host in this lab).
2. Ensures `nfs-common` is installed, the mount point exists, `tank/postgres` is mounted from `truenas01`, and confirms the mount is actually active.
3. Renders the `.env` file from the vault-encrypted password via the Jinja2 template.
4. Runs `docker compose up -d` against [`Docker/Postgres/docker-compose.yml`](../Docker/Postgres/docker-compose.yml) (`postgres:17`, matching the same one-folder-per-service convention as `Docker/Automation/` and `Docker/MCP/`).
5. Waits for `pg_isready`, retrying — Postgres takes longer to accept connections on first-time NFS-backed initialization than on local disk (many small files, NFS metadata overhead), so a single immediate check would be flaky.

Verified end-to-end, not just "container exists": connected via `docker exec postgres psql` and ran real queries (`\l`, `SELECT version()`) — confirmed `PostgreSQL 17.10` running and queryable, with its actual data files (`~7.5MB`) confirmed present on the NFS mount, not local disk.

**One-time migration note**: since Postgres had already been deployed once with a local named volume before this storage move, switching required a one-time `docker compose down -v` to discard the old local volume (safe — nothing but default/empty test databases were ever in it) before re-running the playbook against the new NFS-backed config. This teardown step was **not** added to the playbook itself — baking in "delete the old volume" as a normal, repeatable task would be dangerous once real data exists.

## Second playbook: deploy_plex.yml

[`Ansible/playbooks/deploy_plex.yml`](../Ansible/playbooks/deploy_plex.yml) — same shape as `deploy_postgres.yml` (confirm Docker, ensure the NFS mount, `docker compose up -d`), applied against `plex01`'s existing Plex + Portainer Agent stack ([`Docker/Media/docker-compose.yml`](../Docker/Media/docker-compose.yml)). Two differences from the Postgres playbook:
- **No Ansible Vault involved** — nothing in `Docker/Media/docker-compose.yml` needs a secret (no `.env` at all), so there's no template-rendering step.
- **The NFS mount (`tank/media`) already existed and was already in `plex01`'s `/etc/fstab`** before this playbook was written — unlike Postgres's mount, which the playbook created from scratch. The mount tasks here are about making that state *declarative and idempotent* (Ansible verifies/enforces it every run) rather than provisioning it for the first time.

First run confirmed idempotent against the live host: `docker ps` showed both containers with unchanged uptime (`Up 7 days`) after the playbook ran — nothing was recreated, Ansible just confirmed everything already matched the desired state.

## Third target: classcompass01 (2026-08-03)

Two new playbooks, both targeting `classcompass01` (`192.168.1.21`):

- **`bootstrap_docker.yml`** — new work, not copying an existing pattern. Every playbook up to this
  point explicitly assumed Docker was already installed ("this playbook does not install Docker...
  assumes Docker already exists, which it does on every host in this lab" — true for `automation01`/
  `plex01` because they were hand-set-up before Ansible existed, but `classcompass01` wasn't). This
  playbook installs Docker Engine + the Compose plugin from Docker's own apt repo (not Ubuntu's
  `docker.io` package, which lags upstream) and runs before `deploy_classcompass.yml`.
- **`deploy_classcompass.yml`** — same shape as `deploy_plex.yml`, with two differences: the app's repo
  (`github.com/kyledupont/Class-Compass`, deliberately kept separate from this one — see that repo's own
  `Docs/Deployment.md`) is cloned/pulled at deploy time rather than already living under `Docker/<service>/`
  here; and since it's a *private* repo, the playbook generates a dedicated read-only deploy key on
  `classcompass01` the first time it runs (`~/.ssh/classcompass_deploy_ed25519` — same "keypair scoped to
  exactly this purpose" pattern as `automation01`'s own `ansible_ed25519` key). The public half needs
  adding to the class-compass repo's **Settings → Deploy keys** (read-only) on GitHub — one-time manual
  step, the playbook prints it via `ansible.builtin.debug` on first run so it's easy to grab from the
  Actions log.

`.env` is rendered from `Ansible/templates/classcompass.env.j2` — vault-encrypted secrets live in
`Ansible/host_vars/classcompass01/vault.yml` (same `ansible-vault encrypt_string` pattern as Postgres's
password), non-secret values (public API client IDs, the AdSense publisher ID, the Turnstile site key) in
`Ansible/host_vars/classcompass01/vars.yml`. One value there, `vault_cloudflare_tunnel_token`, is currently
a placeholder — re-encrypt it with the real token once the Cloudflare Tunnel is created (Zero Trust →
Networks → Tunnels on Cloudflare's dashboard), same workflow as every other secret here.

No NFS mount needed here (unlike Postgres/Plex) — the app's only persistent state is in Postgres, which
stays on `automation01`'s shared container; `classcompass01` just makes a LAN-only client connection to
it, no change to `automation01`'s own exposure.

## Running it

Manually, from `automation01` (SSH in, or however you're driving it):
```bash
cd ~/homelab/Ansible
ansible-playbook playbooks/deploy_postgres.yml --vault-password-file .vault_pass
```

Or automatically — see below.

## Automatic deploys via GitHub Actions

**Status: wired up 2026-07-23, extended 2026-08-03.** [`.github/workflows/deploy-ansible.yml`](../.github/workflows/deploy-ansible.yml) runs `deploy_postgres.yml`, `deploy_plex.yml`, `bootstrap_docker.yml`, and `deploy_classcompass.yml` (in sequence, one job) on every push to `main` that touches `Ansible/**` (plus a manual `workflow_dispatch` trigger). All playbooks are idempotent, so running one even when only another actually changed is a harmless no-op rather than something worth conditionally skipping — not worth the added complexity of path-based job selection at this scale.

**Runner: self-hosted on automation01 itself, not a GitHub-hosted runner.** Two reasons:
- automation01 is the Ansible control node already (see above) — a hosted runner has no route into the homelab LAN without a VPN/tunnel.
- The workflow reuses the vault password file that's already on disk at `/home/kyle/homelab/Ansible/.vault_pass` (`--vault-password-file` points at that absolute path directly), rather than duplicating the vault secret into GitHub Actions secrets. Same "the key that unlocks the vault never leaves automation01" principle as the manual-run setup.

Installed as a systemd service (`actions-runner/svc.sh install kyle` → `actions.runner.Dup0n7-Homelab.automation01.service`, enabled + running), so it survives reboots and doesn't need a logged-in session.

**Security note — this repo is public.** Registering a self-hosted runner on a public repo triggers a GitHub warning: a fork's pull request could otherwise get arbitrary code executed on the runner (which runs as `kyle`, who has `sudo`/`docker` group membership and LAN access). Mitigated by keeping the trigger to `push: branches: [main]` only — **never add a `pull_request` or `pull_request_target` trigger to any workflow that targets this runner**, since a fork PR can't push to `main` and there are no other collaborators on this repo. If that ever changes (a collaborator gets push access, or a PR-triggered workflow gets added), this needs re-hardening — e.g. a dedicated low-privilege service account instead of `kyle`, off the `sudo`/`docker` groups.

### Runner internals: where it lives, how to watch it

The runner agent itself is **not part of this git repo** — `deploy-ansible.yml` only defines what runs; the agent that polls GitHub and executes it is a standalone install on `automation01` at `/home/kyle/actions-runner/`:

| File | What it holds |
|---|---|
| `.runner` | Non-secret identity — registered to `Dup0n7/Homelab`, agent name `automation01`, pool `Default` |
| `.credentials` / `.credentials_rsaparams` | The auth keypair the runner uses to poll GitHub, generated once at registration — never touches git |
| `_work/Homelab/Homelab/` | Fresh checkout of the repo per job run (separate from `~/homelab`, the manually-managed checkout) |
| `_diag/` | Per-run diagnostic logs |

Registered as a systemd service, `actions.runner.Dup0n7-Homelab.automation01.service` (`/etc/systemd/system/`), running as `kyle`, `enabled` + `active`.

**Watching it run:**
- GitHub's Actions tab (`github.com/kyledupont/Homelab/actions`) — the normal way, shows every run and step-by-step logs.
- Runner online/idle/active status: repo **Settings → Actions → Runners**.
- On `automation01`: `sudo journalctl -u actions.runner.Dup0n7-Homelab.automation01.service -f` (live) or `--no-pager -n 100` (history).

**How it was registered** (one-time, not something a playbook or script repeats): downloaded the runner release tarball to `~/actions-runner`, ran `./config.sh --url https://github.com/Dup0n7/Homelab --token <one-time token from the GitHub UI> --unattended --name automation01 --labels automation01 --work _work`, then `sudo ./svc.sh install kyle && sudo ./svc.sh start` to wrap it as the systemd service above. The registration token is single-use and expires quickly — only needed at registration time, not stored anywhere after.

## Open questions / next steps

- [x] Give `automation01` its own SSH keypair and authorize it on `plex01` — done 2026-07-23, see "Cross-host management" above. `truenas01` still not authorized/added.
- [x] Decide whether `truenas01` should ever be Ansible-managed at all — **decided 2026-07-23: no.** It's a storage appliance driven through its own UI/API by design (ZFS pools, NFS/SMB exports, shares) — not a general-purpose Docker host like `automation01`/`plex01`, so there's nothing here that's actually a better fit for Ansible than TrueNAS's own tooling. `docker_hosts` in the inventory stays scoped to hosts that run Docker Compose stacks.
- [ ] Next phase per the original order: Kubernetes (K3s), once Terraform + Ansible both feel solid.
