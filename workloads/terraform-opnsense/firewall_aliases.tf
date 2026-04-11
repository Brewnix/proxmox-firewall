# Firewall aliases — aligned with ../../OpnSenseXML/ALIASES.xml
# If these already exist on the firewall, import before apply:
#   ./scripts/generate_alias_imports.sh
# Or: terraform import 'opnsense_firewall_alias.alias_rfc1918' '<uuid>'

locals {
  alias_network_rfc1918 = toset(["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"])
  alias_network_internal_nets = toset([
    "192.168.1.0/24", "192.168.2.0/24", "192.168.3.0/24", "192.168.5.0/24", "192.168.6.0/24", "192.168.7.0/24",
  ])
  alias_network_cam_block_dest = toset([
    "192.168.1.0/24", "192.168.3.0/24", "192.168.4.0/24", "192.168.5.0/24", "192.168.6.0/24", "192.168.7.0/24",
  ])
}

resource "opnsense_firewall_alias" "alias_rfc1918" {
  name        = "RFC1918"
  type        = "network"
  description = "All private IPv4 — use for internal-only blocks"
  enabled     = true
  content     = local.alias_network_rfc1918
}

resource "opnsense_firewall_alias" "alias_lan_net" {
  name        = "LAN_NET"
  type        = "network"
  description = "Main Network VLAN 10"
  enabled     = true
  content     = toset(["192.168.1.0/24"])
}

resource "opnsense_firewall_alias" "alias_cam_net" {
  name        = "CAM_NET"
  type        = "network"
  description = "Camera Network VLAN 20"
  enabled     = true
  content     = toset(["192.168.2.0/24"])
}

resource "opnsense_firewall_alias" "alias_iot_net" {
  name        = "IOT_NET"
  type        = "network"
  description = "IoT Network VLAN 30"
  enabled     = true
  content     = toset(["192.168.3.0/24"])
}

resource "opnsense_firewall_alias" "alias_guest_net" {
  name        = "GUEST_NET"
  type        = "network"
  description = "Guest Network VLAN 40"
  enabled     = true
  content     = toset(["192.168.4.0/24"])
}

resource "opnsense_firewall_alias" "alias_mgmt_net" {
  name        = "MGMT_NET"
  type        = "network"
  description = "Management VLAN 50 (Omada, Tailscale exit, infra)"
  enabled     = true
  content     = toset(["192.168.5.0/24"])
}

resource "opnsense_firewall_alias" "alias_cluster_node_net" {
  name        = "CLUSTER_NODE_NET"
  type        = "network"
  description = "Cluster Nodes VLAN 60"
  enabled     = true
  content     = toset(["192.168.6.0/24"])
}

resource "opnsense_firewall_alias" "alias_cluster_vm_net" {
  name        = "CLUSTER_VM_NET"
  type        = "network"
  description = "Cluster VMs VLAN 70"
  enabled     = true
  content     = toset(["192.168.7.0/24"])
}

resource "opnsense_firewall_alias" "alias_internal_nets" {
  name        = "INTERNAL_NETS"
  type        = "network"
  description = "All cottage RFC1918 VLANs (for guest/camera isolation)"
  enabled     = true
  content     = local.alias_network_internal_nets
}

resource "opnsense_firewall_alias" "alias_cam_block_dest" {
  name        = "CAM_BLOCK_DEST"
  type        = "network"
  description = "Non-camera internal VLANs (block camera VLAN -> these)"
  enabled     = true
  content     = local.alias_network_cam_block_dest
}

resource "opnsense_firewall_alias" "alias_home_assistant" {
  name        = "HomeAssistant"
  type        = "host"
  description = "HomeAssistant — set IP after DHCP reservation"
  enabled     = true
  content     = toset(["192.168.1.10"])
}

resource "opnsense_firewall_alias" "alias_dahua_nvr" {
  name        = "Dahua_NVR"
  type        = "host"
  description = "Dahua NVR on camera VLAN"
  enabled     = true
  content     = toset(["192.168.2.10"])
}

resource "opnsense_firewall_alias" "alias_reolink_hub" {
  name        = "Reolink_Hub"
  type        = "host"
  description = "Reolink Pro Hub"
  enabled     = true
  content     = toset(["192.168.2.11"])
}

