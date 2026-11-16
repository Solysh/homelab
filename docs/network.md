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

## Remote access

WireGuard server on the gateway (chosen over Tailscale). Phones connect on demand whenever they're off the home Wi-Fi. The gateway keeps the VPN hostname current with Cloudflare dynamic DNS.
