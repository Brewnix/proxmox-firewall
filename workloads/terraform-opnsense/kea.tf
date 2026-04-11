# =============================================================================
# opnsense_kea_subnet
# =============================================================================
# Use [] for unset DHCP options (routers, dns_servers, ntp_servers, time_servers).
# Do not use [""] — the API normalizes those to null; Terraform then shows endless drift.

resource "opnsense_kea_subnet" "kea_sn_192_168_1_0_24" {
  subnet = "192.168.1.0/24"
  pools = [
    "192.168.1.50-192.168.1.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers         = ["192.168.1.1"]
  dns_servers     = ["192.168.1.1"]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "tn.fyberlabs.com"
  ntp_servers   = ["192.168.1.1"]
  time_servers  = ["192.168.1.1"]
  description   = "Main LAN Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_2_0_24" {
  subnet = "192.168.2.0/24"
  pools = [
    "192.168.2.50-192.168.2.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers         = ["192.168.2.1"]
  dns_servers     = ["192.168.2.1"]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "cam.tn.fyberlabs.com"
  ntp_servers   = ["192.168.2.1"]
  time_servers  = ["192.168.2.1"]
  description   = "Camera Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_3_0_24" {
  subnet = "192.168.3.0/24"
  pools = [
    "192.168.3.50-192.168.3.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers         = ["192.168.3.1"]
  dns_servers     = ["192.168.3.1"]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "iot.tn.fyberlabs.com"
  ntp_servers   = ["192.168.3.1"]
  time_servers  = ["192.168.3.1"]
  description   = "IoT Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_4_0_24" {
  subnet = "192.168.4.0/24"
  pools = [
    "192.168.4.50-192.168.4.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers         = ["192.168.4.1"]
  dns_servers     = ["192.168.4.1"]
  domain_search   = []
  ntp_servers     = ["192.168.4.1"]
  time_servers    = ["192.168.4.1"]
  description     = "Guest Wifi Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_5_0_24" {
  subnet = "192.168.5.0/24"
  pools = [
    "192.168.5.50-192.168.5.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers         = ["192.168.5.1"]
  dns_servers     = ["192.168.5.1"]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "mgmt.tn.fyberlabs.com"
  ntp_servers   = ["192.168.5.1"]
  time_servers  = ["192.168.5.1"]
  description   = "Management Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_6_0_24" {
  subnet = "192.168.6.0/24"
  pools = [
    "192.168.6.50-192.168.6.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers         = ["192.168.6.1"]
  dns_servers     = ["192.168.6.1"]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "nodes.tn.fyberlabs.com"
  ntp_servers   = ["192.168.6.1"]
  time_servers  = ["192.168.6.1"]
  description   = "K3S Nodes Network"
}

resource "opnsense_kea_subnet" "kea_sn_192_168_7_0_24" {
  subnet = "192.168.7.0/24"
  pools = [
    "192.168.7.50-192.168.7.250",
  ]
  match_client_id = true
  auto_collect    = true
  routers         = ["192.168.7.1"]
  dns_servers     = ["192.168.7.1"]
  domain_search = [
    "tn.fyberlabs.com",
    "fyberlabs.com",
  ]
  domain_name = "vm.tn.fyberlabs.com"
  ntp_servers   = ["192.168.7.1"]
  time_servers  = ["192.168.7.1"]
  description   = "K3S VMs Network"
}

# =============================================================================
# opnsense_kea_reservation
# =============================================================================
# Local reservations from inventory: run
#   ./scripts/generate_kea_reservations_from_yaml.py --yaml ../../network_devices.yaml --out ./generated_kea_reservations.tf --infer-ip
# Output is gitignored (generated_kea_reservations.tf). Omit --infer-ip to only emit entries with reserved_ip/ip/static_ip.

# =============================================================================
# opnsense_kea_peer
# =============================================================================

# (no HA peers, or searchPeer unavailable)
