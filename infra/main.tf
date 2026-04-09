data "digitalocean_ssh_key" "deploy" {
  name = var.ssh_key_name
}

resource "digitalocean_droplet" "nixos" {
  image    = "ubuntu-24-04-x64"
  name     = "local-db-remote-nixos"
  region   = var.region
  size     = var.droplet_size
  ssh_keys = [data.digitalocean_ssh_key.deploy.id]
}

resource "digitalocean_reserved_ip" "nixos" {
  region = var.region
}

resource "digitalocean_reserved_ip_assignment" "nixos" {
  ip_address = digitalocean_reserved_ip.nixos.ip_address
  droplet_id = digitalocean_droplet.nixos.id
}
