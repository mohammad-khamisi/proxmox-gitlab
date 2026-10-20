locals {
  single = var.deployment_mode == "single"

  gitlab_ip           = split("/", var.gitlab_vm.ip)[0]
  gitlab_external_url = var.gitlab_external_url != "" ? var.gitlab_external_url : "http://${local.gitlab_ip}"

  # GitLab and CI jobs share the VM in single mode, so it needs more room.
  gitlab_cores     = coalesce(var.gitlab_vm.cores, local.single ? 6 : 4)
  gitlab_memory_mb = coalesce(var.gitlab_vm.memory_mb, local.single ? 12288 : 8192)
  gitlab_disk_gb   = coalesce(var.gitlab_vm.disk_gb, local.single ? 80 : 50)

  # Runner name/description: the GitLab VM itself in single mode.
  runner_name = local.single ? var.gitlab_vm.name : try(var.runner_vm.name, "")

  # Without node SSH the disk must be imported through the API (import_from),
  # which needs an image of 'import' content type.
  image_content_type = var.use_snippets ? "iso" : "import"
  ubuntu_image_import = (
    var.ubuntu_image_file_id != ""
    ? strcontains(var.ubuntu_image_file_id, ":import/")
    : local.image_content_type == "import"
  )
  ubuntu_image_file_id = (
    var.ubuntu_image_file_id != ""
    ? var.ubuntu_image_file_id
    : proxmox_download_file.ubuntu[0].id
  )
}

resource "terraform_data" "validate_inputs" {
  lifecycle {
    precondition {
      condition     = local.single || var.runner_vm != null
      error_message = "runner_vm must be set when deployment_mode = \"separate\"."
    }
    precondition {
      condition     = var.use_snippets || var.ubuntu_image_file_id == "" || strcontains(var.ubuntu_image_file_id, ":import/")
      error_message = "With use_snippets = false the image must be of 'import' content type (e.g. iso:import/noble-server-cloudimg-amd64.qcow2); importing from ':iso/' needs SSH to the node."
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

# Console password for vm_user (Proxmox web console), used when cloud-init
# snippets are not available.
resource "random_password" "vm_user" {
  length  = 20
  special = false
}

locals {
  gitlab_automation_token = "glpat-${random_password.gitlab_automation_token.result}"

  # Strip CR so files checked out with Windows line endings still run on Linux.
  scripts = {
    for name in ["install-gitlab.sh", "gitlab-bootstrap.rb", "install-runner.sh", "provision.sh"] :
    name => replace(file("${path.module}/scripts/${name}"), "\r", "")
  }

  gitlab_env = replace(templatefile("${path.module}/cloud-init/gitlab.env.tftpl", {
    external_url     = local.gitlab_external_url
    gitlab_edition   = var.gitlab_edition
    root_password    = random_password.gitlab_root.result
    automation_token = local.gitlab_automation_token
  }), "\r", "")

  runner_env = replace(templatefile("${path.module}/cloud-init/runner.env.tftpl", {
    gitlab_url        = local.gitlab_external_url
    automation_token  = local.gitlab_automation_token
    runner_name       = local.runner_name
    runner_tags       = join(",", var.runner_tags)
    runner_concurrent = var.runner_concurrent
    docker_image      = var.runner_docker_image
    docker_privileged = var.runner_docker_privileged
  }), "\r", "")

  common_template_vars = {
    vm_user         = var.vm_user
    ssh_public_keys = var.ssh_public_keys
    timezone        = var.timezone
    gitlab_env      = local.gitlab_env
    runner_env      = local.runner_env
    gitlab_script   = local.scripts["install-gitlab.sh"]
    bootstrap_rb    = local.scripts["gitlab-bootstrap.rb"]
    runner_script   = local.scripts["install-runner.sh"]
  }

  # Built-in Proxmox cloud-init user, used instead of custom user-data.
  vm_user_account = {
    username = var.vm_user
    keys     = var.ssh_public_keys
    password = random_password.vm_user.result
  }
}

# ---------------------------------------------------------------------------
# Ubuntu cloud image (downloaded once onto the node, unless an existing
# image is given in ubuntu_image_file_id)
# ---------------------------------------------------------------------------
resource "proxmox_download_file" "ubuntu" {
  count = var.ubuntu_image_file_id == "" ? 1 : 0

  content_type = local.image_content_type
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node
  url          = var.ubuntu_image_url
  # 'import' content needs a disk-format extension; the Ubuntu .img is qcow2.
  file_name = var.use_snippets ? "noble-server-cloudimg-amd64.img" : "noble-server-cloudimg-amd64.qcow2"
  overwrite = false
}

# ---------------------------------------------------------------------------
# Cloud-init user-data snippets (only with use_snippets = true; needs SSH to
# the Proxmox node)
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "gitlab_user_data" {
  count = var.use_snippets ? 1 : 0

  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.gitlab_vm.name}-user-data.yaml"
    data = templatefile(
      "${path.module}/cloud-init/${local.single ? "all-in-one" : "gitlab"}.yaml.tftpl",
      merge(local.common_template_vars, { hostname = var.gitlab_vm.name })
    )
  }
}

resource "proxmox_virtual_environment_file" "runner_user_data" {
  count = var.use_snippets && !local.single ? 1 : 0

  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.runner_vm.name}-user-data.yaml"
    data = templatefile(
      "${path.module}/cloud-init/runner.yaml.tftpl",
      merge(local.common_template_vars, { hostname = var.runner_vm.name })
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
  image_import      = local.ubuntu_image_import
  bridge            = var.network_bridge
  vlan_id           = var.vlan_id
  ip_cidr           = var.gitlab_vm.ip
  gateway           = var.gateway
  dns_servers       = var.dns_servers
  agent_enabled     = var.use_snippets
  user_data_file_id = var.use_snippets ? proxmox_virtual_environment_file.gitlab_user_data[0].id : null
  user_account      = var.use_snippets ? null : local.vm_user_account
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
  image_import      = local.ubuntu_image_import
  bridge            = var.network_bridge
  vlan_id           = var.vlan_id
  ip_cidr           = var.runner_vm.ip
  gateway           = var.gateway
  dns_servers       = var.dns_servers
  agent_enabled     = var.use_snippets
  user_data_file_id = var.use_snippets ? proxmox_virtual_environment_file.runner_user_data[0].id : null
  user_account      = var.use_snippets ? null : local.vm_user_account

  # The runner registers itself against GitLab on first boot.
  depends_on = [module.gitlab]
}

# ---------------------------------------------------------------------------
# Provisioning over SSH to the VMs (only with use_snippets = false)
# ---------------------------------------------------------------------------
module "provision_gitlab" {
  source = "./modules/provision"
  count  = var.use_snippets ? 0 : 1

  vm_id            = module.gitlab.vm_id
  host             = module.gitlab.ip
  user             = var.vm_user
  private_key_path = var.vm_ssh_private_key_path
  timezone         = var.timezone
  roles            = local.single ? ["gitlab", "runner"] : ["gitlab"]
  scripts          = local.scripts
  gitlab_env       = local.gitlab_env
  runner_env       = local.single ? local.runner_env : ""
}

module "provision_runner" {
  source = "./modules/provision"
  count  = !var.use_snippets && !local.single ? 1 : 0

  vm_id            = module.runner[0].vm_id
  host             = module.runner[0].ip
  user             = var.vm_user
  private_key_path = var.vm_ssh_private_key_path
  timezone         = var.timezone
  roles            = ["runner"]
  scripts          = local.scripts
  gitlab_env       = ""
  runner_env       = local.runner_env

  depends_on = [module.provision_gitlab]
}
