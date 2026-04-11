# =============================================================================
# opnsense_interfaces_vlan
# =============================================================================

resource "opnsense_interfaces_vlan" "main_lan_vlan10" {
  description = "Main LAN"
  tag         = 10
  priority    = 3
  parent      = "vtnet2"
  device      = "vlan01"
}

resource "opnsense_interfaces_vlan" "guest_wifi_vlan40" {
  description = "Guest WiFi"
  tag         = 40
  priority    = 0
  parent      = "vtnet3"
  device      = "vlan010"
}

resource "opnsense_interfaces_vlan" "k3s_cluster_nodes_vlan60" {
  description = "K3S Cluster Nodes"
  tag         = 60
  priority    = 0
  parent      = "vtnet2"
  device      = "vlan011"
}

resource "opnsense_interfaces_vlan" "k3s_cluster_vms_vlan70" {
  description = "K3S Cluster VMs"
  tag         = 70
  priority    = 0
  parent      = "vtnet2"
  device      = "vlan012"
}

resource "opnsense_interfaces_vlan" "cameras_vlan20" {
  description = "Cameras"
  tag         = 20
  priority    = 4
  parent      = "vtnet3"
  device      = "vlan013"
}

resource "opnsense_interfaces_vlan" "management_vlan50" {
  description = "Management"
  tag         = 50
  priority    = 7
  parent      = "vtnet2"
  device      = "vlan02"
}

resource "opnsense_interfaces_vlan" "management_vlan50_1" {
  description = "Management"
  tag         = 50
  priority    = 7
  parent      = "vtnet3"
  device      = "vlan03"
}

resource "opnsense_interfaces_vlan" "management_vlan50_2" {
  description = "Management"
  tag         = 50
  priority    = 7
  parent      = "vtnet4"
  device      = "vlan04"
}

resource "opnsense_interfaces_vlan" "cameras_vlan20_1" {
  description = "Cameras"
  tag         = 20
  priority    = 4
  parent      = "vtnet4"
  device      = "vlan05"
}

resource "opnsense_interfaces_vlan" "main_wifi_vlan10" {
  description = "Main WiFi"
  tag         = 10
  priority    = 3
  parent      = "vtnet3"
  device      = "vlan06"
}

resource "opnsense_interfaces_vlan" "iot_vlan30" {
  description = "IoT"
  tag         = 30
  priority    = 1
  parent      = "vtnet2"
  device      = "vlan07"
}

resource "opnsense_interfaces_vlan" "iot_vlan30_1" {
  description = "IoT"
  tag         = 30
  priority    = 1
  parent      = "vtnet3"
  device      = "vlan08"
}

resource "opnsense_interfaces_vlan" "iot_vlan30_2" {
  description = "IoT"
  tag         = 30
  priority    = 1
  parent      = "vtnet4"
  device      = "vlan09"
}
