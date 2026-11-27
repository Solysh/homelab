# Containers

The 19 Docker containers running on the Unraid server, from their Unraid templates. Values that identify the server (IPs, logins, tokens) are left out or shown as placeholders.

## Conventions

- **Network:** everything is on the custom bridge network `terranet`, so containers reach each other by name (for example Nginx Proxy Manager forwards to `http://sonarr:8989`). Two exceptions: Plex uses the host network, and AdGuard Home gets its own LAN IP on `bond0` (see [Network](network.md)).
- **User:** `PUID=99`, `PGID=100` (Unraid's `nobody:users`) unless noted.
- **Paths:** `/mnt/user/appdata/<app>` for config, `/mnt/user/media/library/...` for media, `/mnt/user/downloads/` for downloads. NZBGet and the *arr apps all map downloads to the same `/downloads` path, so no remote path mappings are needed.
- **Logs:** Docker log rotation is on (10 MB × 3 files per container).

## Summary

| Container | Image | Network | Ports (host:container) | Proxied by NPM |
|---|---|---|---|---|
| AdGuard-Home | `adguard/adguardhome` | `bond0` (own IP) | 53/tcp, 53/udp, 3000 (web) | no |
| apprise-api | `lscr.io/linuxserver/apprise-api` | terranet | 8010:8000 | no |
| audiobookshelf | `ghcr.io/advplyr/audiobookshelf` | terranet | 13378:80 | yes, public |
| chaptarr | `chaptarr/chaptarr:latest` | terranet | 8789 | no |
| clonarr | `ghcr.io/prophetse7en/clonarr:latest` | terranet | 6060 | no |
| Kometa | `kometateam/kometa` | terranet | none | no |
| Maintainerr | `ghcr.io/maintainerr/maintainerr:latest` | terranet | 6246 | no |
| npm (Nginx Proxy Manager) | `jc21/nginx-proxy-manager` | terranet | 80, 443, 81 (admin) | n/a |
| nzbget | `lscr.io/linuxserver/nzbget` | terranet | 6789 | yes, LAN/VPN only |
| plex | `lscr.io/linuxserver/plex` | host | 32400 | no |
| posterizarr | `ghcr.io/fscorrupt/posterizarr:latest` | terranet | 8000 | no |
| prowlarr | `lscr.io/linuxserver/prowlarr` | terranet | 9696 | yes, LAN/VPN only |
| radarr | `lscr.io/linuxserver/radarr` | terranet | 7878 | yes, LAN/VPN only |
| Seerr | `ghcr.io/seerr-team/seerr:latest` | terranet | 5055 | yes, public |
| sonarr | `lscr.io/linuxserver/sonarr:develop` | terranet | 8989 | yes, LAN/VPN only |
| tautulli | `tautulli/tautulli` | terranet | 8181 | no |
| tracearr-supervised | `ghcr.io/connorgallopo/tracearr:supervised` | terranet | 3001:3000 | yes, LAN/VPN only |
| vector | `timberio/vector:latest-alpine` | terranet | none | no |
| victoria-logs | `victoriametrics/victoria-logs` | terranet | 9428 (web), 5514/udp+tcp (syslog) | no |

Updates: the Appdata Backup plugin updates containers right after backing them up (see [Nightly schedule](nightly-schedule.md)). Exceptions: it doesn't stop or update [AdGuard Home](#adguard-home), and it neither stops nor archives [victoria-logs](#victoria-logs), though it still updates it.

## Per container

### AdGuard-Home

DNS filtering for the Trusted and VPN networks. On `bond0` with a fixed LAN IP (`YOUR_ADGUARD_IP`) so it can serve port 53 directly.

| Container path | Host path |
|---|---|
| `/opt/adguardhome/work` | `/mnt/user/appdata/adguard/workingdir` |
| `/opt/adguardhome/conf` | `/mnt/user/appdata/adguard/config` |

Appdata Backup: "Skip stopping of container?" is "Yes", so DNS stays up during the nightly run, and "Update container after backup?" is "No". The working folder is excluded; the configuration is still archived.

### apprise-api

Apprise notification API: apps post one HTTP request and it fans out to the configured services.

| Container path / variable | Value |
|---|---|
| `/config` | `/mnt/user/appdata/apprise-api` |
| `APPRISE_ATTACH_SIZE` | `0` (attachments off) |

### audiobookshelf

Audiobook server, public through NPM.

| Container path | Host path |
|---|---|
| `/audiobooks` | `/mnt/user/media/library/books/audiobooks/` |
| `/config` | `/mnt/user/appdata/audiobookshelf` |
| `/metadata` | `/mnt/user/appdata/audiobookshelf/metadata/` |

### chaptarr

Books and audiobooks manager (an *arr fork). Uses SQLite; the PostgreSQL variables in its template are left blank.

| Container path / variable | Value |
|---|---|
| `/config` | `/mnt/user/appdata/chaptarr/config` |
| `/audiobooks` | `/mnt/user/media/library/books/audiobooks/` |
| `/ebooks` | `/mnt/user/media/library/books/ebooks/` |
| `/downloads` | `/mnt/user/downloads/` |
| `UMASK` | `002` |
| `TZ` | `America/New_York` |

### clonarr

| Container path | Host path |
|---|---|
| `/config` | `/mnt/user/appdata/clonarr` |

### Kometa

Runs once a day at 08:30 with low CPU priority. Config is [`config.yml`](../config.yml) in this repo.

| Container path / variable | Value |
|---|---|
| `/config` | `/mnt/user/appdata/Kometa` |
| `KOMETA_TIME` | `08:30` |
| `LOW_PRIORITY` | `True` |

All other `KOMETA_*` switches are at their defaults.

### Maintainerr

Removes watched or stale media by rule. Evaluates rules at 00:30.

| Container path / variable | Value |
|---|---|
| `/opt/data` | `/mnt/user/appdata/maintainerr` |
| `TZ` | `America/New_York` |
| Extra Parameters | `--user 1000:1000` |

### npm (Nginx Proxy Manager)

Reverse proxy and TLS for everything web-facing. The appdata folder keeps its old name from an earlier install.

| Container path / variable | Value |
|---|---|
| `/data` | `/mnt/user/appdata/Nginx-Proxy-Manager-Official/data` |
| `/etc/letsencrypt` | `/mnt/user/appdata/Nginx-Proxy-Manager-Official/letsencrypt` |
| `/var/log` | `/tmp/Nginx-Proxy-Manager-Official/var/log` (in RAM, cleared on reboot; nginx's own log only) |
| `DB_SQLITE_FILE` | `/data/database.sqlite` |
| Extra Parameters | `--memory=1G --no-healthcheck` |

Per-host access and error logs are in `/data/logs` (persistent, rotated weekly, 4 weeks kept) and are shipped to victoria-logs by vector.

Real visitor IPs: the sites sit behind Cloudflare, so `data/nginx/custom/server_proxy.conf` (included in every proxy host) sets `real_ip_header CF-Connecting-IP;`. NPM already trusts Cloudflare's ranges, so logs and access lists see the visitor's IP instead of Cloudflare's. The header is only honoured from trusted addresses, so it can't be spoofed by hitting the server directly.

### nzbget

Usenet downloader.

| Container path / variable | Value |
|---|---|
| `/config` | `/mnt/user/appdata/nzbget` |
| `/downloads` | `/mnt/user/downloads/` |
| `NZBGET_USER` | `YOUR_NZBGET_USER` |
| `NZBGET_PASS` | `YOUR_NZBGET_PASSWORD` |

### plex

On the host network so local discovery works without extra port mappings. Hardware transcoding through `/dev/dri`.

| Container path / variable | Value |
|---|---|
| `/library` | `/mnt/user/media/library/` |
| `/transcode` | `/mnt/cache/system/plex-transcode` |
| `/config` | `/mnt/user/appdata/plex` |
| Device | `/dev/dri` |
| `VERSION` | `docker` (update by pulling the image) |
| `PLEX_CLAIM` | `YOUR_PLEX_CLAIM` (only needed on first start) |
| Extra Parameters | `--stop-timeout=120` (clean shutdown during backups) |

### posterizarr

Artwork generator. Writes straight into Kometa's asset folder, and runs at 04:30 so new art is ready before Kometa.

| Container path / variable | Value |
|---|---|
| `/config` | `/mnt/user/appdata/posterizarr` |
| `/assets` | `/mnt/user/appdata/Kometa/assets` |
| `/manualassets` | `/mnt/user/appdata/posterizarr/manualassets` |
| `/assetsbackup` | `/mnt/user/appdata/posterizarr/assetsbackup` |
| `RUN_TIME` | `disabled` |
| `UMASK` | `002` |
| Extra Parameters | `--user 99:100` |

### prowlarr

Indexer manager for Radarr and Sonarr.

| Container path | Host path |
|---|---|
| `/config` | `/mnt/user/appdata/prowlarr` |

### radarr

| Container path | Host path |
|---|---|
| `/movies` | `/mnt/user/media/library/movies/` |
| `/downloads` | `/mnt/user/downloads/` |
| `/config` | `/mnt/user/appdata/radarr` |

### Seerr

Media requests, public through NPM.

| Container path / variable | Value |
|---|---|
| `/app/config` | `/mnt/user/appdata/seerr` |
| `/app/config/logs` | `/mnt/user/appdata/seerr/logs` |
| `PORT` | `5055` |
| `LOG_LEVEL` | `debug` |
| Extra Parameters | `--init --user 99:100` |

### sonarr

On the `develop` tag.

| Container path | Host path |
|---|---|
| `/tv` | `/mnt/user/media/library/tv/` |
| `/downloads` | `/mnt/user/downloads/` |
| `/config` | `/mnt/user/appdata/sonarr` |

### tautulli

Plex statistics. Kometa reads popularity data from it.

| Container path / variable | Value |
|---|---|
| `/config` | `/mnt/user/appdata/tautulli` |
| `TZ` | `EST` |

### tracearr-supervised

Plex stream monitoring. The `supervised` image bundles its own PostgreSQL and Redis, so its data lives on the cache pool directly (`/mnt/cache`), not through the user-share layer.

| Container path / variable | Value |
|---|---|
| `/data/postgres` | `/mnt/cache/appdata/tracearr/postgres` |
| `/data/redis` | `/mnt/cache/appdata/tracearr/redis` |
| `/data/tracearr` | `/mnt/cache/appdata/tracearr/data` |
| `TZ` | `America/New_York` |
| `PG_MAX_MEMORY` | `2GB` |
| `JWT_SECRET`, `COOKIE_SECRET` | blank (auto-generated) |
| Extra Parameters | `--restart=unless-stopped --shm-size=512m` |

### vector

Ships logs to victoria-logs:

- Every container's stdout/stderr, labelled with `container_name`, `stream`, `image` and `host`. Reads through the Docker socket (read-only), so new containers are picked up automatically and no template needs a log-driver change. Ships only lines written after it starts. Its own logs are excluded to avoid a feedback loop.
- Nginx Proxy Manager's access and error log files, as `container_name=npm` with `stream=access` or `stream=error`. Access lines are parsed into `vhost`, `method`, `uri`, `status`, `upstream_status`, `client`, `length`, `user_agent`, `referer` and `upstream`, with the timestamp from the line. Rotated `.gz` files are skipped.

Read checkpoints in `/var/lib/vector` let it resume after a restart without duplicates.

| Container path / setting | Value |
|---|---|
| `/var/run/docker.sock` | `/var/run/docker.sock` (read-only) |
| `/npm-logs` | `/mnt/user/appdata/Nginx-Proxy-Manager-Official/data/logs` (read-only) |
| `/etc/vector/vector.yaml` | `/mnt/user/appdata/vector/vector.yaml` (read-only) |
| `/var/lib/vector` | `/mnt/user/appdata/vector/data` |
| Post Arguments | `--config /etc/vector/vector.yaml` |
| Extra Parameters | `--memory=256M` |

The config sends to `http://victoria-logs:9428/insert/elasticsearch/` with `VL-Stream-Fields: host,container_name,stream`.

### victoria-logs

Long-term store for all container logs and NPM access logs (from vector), Unraid's own syslog (Settings > Syslog Server > remote server `127.0.0.1` port 5514 UDP; Unraid keeps it only in RAM otherwise) and UniFi syslog: the gateway's (firewall, port-forward and system events) plus the switch's and access points' own logs (link up/down, spanning tree, Wi-Fi association and roaming). The gateway itself keeps only about 24 hours and Docker's rotation keeps about 30 MB per container. Search UI at `http://YOUR_SERVER_IP:9428/select/vmui/`, LAN only with no login, so it isn't proxied. Syslog is on 5514 rather than 514 so it never clashes with Unraid's own syslog server.

| Container path / setting | Value |
|---|---|
| `/vlogs` | `/mnt/user/appdata/victoria-logs` |
| Post Arguments | `-storageDataPath=/vlogs -retentionPeriod=1y -retention.maxDiskSpaceUsageBytes=20GiB -syslog.listenAddr.udp=:5514 -syslog.listenAddr.tcp=:5514 -syslog.timezone=America/New_York` |
| Extra Parameters | `--memory=1G` |

Alerts: [`log-alerts.sh`](../README.md#log-alertssh) queries it every 5 minutes and notifies through apprise-api.

Appdata Backup: under advanced options, "Skip backup?" is "Yes, skip backup and do stop/start only" and "Skip stopping of container?" is "Yes", so the nightly run neither stops it (no syslog gap) nor archives up to 20 GiB of logs. The top-level "Skip?" stays "No", so the plugin still updates it after the backup ("Update container after backup?" follows the global setting). Don't use the top-level skip or exclude `/mnt/user/appdata/victoria-logs` instead: a full skip also drops the update, and excluding its only volume makes the plugin warn every night that it "does not have any volume to back up". Log history isn't backed up: a lost drive loses it, while the settings above rebuild the container.

Retention: 1 year or 20 GiB, whichever comes first; the oldest data is dropped first. In UniFi: Settings > CyberSecure > Traffic Logging > Activity Logging (SIEM server) pointing at `YOUR_SERVER_IP` port 5514, with every content category on except Firewall Default Policy (too noisy). The switch and access points send their logs directly rather than through the gateway, so they need a firewall rule allowing the network-gear VLAN to reach the server on UDP 5514, placed above any rule that blocks that VLAN from the server's network.
