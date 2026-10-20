variable "name" { type = string }
variable "vm_id" { type = number }
variable "node_name" { type = string }
variable "description" {
  type    = string
  default = ""
}
variable "tags" {
  type    = list(string)
  default = []
}
variable "cores" { type = number }
variable "memory_mb" { type = number }
variable "disk_gb" { type = number }
variable "datastore_id" { type = string }
variable "image_file_id" {
  type    = string
  default = null
}
variable "image_import" {
  description = "true = image is '<storage>:import/<file>', imported via the API (import_from); false = file_id, imported via SSH to the node"
  type        = bool
  default     = true
}
variable "clone_vm_id" {
  description = "Template VM ID to full-clone instead of importing an image"
  type        = number
  default     = null
}
variable "clone_node_name" {
  description = "Node holding the template (null = same node)"
  type        = string
  default     = null
}
variable "clone_disk_interface" {
  description = "Interface of the template's boot disk (see the template's Hardware tab)"
  type        = string
  default     = "scsi0"
}
variable "bridge" { type = string }
variable "vlan_id" {
  type    = number
  default = null
}
variable "ip_cidr" { type = string }
variable "gateway" { type = string }
variable "dns_servers" { type = list(string) }
variable "agent_enabled" {
  description = "Wait for the QEMU guest agent (only when cloud-init installs it)"
  type        = bool
  default     = true
}
variable "user_data_file_id" {
  description = "Custom cloud-init user-data snippet; conflicts with user_account"
  type        = string
  default     = null
}
variable "user_account" {
  description = "Built-in cloud-init user, used when no user-data snippet is given"
  type = object({
    username = string
    keys     = list(string)
    password = string
  })
  default   = null
  sensitive = true
}
