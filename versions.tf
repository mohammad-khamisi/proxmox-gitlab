terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  # SSH access to the node is required to upload cloud-init snippets.
  ssh {
    agent       = var.proxmox_ssh_private_key_path == ""
    username    = var.proxmox_ssh_username
    private_key = var.proxmox_ssh_private_key_path == "" ? null : file(pathexpand(var.proxmox_ssh_private_key_path))
  }
}
