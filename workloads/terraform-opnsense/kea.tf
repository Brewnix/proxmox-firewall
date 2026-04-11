# =============================================================================
# opnsense_kea_subnet
# =============================================================================

resource "opnsense_kea_subnet" "kea_sn_192_168_1_0_24" {
  subnet = "192.168.1.0/24"
  pools = [
    "192.168.1.10-192.168.1.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers = [
    "",
  ]
  dns_servers = [
    "",
  ]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "tn.fyberlabs.com"
  ntp_servers = [
    "",
  ]
  time_servers = [
    "",
  ]
  description = "Main LAN Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_2_0_24" {
  subnet = "192.168.2.0/24"
  pools = [
    "192.168.2.10-192.168.2.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers = [
    "",
  ]
  dns_servers = [
    "",
  ]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "cam.tn.fyberlabs.com"
  ntp_servers = [
    "",
  ]
  time_servers = [
    "",
  ]
  description = "Camera Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_3_0_24" {
  subnet = "192.168.3.0/24"
  pools = [
    "192.168.3.10-192.168.3.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers = [
    "",
  ]
  dns_servers = [
    "",
  ]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "iot.tn.fyberlabs.com"
  ntp_servers = [
    "",
  ]
  time_servers = [
    "",
  ]
  description = "IoT Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_4_0_24" {
  subnet = "192.168.4.0/24"
  pools = [
    "192.168.4.10-192.168.4.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers = [
    "",
  ]
  dns_servers = [
    "",
  ]
  domain_search = [
    "",
  ]
  ntp_servers = [
    "",
  ]
  time_servers = [
    "",
  ]
  description = "Guest Wifi Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_5_0_24" {
  subnet = "192.168.5.0/24"
  pools = [
    "192.168.5.10-192.168.5.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers = [
    "",
  ]
  dns_servers = [
    "",
  ]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "mgmt.tn.fyberlabs.com"
  ntp_servers = [
    "",
  ]
  time_servers = [
    "",
  ]
  description = "Management Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_6_0_24" {
  subnet = "192.168.6.0/24"
  pools = [
    "192.168.6.10-192.168.6.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers = [
    "",
  ]
  dns_servers = [
    "",
  ]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "nodes.tn.fyberlabs.com"
  ntp_servers = [
    "",
  ]
  time_servers = [
    "",
  ]
  description = "K3S Nodes Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_7_0_24" {
  subnet = "192.168.7.0/24"
  pools = [
    "192.168.7.10-192.168.7.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers = [
    "",
  ]
  dns_servers = [
    "",
  ]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "vm.tn.fyberlabs.com"
  ntp_servers = [
    "",
  ]
  time_servers = [
    "",
  ]
  description = "K3S VMs Network"
}

# =============================================================================
# opnsense_kea_reservation
# =============================================================================


# =============================================================================
# opnsense_kea_peer
# =============================================================================

# (no HA peers, or searchPeer unavailable)
