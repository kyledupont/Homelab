variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, e.g. https://192.168.1.10:8006/"
  type        = string
  default     = "https://192.168.1.10:8006/"
}

variable "proxmox_api_token" {
  description = "Proxmox API token, format: <user>@<realm>!<token-id>=<uuid> (see README.md for how to create one)"
  type        = string
  sensitive   = true
}

variable "proxmox_node_name" {
  description = "Name of the Proxmox node to deploy VMs on"
  type        = string
  default     = "pve"
}

variable "template_vm_id" {
  description = "VMID of the reusable Ubuntu 24.04 cloud-init template to clone from"
  type        = number
  default     = 9000
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key injected into new VMs via cloud-init"
  type        = string
  default     = "C:/Users/dupon/.ssh/id_ed25519.pub"
}

variable "vm_user" {
  description = "Cloud-init user created on new VMs (matches the existing convention used for automation01/plex01/etc.)"
  type        = string
  default     = "kyle"
}

variable "vm_ip" {
  description = "Static IPv4 address for tf-test01 (no CIDR suffix). Chosen from the lab's safe static range (.2-.63, see Docs/Network.md) — .21 confirmed unused via ping 2026-07-22."
  type        = string
  default     = "192.168.1.21"
}

variable "vm_gateway" {
  description = "Default gateway for new VMs"
  type        = string
  default     = "192.168.1.254"
}

variable "ansible_public_key" {
  description = "Public half of automation01's dedicated ansible_ed25519 keypair (see Docs/Ansible.md 'Cross-host management') - baked into new VMs at creation via cloud-init so Ansible can reach them over SSH without a manual authorized_keys retrofit like plex01 needed. Public key, safe to commit - not sensitive."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFl0y1EUIgQAtKvU6MOtteBDD0USlLarKa24WmeiaGI8 automation01-ansible-control"
}
