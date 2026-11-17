# Network

UniFi gateway, managed switch and Wi-Fi APs. The default posture is **block all between networks**, then allow specific flows.

## Networks

| Network | Purpose | Notes |
|---|---|---|
| Trusted | Adult devices, server | DNS through AdGuard Home only |
| Kids | Kids' tablets and PC | UniFi content filter, encrypted DNS blocked, overnight Wi-Fi schedule |
| IoT | Smart home hubs, speakers, Home Assistant | 2.4 GHz only, isolated in an untrusted zone |
| VPN | WireGuard clients | AdGuard Home as the only DNS |
| Management | Network gear | |

Each user-facing network has its own SSID.

## Server networking

The Unraid server's two NICs are bonded and carry a tagged VLAN for IoT.

| Interface | What it is | Used by |
|---|---|---|
| `bond0` | `eth0` + `eth1`, bonding mode 4 (802.3ad/LACP), MII monitoring every 100 ms; address by DHCP | Unraid itself, Plex (host network), AdGuard Home (own IP) |
| `bond0.4` | VLAN 4 (IoT) on top of the bond | Home Assistant VM |
| `terranet` | User-defined Docker bridge network | All other containers |

The switch ports for `eth0` and `eth1` are configured as one LACP aggregate, with VLAN 4 tagged on it.

### Docker networks

- **`terranet`:** a custom bridge, so containers resolve each other by name and Nginx Proxy Manager can forward to `http://<container>:<port>` without exposing those ports anywhere else. Unraid's "preserve user-defined networks" setting is on, so it survives Docker restarts.
- **AdGuard Home on `bond0`:** Unraid's custom network on the bond gives the container its own LAN IP (`YOUR_ADGUARD_IP`). DNS on port 53 then doesn't clash with anything on the host, and DHCP hands that IP out as the DNS server.
- **Plex on host:** for local network discovery.

## Firewall approach

Zone-based firewall. Trusted and Kids sit in an internal zone; IoT sits in an untrusted zone so cheap devices can't reach anything else. Allowed exceptions are narrow, single-port policies, for example:

- Trusted to the Home Assistant VM on its web port (for the Companion app)
- Kids to Plex on TCP 32400, scheduled for weekends only
- Home Assistant to the server's SMB port, for its backup share

## DNS

- **Trusted:** DHCP hands out only the AdGuard Home container. AdGuard uses Hagezi Pro and TIF blocklists with DoH upstreams (Cloudflare, Quad9), and forwards the home domain to the gateway for split-horizon DNS.
- **Blocking bypass:** outbound port 53 from Trusted is blocked, except from AdGuard itself, so hardcoded DNS on devices fails closed.
- **Kids:** UniFi content filtering plus a firewall rule that blocks DoH/DoT so the filter can't be bypassed.
- **HTTPS records:** AdGuard blocks HTTPS-type DNS records for LAN-only hosts. Cloudflare's ECH otherwise broke LAN access to them.

## Reverse proxy and exposure

- Nginx Proxy Manager terminates TLS with one wildcard Let's Encrypt cert (`*.example.com`), issued via Cloudflare DNS challenge with a scoped API token.
- Ports 80/443 are forwarded **only from Cloudflare's published IP ranges**, so public web services are reachable only through Cloudflare.
- Most hosts use an NPM access list that allows private ranges only. They're reachable remotely through the VPN, not the internet.
- Only a couple of services (audiobooks, media requests) are public.

Proxy hosts (every host forces HTTPS, uses HTTP/2, websockets and NPM's "block common exploits"):

| Service | Upstream | Access |
|---|---|---|
| Seerr | `seerr:5055` | Public |
| audiobookshelf | server IP, port 13378 | Public |
| Sonarr | `sonarr:8989` | Private ranges only |
| Radarr | `radarr:7878` | Private ranges only |
| Prowlarr | `prowlarr:9696` | Private ranges only |
| NZBGet | `nzbget:6789` | Private ranges only |
| Tracearr | `tracearr-supervised:3000` | Private ranges only |
| Unraid web UI | server IP, port 8443 | Private ranges only |
| Home Assistant | VM's IP on the IoT network, port 80 | Private ranges only |

Containers on `terranet` are addressed by name; anything else by IP. See [Containers](containers.md) for ports.

## Remote access

WireGuard server on the gateway (chosen over Tailscale). Phones connect on demand whenever they're off the home Wi-Fi. The gateway keeps the VPN hostname current with Cloudflare dynamic DNS.
