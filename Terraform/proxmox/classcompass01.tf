# Dedicated host for the class-compass app (separate repo: d:\Github\class-compass),
# split off onto its own VM rather than automation01 specifically so the app can be
# exposed publicly (classcompass.io via Cloudflare Tunnel) without widening
# automation01's attack surface -- automation01 holds the Ansible control keys and
# GitHub Actions runner, so it stays off the public internet entirely. Same
# clone-from-template pattern as k3s-master01.tf; agent.enabled = false because the
# reusable template (VMID 9000) has no qemu-guest-agent installed.

resource "proxmox_virtual_environment_vm" "classcompass01" {
  name      = "classcompass01"
  node_name = var.proxmox_node_name
  tags      = ["terraform-managed", "classcompass"]

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  agent {
    enabled = false
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
  }

  initialization {
    user_account {
      username = var.vm_user
      # Two keys: the Windows workstation's (personal SSH access, matches every
      # other VM) and automation01's dedicated Ansible key (matches
      # Docs/Ansible.md's cross-host pattern -- baked in at creation instead of
      # appended to authorized_keys after the fact like plex01 needed).
      keys = [
        trimspace(file(var.ssh_public_key_path)),
        var.ansible_public_key,
      ]
    }

    ip_config {
      ipv4 {
        address = "192.168.1.21/24"
        gateway = var.vm_gateway
      }
    }
  }
}

output "classcompass01_ipv4" {
  description = "Static IPv4 address assigned to classcompass01 via cloud-init (not agent-reported -- see agent block comment above)"
  value       = "192.168.1.21"
}
