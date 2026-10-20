# ---------------------------------------------------------------------------
# Proxmox connection
# ---------------------------------------------------------------------------
variable "proxmox_endpoint" {
  description = "Proxmox API URL, e.g. https://192.168.1.10:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token in the form 'user@realm!tokenid=uuid'"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^!\\s]+![^=\\s]+=[0-9a-fA-F-]{36}$", var.proxmox_api_token))
    error_message = "proxmox_api_token must look like root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (user@realm!tokenid=secret, no spaces)."
  }
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (self-signed Proxmox certificate)"
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "SSH user on the Proxmox node (used to upload snippets)"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_private_key_path" {
  description = "Path to an SSH private key for the Proxmox node. Empty = use ssh-agent"
  type        = string
  default     = ""
}

variable "proxmox_node" {
  description = "Name of the Proxmox node to create the VMs on"
  type        = string
  default     = "pve"
}

# ---------------------------------------------------------------------------
# Storage / network
# ---------------------------------------------------------------------------
variable "vm_datastore" {
  description = "Datastore for VM disks and cloud-init drives (must support 'images', e.g. LVM over iSCSI)"
  type        = string
  default     = "iscsi-netapp"
}

variable "image_datastore" {
  description = "Datastore (with 'iso' content) to store the downloaded cloud image"
  type        = string
  default     = "local"
}

variable "snippets_datastore" {
  description = "Datastore with 'snippets' content enabled for cloud-init user-data"
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Bridge the VMs are attached to"
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "Optional VLAN tag (null = untagged)"
  type        = number
  default     = null
}

variable "gateway" {
  description = "Default IPv4 gateway for the VMs"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers for the VMs"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ubuntu_image_url" {
  description = "Ubuntu cloud image URL"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

# ---------------------------------------------------------------------------
# Guest OS access
# ---------------------------------------------------------------------------
variable "vm_user" {
  description = "Login user created on both VMs"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_keys" {
  description = "SSH public keys allowed to log in as vm_user"
  type        = list(string)
}

variable "timezone" {
  description = "Timezone of the VMs"
  type        = string
  default     = "Asia/Tehran"
}

# ---------------------------------------------------------------------------
# Deployment layout
# ---------------------------------------------------------------------------
variable "deployment_mode" {
  description = "'single' = GitLab and Runner on one VM, 'separate' = one VM each"
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "separate"], var.deployment_mode)
    error_message = "deployment_mode must be single or separate."
  }
}

# ---------------------------------------------------------------------------
# GitLab VM
# ---------------------------------------------------------------------------
variable "gitlab_vm" {
  description = <<-EOT
    GitLab server VM settings. ip must be in CIDR form, e.g. 192.168.1.50/24.
    Unset sizes default to 6 cores / 12 GB / 80 GB in single mode and
    4 cores / 8 GB / 50 GB in separate mode.
  EOT
  type = object({
    vm_id     = number
    name      = string
    ip        = string
    cores     = optional(number)
    memory_mb = optional(number)
    disk_gb   = optional(number)
  })
}

variable "gitlab_external_url" {
  description = "GitLab external URL. Empty = http://<gitlab ip>"
  type        = string
  default     = ""
}

variable "gitlab_edition" {
  description = "gitlab-ce or gitlab-ee"
  type        = string
  default     = "gitlab-ce"

  validation {
    condition     = contains(["gitlab-ce", "gitlab-ee"], var.gitlab_edition)
    error_message = "gitlab_edition must be gitlab-ce or gitlab-ee."
  }
}

# ---------------------------------------------------------------------------
# GitLab Runner VM
# ---------------------------------------------------------------------------
variable "runner_vm" {
  description = "GitLab Runner VM settings, only used when deployment_mode = separate. ip must be in CIDR form"
  type = object({
    vm_id     = number
    name      = string
    ip        = string
    cores     = optional(number, 2)
    memory_mb = optional(number, 4096)
    disk_gb   = optional(number, 40)
  })
  default = null
}

variable "runner_tags" {
  description = "Tags assigned to the runner"
  type        = list(string)
  default     = ["docker", "proxmox"]
}

variable "runner_concurrent" {
  description = "Number of jobs the runner executes in parallel"
  type        = number
  default     = 2
}

variable "runner_docker_image" {
  description = "Default Docker image for jobs"
  type        = string
  default     = "alpine:latest"
}

variable "runner_docker_privileged" {
  description = "Run job containers privileged (needed for docker-in-docker)"
  type        = bool
  default     = false
}
