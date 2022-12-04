terraform {
  required_providers {
    routeros = {
      source = "GNewbury1/routeros"
    }
  }
}

provider "routeros" {
  hosturl  = "https://172.21.0.1"
  username = "admin"
  password = "password"
  insecure = true
}

# VLAN interface
resource "routeros_interface_vlan" "vlan-vlan71-smartDevices" {
  interface = "bridge-lan"
  name      = "vlan71-smartDevices"
  vlan_id   = 71
}
# Address / Subnet
resource "routeros_ip_address" "address-vlan71-smartDevices" {
  address   = "10.0.71.1/24"
  interface = routersos_interface_vlan.vlan-vlan71-smartDevices.name
  network   = "10.0.71.0"
}
# Pool (optional)
resource "routeros_ip_pool" "pool-vlan71-smartDevices" {
  name   = routersos_interface_vlan.vlan-vlan71-smartDevices.name
  ranges = "10.0.71.100-10.0.71.200"
}
# DHCP network (optional)
resource "routeros_ip_dhcp_server_network" "dhcpNetwork-vlan71-smartDevices" {
  address    = "10.71.0.0/24"
  gateway    = "10.71.0.1"
  dns_server = "10.71.0.1"
  domain     = "yoshi.lan"
}
# DHCP server (optional)
resource "routeros_ip_dhcp_server" "dhcpServer-vlan71-smartDevices" {
  address_pool = routersos_interface_vlan.vlan-vlan71-smartDevices.name
  interface    = routersos_interface_vlan.vlan-vlan71-smartDevices.name
  name         = routersos_interface_vlan.vlan-vlan71-smartDevices.name
}
# Route
resource "routeros_ip_route" "route-vlan71-smartDevices" {
  dst_address = "10.71.0.0/24"
  gateway     = format("%%%s", routersos_interface_vlan.vlan-vlan71-smartDevices.name)
}