# OPNsense web UI after root console login

You already have **root** on the console or SSH. The management UI is the same **HTTPS** service OPNsense ships by default; you mainly need a reachable **LAN/management IP** and a browser path to it.

## 1. Make sure an interface has an IP you can reach

With five virtio NICs (see **`OpnSenseXML/README.md`**), pick the one that matches how you connect (e.g. **vtnet2** on **vmbr2** for cottage LAN).

From the **root** menu (or run **`opnsense-shell`**):

- **2) Set interface IP address** — set **IPv4** on the interface that is your “inside” / management leg (static is easiest for first login), e.g. **192.168.1.1/24** on the interface plugged into your main LAN.

Or in the UI later: **Interfaces → Assignments** — add interfaces, **Interfaces → [iface] →** enable, **IPv4 Configuration Type: Static**, set address + subnet.

Until at least one inside interface has an IP on a subnet your PC can route to, the web UI will not be reachable from the network.

## 2. Open the web UI

In a browser (from a machine on that subnet):

```text
https://<that-interface-ip>/
```

Examples: `https://192.168.1.1/` if you set that on LAN.

- You will get a **certificate warning** (self-signed). Continue once for this host.
- Log in as **root** with the password you set at install (or the one you configured in the console).

If the page does not load:

- Confirm **HTTPS** (not HTTP) unless you explicitly enabled HTTP in **System → Settings → Administration**.
- From the OPNsense shell: **`configctl webgui restart`** (or **`configctl webgui restart renew`** to regenerate the GUI certificate); or use **Status → Services** in the UI. See [Web GUI access reset](https://docs.opnsense.org/troubleshooting/webgui.html) in the OPNsense docs.

## 3. Tune “proper” management (System → Settings → Administration)

Recommended checks:

| Setting | Suggestion |
|--------|------------|
| **Web GUI** protocol | **HTTPS** only for normal use. |
| **TCP port** | Default **443**; change only if you have a conflict. |
| **Listen interfaces** | Start with **LAN** (or your management interface only). Avoid “All” on WAN-facing boxes once rules are in place. |
| **Secure Shell** | Enable **SSH**, permit password or keys, restrict source in **Firewall → Rules** on the SSH interface. |
| **DNS rebinding** | If you use a **hostname** instead of IP, add your hostname under **Alternate Hostnames** so the UI is not blocked. |

After changes, use **Apply**; you may need to reopen the URL if the listen interface or port changed.

## 4. Run the setup wizard (optional but usual)

**System → Wizard** (or the first-login wizard) sets timezone, DNS, and WAN basics. You can skip or revisit later.

## 5. Lock down later

When VLANs and WANs are configured:

- Keep an **anti-lockout**-style rule so you do not lose GUI access from your management VLAN.
- Restrict **443** (and **SSH**) to **management subnets** via **Firewall → Rules** on the relevant interface(s), matching the intent of **`OpnSenseXML/`** rules.

## Quick reference

- **Default GUI**: `https://<LAN-or-mgmt-IP>/` — user **root**.
- **Console menu**: `opnsense-shell` (or login root and use the menu).
- **Backups before big changes**: **System → Configuration → Backups**.
