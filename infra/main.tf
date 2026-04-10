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

resource "digitalocean_firewall" "nixos" {
  name       = "local-db-remote"
  droplet_ids = [digitalocean_droplet.nixos.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_cidrs
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = [ "0.0.0.0/0", "::/0" ]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = [ "0.0.0.0/0", "::/0" ]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = [ "0.0.0.0/0", "::/0" ]
  }
}

resource "digitalocean_reserved_ip" "nixos" {
  region = var.region
}

resource "digitalocean_reserved_ip_assignment" "nixos" {
  ip_address = digitalocean_reserved_ip.nixos.ip_address
  droplet_id = digitalocean_droplet.nixos.id
}
