# Network

UniFi gateway, managed switch and Wi-Fi APs. The default posture is **block all between networks**, then allow specific flows.

## Networks

| Network | Purpose | Notes |
|---|---|---|
| Trusted | Adult devices, server | DNS through AdGuard Home only |
| Kids | Kids' tablets and PC | Isolated from other networks, UniFi content filter, app blocking, encrypted DNS blocked, overnight Wi-Fi schedule |
| IoT | Smart home hubs, speakers, printers, Home Assistant | 2.4 GHz only, isolated in an untrusted zone |
| VPN | WireGuard clients | AdGuard Home as the only DNS |
| Management | Network gear | |
| Unused | Default network, no devices | Kept empty on purpose |

Every network runs a DHCP server with 24-hour leases and IPv6 off. Fixed addresses (the server, AdGuard Home, Home Assistant, printers, the speaker) sit outside or are reserved within the DHCP pool.

## Wi-Fi

Each user-facing network has its own SSID, broadcast from every AP.

| Network | Bands | Security | Notes |
|---|---|---|---|
| Trusted | 2.4 + 5 GHz | WPA2/WPA3, PMF optional | Fast roaming, band steering, BSS transition |
| Kids | 2.4 + 5 GHz | WPA2/WPA3, PMF optional | Client isolation, a 100/10 Mbps speed limit, overnight blackout every day |
| IoT | 2.4 GHz only | WPA2, PMF off | Old devices connect more reliably this way. No speed limit or blackout |

**Radios:** 2.4 GHz is fixed at 20 MHz on channels 1 and 11, one per AP. 5 GHz is 80 MHz on non-DFS channels, so radar events never move it. Wireless meshing is off, and every AP has a wired uplink.

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

Zone-based firewall. Trusted and Kids sit in an internal zone; IoT sits in an untrusted zone so cheap devices can't reach anything else. The default between zones is block, and Kids is also isolated from every other internal network. Allowed exceptions are narrow policies, for example:

- Kids to Plex on TCP 32400, scheduled for weekends only (a Plex app block covers Monday to Thursday)
- Kids to the two IoT printers, and nothing else on IoT
- Home Assistant to the server's SMB port, for its backup share
- IoT to the gateway on DNS, DHCP, NTP and mDNS ports plus ICMP, then everything else to the gateway is blocked

Two broader rules are deliberate:

- **Trusted to IoT:** allowed on all ports, one direction only. Return traffic is automatic, so IoT devices still can't start connections into Trusted.
- **VPN to IoT:** allowed, so phones on the VPN can reach smart-home devices by IP. mDNS doesn't cross the tunnel, so discovery still needs the home network.

Kids also has app blocking: YouTube and social media are always blocked, and Plex is blocked Monday to Thursday. The gateway's mDNS proxy is on Auto, which is enough for AirPlay and printer discovery across networks.

## DNS

- **Trusted:** DHCP hands out only the AdGuard Home container. AdGuard uses Hagezi Pro and TIF blocklists with DoH upstreams (Cloudflare, Quad9), and forwards the home domain to the gateway for split-horizon DNS.
- **Blocking bypass:** outbound port 53 from Trusted is blocked, except from AdGuard itself, so hardcoded DNS on devices fails closed.
- **Kids:** UniFi content filtering (ad block, safe search) plus two firewall rules that block DoH/DoT: one matches the apps, the other blocks a dynamic list of public DoH server IPs (Hagezi, refreshed every 24 hours, about 1,500 entries). Port 53 from Kids is redirected to the gateway.
- **IoT:** port 53 is redirected to the gateway too, so devices with hardcoded DNS still resolve through it. The gateway's own upstreams are DoH to Cloudflare's security resolver and Quad9's filtered one.
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

The port 443 forward uses a **dynamic network list** of Cloudflare's IPv4 ranges (refreshed every 24 hours) instead of a static copy. The port 80 forward is paused, since the public services work over HTTPS only. Plex is forwarded to any source, and WireGuard has its own allow rule.

## Remote access

WireGuard server on the gateway (chosen over Tailscale). Phones connect on demand whenever they're off the home Wi-Fi. The gateway keeps the VPN hostname current with Cloudflare dynamic DNS. Teleport is turned off, so WireGuard is the only VPN. The UniFi cloud remote-access option stays on for managing the console, with SSH off.

## Threat management

- **Intrusion Prevention:** on in notify-and-block mode for every network, with all signature categories enabled (the free Standard tier, about 33,000 signatures) and no exclusions.
- **Honeypot:** a decoy address on the IoT network. Any touch triggers a push and email alert.
- **Alerts:** push and email for the honeypot, internet loss and device disconnects, plus UniFi's default system and power alerts.

## Switching and APs

- The 24-port switch is the STP root. A 10G SFP+ link joins it to the gateway.
- The server's two ports form one LACP aggregate with the IoT VLAN tagged on it (the only trunk to a host). Ordinary device ports are edge ports with BPDU guard.
- The hub ports for the lighting systems sit on the IoT network. AP uplinks use a management profile.
- The gateway and switch keep IGMP snooping on, with the switch as querier.

## Console and updates

- The console and the Network app auto-update daily at 3 AM on the Official release channel.
- Config backups run weekly (Thursday, 2 AM) to local storage and the cloud, keeping 10.
- The configuration is documented here by hand. UniFi has no readable export, and its backup file is a restore image only.
