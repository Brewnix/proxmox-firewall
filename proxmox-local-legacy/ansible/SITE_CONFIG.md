# Site Configuration Integration

The `site.yml` master playbook is designed to load configuration directly from site YAML files in `config/sites/` and make it available to all individual playbooks.

## Configuration Loading Process

1. **Site Detection**: Site name is determined from `--limit` parameter or inventory hostname
2. **Config Loading**: Loads `config/sites/{site_name}.yml`
3. **Fact Distribution**: Makes site configuration available to all hosts
4. **Compatibility Layer**: Creates `group_vars/{site_name}.yml` for existing playbooks

## Site Configuration Structure

The site configuration file should follow this structure:

```yaml
site:
  name: "mysite"
  display_name: "My Production Site"
  network_prefix: "10.100"
  domain: "mysite.local"
  
  hardware:
    network:
      vlans:
        - id: 10
          name: "main"
          subnet: "10.100.10.0/24"
          dhcp: true
        - id: 20
          name: "cameras"
          subnet: "10.100.20.0/24"
          dhcp: true
  
  proxmox:
    host: "proxmox.mysite.local"
    node_name: "pve"
  
  vm_templates:
    opnsense:
      enabled: true
    tailscale:
      enabled: true
    zeek:
      enabled: false
  
  security:
    suricata:
      enabled: true
  
  backup:
    enabled: true
    schedule: "0 2 * * *"
    retention: 7
  
  credentials:
    proxmox_api_secret: "MYSITE_PROXMOX_API_SECRET"
    opnsense_api_key_env: "OPNSENSE_API_KEY"
    opnsense_api_secret_env: "OPNSENSE_API_SECRET"

devices:
  nas:
    ip_address: "10.100.10.100"
    vlan_id: 10
    config_file: "config/devices/mysite/nas.yml"
```

## Available Variables in Playbooks

After loading, the following variables are available in all playbooks:

- `site_config`: Complete site configuration
- `site_devices`: Device configurations  
- `site_name`: Site name
- `network_prefix`: Network prefix (e.g., "10.100")
- `domain`: Site domain

## Environment Variables

The playbook automatically detects required environment variables from the site configuration's `credentials` section. Any value that looks like an environment variable name (ALL_CAPS with underscores) will be checked.

## Backward Compatibility

For compatibility with existing playbooks that expect `group_vars`, the master playbook automatically generates:

- `group_vars/{site_name}.yml` with all site configuration
- Proper variable mapping for OPNsense and other service playbooks

## Usage Examples

### Deploy complete site:
```bash
ansible-playbook site.yml --limit mysite
```

### Deploy only security components:
```bash
ansible-playbook site.yml --limit mysite --tags security
```

### Deploy with specific site config:
```bash
ansible-playbook site.yml -e site_name=mysite
```

## Verification

The playbook will:
1. Validate site configuration exists
2. Check all required environment variables
3. Display configuration summary
4. Test service connectivity after deployment
5. Provide comprehensive deployment report 
