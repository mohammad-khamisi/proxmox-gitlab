resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  vm_id       = var.vm_id
  node_name   = var.node_name
  description = var.description
  tags        = var.tags
  on_boot     = true

  # Cloud-init (or the SSH provisioning) installs and starts the agent.
  agent {
    enabled = var.agent_enabled
    timeout = "15m"
  }

  operating_system {
    type = "l26"
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    import_from  = var.image_import ? var.image_file_id : null
    file_id      = var.image_import ? null : var.image_file_id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.disk_gb
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  serial_device {}

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ip_cidr
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_data_file_id = var.user_data_file_id

    dynamic "user_account" {
      for_each = var.user_data_file_id == null ? [1] : []
      content {
        username = var.user_account.username
        keys     = var.user_account.keys
        password = var.user_account.password
      }
    }
  }

  lifecycle {
    # Changing user-data after the first boot has no effect; don't recreate.
    ignore_changes = [initialization[0].user_data_file_id]
  }
}
