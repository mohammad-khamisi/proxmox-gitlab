locals {
  gitlab_ip           = split("/", var.gitlab_vm.ip)[0]
  gitlab_external_url = var.gitlab_external_url != "" ? var.gitlab_external_url : "http://${local.gitlab_ip}"
}

# Initial root password and an automation token used by the runner VM to
# create its own runner through the GitLab API.
resource "random_password" "gitlab_root" {
  length  = 24
  special = false
}

resource "random_password" "gitlab_automation_token" {
  length  = 40
  special = false
}

locals {
  gitlab_automation_token = "glpat-${random_password.gitlab_automation_token.result}"
}

# ---------------------------------------------------------------------------
# Ubuntu cloud image (downloaded once onto the node)
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "ubuntu" {
  content_type = "iso"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node
  url          = var.ubuntu_image_url
  file_name    = "noble-server-cloudimg-amd64.img"
  overwrite    = false
}

# ---------------------------------------------------------------------------
# Cloud-init user-data snippets
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "gitlab_user_data" {
  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.gitlab_vm.name}-user-data.yaml"
    data = templatefile("${path.module}/cloud-init/gitlab.yaml.tftpl", {
      hostname         = var.gitlab_vm.name
      vm_user          = var.vm_user
      ssh_public_keys  = var.ssh_public_keys
      timezone         = var.timezone
      external_url     = local.gitlab_external_url
      gitlab_edition   = var.gitlab_edition
      root_password    = random_password.gitlab_root.result
      automation_token = local.gitlab_automation_token
      install_script   = file("${path.module}/scripts/install-gitlab.sh")
      bootstrap_rb     = file("${path.module}/scripts/gitlab-bootstrap.rb")
    })
  }
}

resource "proxmox_virtual_environment_file" "runner_user_data" {
  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.runner_vm.name}-user-data.yaml"
    data = templatefile("${path.module}/cloud-init/runner.yaml.tftpl", {
      hostname          = var.runner_vm.name
      vm_user           = var.vm_user
      ssh_public_keys   = var.ssh_public_keys
      timezone          = var.timezone
      gitlab_url        = local.gitlab_external_url
      automation_token  = local.gitlab_automation_token
      runner_tags       = join(",", var.runner_tags)
      runner_concurrent = var.runner_concurrent
      docker_image      = var.runner_docker_image
      docker_privileged = var.runner_docker_privileged
      install_script    = file("${path.module}/scripts/install-runner.sh")
    })
  }
}

# ---------------------------------------------------------------------------
# VMs
# ---------------------------------------------------------------------------
module "gitlab" {
  source = "./modules/vm"

  name              = var.gitlab_vm.name
  vm_id             = var.gitlab_vm.vm_id
  node_name         = var.proxmox_node
  description       = "GitLab server (managed by Terraform)"
  tags              = ["terraform", "gitlab"]
  cores             = var.gitlab_vm.cores
  memory_mb         = var.gitlab_vm.memory_mb
  disk_gb           = var.gitlab_vm.disk_gb
  datastore_id      = var.vm_datastore
  image_file_id     = proxmox_virtual_environment_download_file.ubuntu.id
  bridge            = var.network_bridge
  vlan_id           = var.vlan_id
  ip_cidr           = var.gitlab_vm.ip
  gateway           = var.gateway
  dns_servers       = var.dns_servers
  user_data_file_id = proxmox_virtual_environment_file.gitlab_user_data.id
}

module "runner" {
  source = "./modules/vm"

  name              = var.runner_vm.name
  vm_id             = var.runner_vm.vm_id
  node_name         = var.proxmox_node
  description       = "GitLab Runner for ${local.gitlab_external_url} (managed by Terraform)"
  tags              = ["terraform", "gitlab-runner"]
  cores             = var.runner_vm.cores
  memory_mb         = var.runner_vm.memory_mb
  disk_gb           = var.runner_vm.disk_gb
  datastore_id      = var.vm_datastore
  image_file_id     = proxmox_virtual_environment_download_file.ubuntu.id
  bridge            = var.network_bridge
  vlan_id           = var.vlan_id
  ip_cidr           = var.runner_vm.ip
  gateway           = var.gateway
  dns_servers       = var.dns_servers
  user_data_file_id = proxmox_virtual_environment_file.runner_user_data.id

  # The runner registers itself against GitLab on first boot.
  depends_on = [module.gitlab]
}
