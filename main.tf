locals {
  single = var.deployment_mode == "single"

  gitlab_ip           = split("/", var.gitlab_vm.ip)[0]
  gitlab_external_url = var.gitlab_external_url != "" ? var.gitlab_external_url : "http://${local.gitlab_ip}"

  # GitLab and CI jobs share the VM in single mode, so it needs more room.
  gitlab_cores     = coalesce(var.gitlab_vm.cores, local.single ? 6 : 4)
  gitlab_memory_mb = coalesce(var.gitlab_vm.memory_mb, local.single ? 12288 : 8192)
  gitlab_disk_gb   = coalesce(var.gitlab_vm.disk_gb, local.single ? 80 : 50)

  ubuntu_image_file_id = (
    var.ubuntu_image_file_id != ""
    ? var.ubuntu_image_file_id
    : proxmox_virtual_environment_download_file.ubuntu[0].id
  )

  # Runner name/description: the GitLab VM itself in single mode.
  runner_name = local.single ? var.gitlab_vm.name : try(var.runner_vm.name, "")
}

resource "terraform_data" "validate_inputs" {
  lifecycle {
    precondition {
      condition     = local.single || var.runner_vm != null
      error_message = "runner_vm must be set when deployment_mode = \"separate\"."
    }
  }
}

# Initial root password and an automation token used to create the runner
# through the GitLab API.
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

  gitlab_template_vars = {
    external_url     = local.gitlab_external_url
    gitlab_edition   = var.gitlab_edition
    root_password    = random_password.gitlab_root.result
    automation_token = local.gitlab_automation_token
    gitlab_script    = file("${path.module}/scripts/install-gitlab.sh")
    bootstrap_rb     = file("${path.module}/scripts/gitlab-bootstrap.rb")
  }

  runner_template_vars = {
    gitlab_url        = local.gitlab_external_url
    automation_token  = local.gitlab_automation_token
    runner_name       = local.runner_name
    runner_tags       = join(",", var.runner_tags)
    runner_concurrent = var.runner_concurrent
    docker_image      = var.runner_docker_image
    docker_privileged = var.runner_docker_privileged
    runner_script     = file("${path.module}/scripts/install-runner.sh")
  }

  common_template_vars = {
    vm_user         = var.vm_user
    ssh_public_keys = var.ssh_public_keys
    timezone        = var.timezone
  }
}

# ---------------------------------------------------------------------------
# Ubuntu cloud image (downloaded once onto the node, unless an existing
# image is given in ubuntu_image_file_id)
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "ubuntu" {
  count = var.ubuntu_image_file_id == "" ? 1 : 0

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
    data = templatefile(
      "${path.module}/cloud-init/${local.single ? "all-in-one" : "gitlab"}.yaml.tftpl",
      merge(
        local.common_template_vars,
        local.gitlab_template_vars,
        local.single ? local.runner_template_vars : {},
        { hostname = var.gitlab_vm.name },
      )
    )
  }
}

resource "proxmox_virtual_environment_file" "runner_user_data" {
  count = local.single ? 0 : 1

  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.runner_vm.name}-user-data.yaml"
    data = templatefile(
      "${path.module}/cloud-init/runner.yaml.tftpl",
      merge(
        local.common_template_vars,
        local.runner_template_vars,
        { hostname = var.runner_vm.name },
      )
    )
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
  description       = local.single ? "GitLab server + GitLab Runner (managed by Terraform)" : "GitLab server (managed by Terraform)"
  tags              = local.single ? ["terraform", "gitlab", "gitlab-runner"] : ["terraform", "gitlab"]
  cores             = local.gitlab_cores
  memory_mb         = local.gitlab_memory_mb
  disk_gb           = local.gitlab_disk_gb
  datastore_id      = var.vm_datastore
  image_file_id     = local.ubuntu_image_file_id
  bridge            = var.network_bridge
  vlan_id           = var.vlan_id
  ip_cidr           = var.gitlab_vm.ip
  gateway           = var.gateway
  dns_servers       = var.dns_servers
  user_data_file_id = proxmox_virtual_environment_file.gitlab_user_data.id
}

module "runner" {
  source = "./modules/vm"
  count  = local.single ? 0 : 1

  name              = var.runner_vm.name
  vm_id             = var.runner_vm.vm_id
  node_name         = var.proxmox_node
  description       = "GitLab Runner for ${local.gitlab_external_url} (managed by Terraform)"
  tags              = ["terraform", "gitlab-runner"]
  cores             = var.runner_vm.cores
  memory_mb         = var.runner_vm.memory_mb
  disk_gb           = var.runner_vm.disk_gb
  datastore_id      = var.vm_datastore
  image_file_id     = local.ubuntu_image_file_id
  bridge            = var.network_bridge
  vlan_id           = var.vlan_id
  ip_cidr           = var.runner_vm.ip
  gateway           = var.gateway
  dns_servers       = var.dns_servers
  user_data_file_id = proxmox_virtual_environment_file.runner_user_data[0].id

  # The runner registers itself against GitLab on first boot.
  depends_on = [module.gitlab]
}
