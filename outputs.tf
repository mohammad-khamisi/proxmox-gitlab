output "deployment_mode" {
  value = var.deployment_mode
}

output "gitlab_url" {
  value = local.gitlab_external_url
}

output "gitlab_root_password" {
  description = "Initial password of the GitLab 'root' user"
  value       = random_password.gitlab_root.result
  sensitive   = true
}

output "gitlab_ssh" {
  value = "ssh ${var.vm_user}@${module.gitlab.ip}"
}

output "runner_ssh" {
  description = "Same as gitlab_ssh in single mode"
  value       = local.single ? "ssh ${var.vm_user}@${module.gitlab.ip}" : "ssh ${var.vm_user}@${module.runner[0].ip}"
}
