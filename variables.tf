variable "mysql_root_password" {
  type      = string
  sensitive = true
}

variable "mysql_user" {
  type = string
}

variable "mysql_password" {
  type      = string
  sensitive = true
}

variable "my_ip" {
  description = "SSHを許可する自分のグローバルIP"
  type        = string
}