resource "opnsense_firewall_alias" "alias_tn_doorbell" {
  name        = "TN_Doorbell"
  type        = "host"
  description = "TN Cottage Doorbell (Dahua)"
  enabled     = true
  content     = toset(["192.168.2.12"])
}

resource "opnsense_firewall_alias" "alias_omada_controller" {
  name        = "Omada_Controller"
  type        = "host"
  description = "Omada Software Controller (LXC)"
  enabled     = true
  content     = toset(["192.168.5.20"])
}

resource "opnsense_firewall_alias" "alias_ecobee_thermostat" {
  name        = "Ecobee_Thermostat"
  type        = "host"
  description = "TN Cottage Ecobee"
  enabled     = true
  content     = toset(["192.168.3.10"])
}

resource "opnsense_firewall_alias" "alias_ecobee_kitchen_cam" {
  name        = "Ecobee_Kitchen_Cam"
  type        = "host"
  description = "TN Kitchen Ecobee Camera"
  enabled     = true
  content     = toset(["192.168.3.11"])
}

resource "opnsense_firewall_alias" "alias_ecobee_devices" {
  name        = "Ecobee_Devices"
  type        = "host"
  description = "Ecobee thermostat + kitchen camera (internet-only sources)"
  enabled     = true
  content     = toset(["192.168.3.10", "192.168.3.11"])
}

resource "opnsense_firewall_alias" "alias_pihole_dns" {
  name        = "PiHole_DNS"
  type        = "host"
  description = "Pi-hole LXC on VLAN 50 (terraform)"
  enabled     = true
  content     = toset(["192.168.5.2"])
}

resource "opnsense_firewall_alias" "alias_camera_ports" {
  name        = "Camera_Ports"
  type        = "port"
  description = "Reolink / Dahua / ONVIF common"
  enabled     = true
  content     = toset(["80", "443", "554", "8000", "9000"])
}

resource "opnsense_firewall_alias" "alias_omada_mgmt" {
  name        = "Omada_Mgmt"
  type        = "port"
  description = "Omada controller UI"
  enabled     = true
  content     = toset(["8043", "8088"])
}

resource "opnsense_firewall_alias" "alias_doorbell_wan_ports" {
  name        = "Doorbell_WAN_Ports"
  type        = "port"
  description = "SIP / UPnP / RTP — narrow after testing"
  enabled     = true
  content     = toset(["1900", "5060", "5061", "10000:20000"])
}

# --- Aliases on firewall not mapped in firewall_aliases.tf ---
# __CAM20VLAN_network  uuid=__CAM20VLAN_network
# __GUEST40VLAN_network  uuid=__GUEST40VLAN_network
# __IOT30VLAN_network  uuid=__IOT30VLAN_network
# __K3SN60VLAN_network  uuid=__K3SN60VLAN_network
# __K3SV70VLAN_network  uuid=__K3SV70VLAN_network
# __MAIN10VLAN_network  uuid=__MAIN10VLAN_network
# __MGMT50VLAN_network  uuid=__MGMT50VLAN_network
# __lan_network  uuid=__lan_network
# __lo0_network  uuid=__lo0_network
# __opt10_network  uuid=__opt10_network
# __opt11_network  uuid=__opt11_network
# __opt12_network  uuid=__opt12_network
# __opt13_network  uuid=__opt13_network
# __opt14_network  uuid=__opt14_network
# __opt15_network  uuid=__opt15_network
# __opt16_network  uuid=__opt16_network
# __opt17_network  uuid=__opt17_network
# __opt18_network  uuid=__opt18_network
# __opt19_network  uuid=__opt19_network
# __opt1_network  uuid=__opt1_network
# __opt2_network  uuid=__opt2_network
# __opt3_network  uuid=__opt3_network
# __opt4_network  uuid=__opt4_network
# __opt5_network  uuid=__opt5_network
# __opt6_network  uuid=__opt6_network
# __opt7_network  uuid=__opt7_network
# __opt8_network  uuid=__opt8_network
# __opt9_network  uuid=__opt9_network
# __wan_network  uuid=__wan_network
# bogons  uuid=bogons
# bogonsv6  uuid=bogonsv6
# sshlockout  uuid=sshlockout
# virusprot  uuid=virusprot
