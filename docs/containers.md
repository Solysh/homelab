# Containers

The 17 Docker containers running on the Unraid server, from their Unraid templates. Values that identify the server (IPs, logins, tokens) are left out or shown as placeholders.

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

Updates: the Appdata Backup plugin updates each container right after backing it up (see [Nightly schedule](nightly-schedule.md)).

## Per container

### AdGuard-Home

DNS filtering for the Trusted and VPN networks. On `bond0` with a fixed LAN IP (`YOUR_ADGUARD_IP`) so it can serve port 53 directly.

| Container path | Host path |
|---|---|
| `/opt/adguardhome/work` | `/mnt/user/appdata/adguard/workingdir` |
| `/opt/adguardhome/conf` | `/mnt/user/appdata/adguard/config` |

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
| `/var/log` | `/tmp/Nginx-Proxy-Manager-Official/var/log` (in RAM, cleared on reboot) |
| `DB_SQLITE_FILE` | `/data/database.sqlite` |
| Extra Parameters | `--memory=1G --no-healthcheck` |

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

Artwork generator. Writes straight into Kometa's asset folder, and runs at 03:00 so new art is ready before Kometa.

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
