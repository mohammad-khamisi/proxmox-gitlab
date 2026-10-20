variable "vm_id" { type = number }
variable "host" { type = string }
variable "user" { type = string }
variable "private_key_path" { type = string }
variable "timezone" { type = string }
variable "roles" { type = list(string) }
variable "scripts" { type = map(string) }
variable "gitlab_env" {
  type      = string
  sensitive = true
}
variable "runner_env" {
  type      = string
  sensitive = true
}
