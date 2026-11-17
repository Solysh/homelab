# Home Assistant

Home Assistant OS runs as a VM on the Unraid server rather than as a container, so add-ons and OS updates work as intended.

## VM spec

| Setting | Value |
|---|---|
| Machine | Q35, UEFI (OVMF) |
| CPU | 2 vCPUs, host-passthrough, pinned to two host threads |
| Memory | 4 GB |
| Disk | HAOS image on the `vms` share (cache only), virtio |
| Network | virtio-net, macvtap (direct) on the VLAN interface `bond0.4` (IoT network) |
| Guest agent | QEMU guest agent channel enabled |
| Console | VNC, bound to `127.0.0.1` |

## Network placement

The VM's NIC sits on `bond0.4`, so Home Assistant lives on the IoT network with the devices it controls instead of on the Trusted network. The firewall then allows only:

- Trusted to Home Assistant's web port (for the Companion app, and for Nginx Proxy Manager, which proxies it for LAN and VPN clients)
- Home Assistant to the server's SMB port, for its backups to the `ha-backups` share

See [Network](network.md).

## VNC bound to localhost

Unraid's default VM template listens for VNC on all interfaces with no password. The VNC server is bound to `127.0.0.1` instead, so it's reachable only through the Unraid web UI's noVNC console (which is already behind the Unraid login), not from the LAN.

In the VM's XML:

```xml
<graphics type='vnc' port='5900' autoport='yes' websocket='5700' listen='127.0.0.1'>
  <listen type='address' address='127.0.0.1'/>
</graphics>
```

Make the change in the VM's XML view, and re-check it after editing the VM in form view.

## Backups

Home Assistant's own backup (Settings > System > Backups) writes to the `ha-backups` share over SMB. That share is on the array, not the cache, and is outside the appdata backup.

## Configuration

Most configuration is managed through the UI and stored in `.storage/`, which isn't tracked here. The YAML files are:

- `configuration.yaml`: stock (`default_config`, themes folder), with automations, scripts and scenes split into their own files via `!include`.
- `scripts.yaml`, `scenes.yaml`: empty.
- `automations.yaml`: one automation, below.

### Automations

**Garage door open at night.** Sends a Pushover notification (priority 1) if the garage door sensor is on at 22:00, or if the door is opened between 22:00 and 06:00 and stays open for 10 minutes. It repeats every 15 minutes until the door closes. Mode is `single`, so a running reminder loop isn't duplicated.
