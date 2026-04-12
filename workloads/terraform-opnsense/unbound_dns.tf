# =============================================================================
# opnsense_unbound_host_override
# =============================================================================


# =============================================================================
# opnsense_unbound_forward
# =============================================================================
# Do not add a catch-all forward to Pi-hole here when DHCP hands clients
# 192.168.5.2 directly (see kea.tf). Clients → Pi-hole → upstream; Pi-hole
# conditional forwards internal zones to OPNsense (cloud-init dnsmasq on the CT).
# Unbound on OPNsense then serves local overrides / recursion for the router and
# for any client still using the gateway as secondary DNS.

# =============================================================================
# opnsense_unbound_host_alias
# =============================================================================

# (no host aliases)
