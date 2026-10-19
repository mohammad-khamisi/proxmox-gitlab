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
variable "image_file_id" { type = string }
variable "bridge" { type = string }
variable "vlan_id" {
  type    = number
  default = null
}
variable "ip_cidr" { type = string }
variable "gateway" { type = string }
variable "dns_servers" { type = list(string) }
variable "user_data_file_id" { type = string }
