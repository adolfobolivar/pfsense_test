locals {
  config  = yamldecode(file("${path.module}/${var.config_file}"))
  secrets = yamldecode(file("${path.module}/${var.secrets_file}"))
}
