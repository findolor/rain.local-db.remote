output "droplet_id" {
  description = "ID of the local DB remote droplet"
  value = digitalocean_droplet.nixos.id
}

output "droplet_ipv4" {
  description = "Public IPv4 address of the droplet"
  value = digitalocean_droplet.nixos.ipv4_address
}

output "reserved_ip" {
  description = "Reserved IP address assigned to the droplet"
  value = digitalocean_reserved_ip.nixos.ip_address
}
