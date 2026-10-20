# Uploads the install scripts to a VM over SSH and runs them with sudo.
locals {
  dir = "/tmp/proxmox-gitlab"
}

resource "terraform_data" "this" {
  triggers_replace = [var.vm_id]

  connection {
    type        = "ssh"
    host        = var.host
    user        = var.user
    private_key = file(pathexpand(var.private_key_path))
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p ${local.dir} && chmod 700 ${local.dir}"]
  }

  provisioner "file" {
    content     = var.scripts["provision.sh"]
    destination = "${local.dir}/provision.sh"
  }

  provisioner "file" {
    content     = var.scripts["install-gitlab.sh"]
    destination = "${local.dir}/install-gitlab.sh"
  }

  provisioner "file" {
    content     = var.scripts["gitlab-bootstrap.rb"]
    destination = "${local.dir}/gitlab-bootstrap.rb"
  }

  provisioner "file" {
    content     = var.scripts["install-runner.sh"]
    destination = "${local.dir}/install-runner.sh"
  }

  provisioner "file" {
    content     = var.gitlab_env
    destination = "${local.dir}/gitlab.env"
  }

  provisioner "file" {
    content     = var.runner_env
    destination = "${local.dir}/runner.env"
  }

  # GitLab takes 10-20 minutes; its output is streamed here and logged to
  # /var/log/install-*.log on the VM.
  provisioner "remote-exec" {
    inline = [
      "sudo bash ${local.dir}/provision.sh '${var.timezone}' ${join(" ", var.roles)}",
    ]
  }
}
