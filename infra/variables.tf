variable "do_token" {
  description = "DigitalOcean API token"
  type = string
  sensitive = true
}

variable "ssh_key_name" {
  description = "Name of the SSH key in DigitalOcean to add to the droplet; must match the key label in the target account"
  type = string
  default = "github_do"
}

variable "region" {
  description = "DigitalOcean region"
  type = string
  default = "lon1"
}

variable "droplet_size" {
  description = "Droplet size slug"
  type = string
  default = "s-2vcpu-4gb"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to reach SSH via the DigitalOcean firewall"
  type = list(string)
  default = [
    "0.0.0.0/0",
    "::/0",
  ]
}
