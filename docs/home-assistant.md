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
