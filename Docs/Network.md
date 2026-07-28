# Network

## Home network

| Property | Value |
|---|---|
| Gateway | `192.168.1.254` |
| Subnet | `255.255.255.0` (/24) |
| Router DHCP range | `192.168.1.64` - `192.168.1.253` |
| Static IP range in use | `192.168.1.2` - `.63` (outside the DHCP pool) |

Static IPs should also get a DHCP reservation/exclusion set on the router to prevent future collisions.

## Static IP assignments

| Host | IP | Role |
|---|---|---|
| Proxmox | `192.168.1.209` | Hypervisor host |
| automation01 | `192.168.1.20` | Docker host — n8n, Portainer, Uptime Kuma |
| truenas01 | `192.168.1.40` | TrueNAS SCALE (Community Edition) — ZFS storage |
| plex01 | `192.168.1.50` | Docker host — Plex, Portainer Agent |
| dc01 | Not yet built | Reserved: `192.168.1.30` (Windows Server / AD, per original plan) |

## Remote access

Not yet configured. Original plan calls for Tailscale for general remote access to the lab, rather than exposing services directly to the internet.

**`plex01` is the deliberate exception.** It's kept on its own VM specifically so it can eventually be exposed to the internet — sharing with people outside the household — without widening `automation01`'s attack surface, since `automation01` holds the Ansible SSH keys, the GitHub Actions runner, and the rest of the control-plane tooling. Not yet exposed; when it happens, options under consideration are Plex's own built-in Remote Access, Tailscale Funnel, or a reverse proxy + own domain (the last one is more work but better practice for the Reverse Proxy/SSL goals elsewhere in this repo).

## Pi-hole (internal DNS + ad blocking)

Deployed to `automation01` 2026-07-28 (`Docker/Pihole/docker-compose.yml`). Confirmed resolving DNS correctly from another LAN device (`192.168.1.89`) via both the admin UI (`:8081/admin`) and real `nslookup`/`dig` queries — **and confirmed actually blocking ads**, not just resolving: manually pointed that PC's IPv4 DNS at `192.168.1.20`, verified via the Query Log (ad-network domains showing as blocked in real time while browsing) and a direct `nslookup` of a known ad domain resolving to `0.0.0.0` instead of a real IP.

**Not yet network-wide** — only that one PC is manually configured to use Pi-hole. The router's DHCP DNS setting still hasn't been pointed at it, so every other device on the network is still using whatever DNS it got by default.

- **Port 53 conflict never actually materialized** — `systemd-resolved` and Docker's `docker-proxy` coexisted fine on `automation01` without the anticipated fix being needed.
- **The admin-password env var (`FTLCONF_webserver_api_password`) was correct as documented** — no v6 drift issue there.
- **Real gotcha hit: Pi-hole only answered loopback queries, not LAN queries, until `FTLCONF_dns_listeningMode=ALL` was set.** Full diagnostic trail and why in [LessonsLearned.md](LessonsLearned.md) 2026-07-28 — worth reading before touching this again, since the symptom (TCP handshake succeeds, but no actual DNS response, only from non-loopback sources) doesn't look like a listening-mode problem at first glance.
- **Still not done**: pointing the router's DHCP/DNS settings at Pi-hole — deliberate separate step, whole-household impact, not yet taken.

## Notes

- All current VMs use static IPs assigned via Proxmox cloud-init (`ipconfig0`), not DHCP reservations on the router.
- SSH access to Linux VMs uses key-based auth only (ed25519 keypair generated on the Windows workstation); cloud-init images don't set a password, so password SSH login isn't available as a fallback.

## Open items

- **Proxmox's IP (`192.168.1.209`) falls inside the router's DHCP range (`.64`-`.253`)**, unlike every other static host in this lab (all assigned in the `.2`-`.63` range specifically to avoid this). The router could theoretically hand `.209` to another device via DHCP, conflicting with Proxmox. Fix by either adding a DHCP reservation/exclusion for `.209` on the router, or re-IPing Proxmox into the safe static range — reservation is less disruptive.
- **Resolved 2026-07-17: switch installed, Proxmox upgraded past 1GbE.** Proxmox's onboard NICs (`nic0`/`nic2`) turned out to only support up to `1000baseT` — no 2.5G mode at all. The other onboard NIC pair (`nic3`/`nic4`, Intel `ixgbe`) supports `1000baseT`/`10000baseT` with nothing in between either, so rather than buying a dedicated 2.5G card, `nic3` was moved to the switch's 10G port instead — confirmed via `ethtool nic3` negotiating a full `10000Mb/s`. The Windows workstation is on one of the switch's 2.5G ports. End-to-end throughput between them is capped by the slower side (2.5G, ~280MB/s realistic ceiling) rather than Proxmox's own 10G link, but that's still roughly 2.5x the old 1GbE ceiling of ~113MB/s.
- **Resolved 2026-07-21: Proxmox internet speed test looked slow, wasn't.** An initial `speedtest-cli` run from Proxmox over SSH returned only 850/274 Mbit/s, versus 2357/2337 Mbps from a PC on the LAN's 2.5G switch port — looked like a real problem. Root cause was entirely tooling, not network: (1) `speedtest-cli` (Python) uses a single TCP stream, which is bandwidth-delay-product limited — it had also picked a distant test server (Springfield, MO, ~81ms RTT), compounding the effect; (2) the Ookla apt-repo installer script failed silently (404 — its OS detection doesn't yet recognize Proxmox/Debian 13 "trixie"), so `speedtest` was quietly still running the old Python tool rather than erroring out. Installing the official Ookla CLI directly from `install.speedtest.net` (bypassing the broken repo script) and re-running against a nearby Orlando server gave **4974 Mbps down / 5058 Mbps up, 0% packet loss** — Proxmox's 10G link has plenty of headroom, and this number is close enough to a round 5000/5000 to suggest the actual ISP plan (AT&T Internet) is a ~5-Gig fiber tier. Lesson: **for multi-gigabit links, always use the official multi-connection Ookla CLI, not the single-threaded Python `speedtest-cli`** — the latter will report numbers far below the real link capacity once you're past roughly 1 Gbps.
