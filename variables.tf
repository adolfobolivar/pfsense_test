variable "config_file" {
  description = "Path to the YAML configuration file, relative to the module root"
  type        = string
  default     = "config.yaml"
}

variable "secrets_file" {
  description = "Path to the YAML secrets file containing AWS credentials, relative to the module root"
  type        = string
  default     = "secrets.yaml"
}
