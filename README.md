# homelab

Config files and maintenance scripts for a Plex media server running on Unraid.

- **Kometa config** for three Plex libraries (Movies, TV Shows, TV Shows - Anime): collections, overlays, and age-based content ratings.
- **Bash scripts** for Unraid: a monthly health check, an orphaned-artwork report, a weekly encrypted offsite backup, and three small maintenance scripts.
- **Docs** for the containers, network, Home Assistant VM, schedules and backups.

Every key, token, and address has been replaced with a placeholder. Nothing here works until you fill in your own values (see [Placeholders](#placeholders)).

## What's in here

| File | What it does |
| --- | --- |
| `config.yml` | Main [Kometa](https://kometa.wiki) config: libraries, overlays, rating sources, and connections to Plex, TMDb, Tautulli, Radarr, Sonarr, MDBList and MyAnimeList |
| `apprise.yml` | Where Kometa sends its notifications (a Discord webhook) |
| `kids-movies.yml`, `kids-tv.yml` | A "Kids" smart collection in each library, built from age ratings |
| `anime-ratings.yml` | Age ratings from MyAnimeList for anime that Common Sense Media doesn't rate |
| `anime-ratings2.yml` | Hand-set ratings for anime that neither source covers |
| `tv-ratings.yml` | Hand-set ratings for TV shows that Common Sense Media doesn't cover |
| `anime-ratings-fetch.py` | Generates `anime-ratings.yml` from MAL ratings via mapping.animemap.dev (see [below](#anime-ratings-fetchpy)) |
| `monthly-health.sh` | Monthly server health check with one summary notification |
| `log-alerts.sh` | Every 5 minutes: alerts on security, admin and disk events found in VictoriaLogs, through apprise-api |
| `orphan-assets-report.sh` | Read-only report of artwork folders whose movie or show is gone |
| `weekly-offsite.sh` | Weekly encrypted copy of the newest appdata backup to Dropbox |
| `apm-fix.sh` | Sets drive APM to 254 at array start, so drives stop parking their heads constantly |
| `delete-dangling-images.sh` | Removes untagged Docker images left by updates |
| `docker-log-size.sh` | Lists the largest container log files |

## Docs

- [Containers](docs/containers.md): the 17 running containers with image, network, ports, paths and settings
- [Network](docs/network.md): networks, Wi-Fi, server bond and VLAN, Docker networks, firewall approach, DNS filtering, reverse proxy, remote access, threat management, switching and console settings
- [Home Assistant](docs/home-assistant.md): the Home Assistant OS VM and how it's isolated
- [Nightly schedule](docs/nightly-schedule.md): the order of the overnight jobs, User Scripts schedules, and the Plex database corruption that set them
- [Backups](docs/backups.md): daily, semi-monthly and offsite backup tiers

## Kometa setup

### Content ratings

The goal is a numeric age rating on every title, so the Kids collections can filter on it.

1. **Common Sense Media first.** Each library runs `mass_metadata_update` with `plex_csm` as the content-rating source.
2. **MyAnimeList as the anime fallback.** The anime library falls back to `mal`, with a mapping from MAL's rating labels to ages (for example `PG-13 - Teens 13 or older` becomes `13`).
3. **Hand-set values for the rest.** The `*-ratings.yml` metadata files cover titles neither source rates.

Items carrying the Plex label `Manual Metadata` are skipped, so manual fixes aren't overwritten.

### Kids collections

`kids-movies.yml` collects movies rated for ages 3 to 12. `kids-tv.yml` collects shows rated for ages 3 to 10. Both are smart collections, so they update as ratings change.

### Collections and overlays

- **Movies:** Kometa's default `basic`, `imdb`, `seasonal` (US-only holidays turned off) and `universe` collections, with resolution, audio codec, ratings and ribbon overlays.
- **TV Shows and Anime:** `basic` plus `imdb` or `anilist` collections, with status and ribbon overlays on shows, and resolution, audio codec, video format, episode info and runtime overlays on episodes.

### Backups

Each library writes an undo file (`*_Backup.yml`) before changing ratings. Those files list the whole media library, so `.gitignore` keeps them out of this repo.

## Scripts

The Bash scripts run on Unraid. The three main ones and report through Unraid's built-in notification script, which can forward to Discord or any other agent you've set up. Run them on a schedule, for example with the User Scripts plugin (schedules in [Nightly schedule](docs/nightly-schedule.md#user-scripts)).

### `monthly-health.sh`

Checks the server and sends one summary. It looks at:

- Docker containers that aren't running
- Web UIs that don't answer (a container can be up while the app inside is hung)
- Array state, parity sync errors, and disabled or invalid disks
- Pool fullness (warns at 95%) and ZFS pool health
- VMs that aren't running
- Whether the latest appdata backup finished and is recent
- `CRITICAL` lines in the Kometa log
- Database lock or corruption messages in the Plex logs
- SMART health, plus CRC error counts compared with last month
- The age of the newest offsite copy on Dropbox
- Logging: VictoriaLogs disk use against its size cap (warns at 90%, when the oldest logs start being dropped before the 1-year retention), whether the UniFi gateway, Unraid syslog, containers and NPM all sent logs in the last 24 hours, and whether `log-alerts.sh` completed a run in the last hour. Skipped if `VL_DIR` doesn't exist.

Edit `HOSTIP`, `SERVICES`, `EXPECT_DRIVES`, `CAP_LIMIT`, `VL_CAP_GIB` and `GATEWAY_HOST` at the top to match your server.

Test it without sending a notification:

```bash
NONOTIFY=1 bash /boot/config/plugins/health-check/monthly-health.sh
```

### `log-alerts.sh`

Runs every 5 minutes and queries [VictoriaLogs](docs/containers.md#victoria-logs) for events since its last run, then sends one message through apprise-api (falling back to Unraid's notification script if apprise-api doesn't answer). It alerts on:

- UniFi security events (IPS detections, honeypot hits and similar). Firewall-policy blocks are left out.
- UniFi admin logins and setting changes, shortened to one line each (e.g. `claude changed firewall policy "Block IoT to Gateway" from <ip>`). `IGNORE_ADMINS` skips named accounts, such as one used by automation.
- Disk and I/O errors in the Unraid syslog (ATA errors, medium errors, `md` read/write errors, ZFS checksum errors)
- One client getting 20 or more 401/403 responses from Nginx Proxy Manager within 10 minutes (once per client per hour)
- The UniFi syslog going silent for 30 minutes, or no container logs for an hour (Vector stopped)
- VictoriaLogs not answering for 3 runs in a row (so a restart for an update doesn't alert)

Each run covers the time since the previous one, so events are not missed or sent twice. If VictoriaLogs is down or a query fails, the window doesn't move forward and the next run catches up. State is kept in `/mnt/user/appdata/log-alerts`. Each section lists up to 10 events (`MAX_LINES`) before "...and N more", and the whole message is cut at a line end before Discord's 2000-character limit.

Settings are at the top and can be overridden with environment variables, so the User Script wrapper can set the real values without editing the script. Test it without sending anything:

```bash
NONOTIFY=1 STATE_DIR=/tmp/log-alerts-test bash /boot/config/plugins/log-alerts/log-alerts.sh
```

### `orphan-assets-report.sh`

Finds Kometa or Posterizarr asset folders whose movie or show no longer has video files on disk, then reports the count and total size. It never moves or deletes anything.

Two safety checks stop false alarms: it exits if the media scan comes back empty, and it warns instead of reporting if more than 25% of a library looks orphaned.

### `weekly-offsite.sh`

Copies the newest Appdata Backup folder to an encrypted rclone remote (`dropbox-crypt:`), then:

- Waits up to 90 minutes for a running backup to finish
- Refuses to upload a backup older than 3 days
- Verifies file sizes after the upload
- Keeps the newest 4 remote copies and prunes the rest

It needs an rclone config with a crypt remote of that name. Test it without changing anything:

```bash
DRY=1 bash /boot/config/plugins/rclone/weekly-offsite.sh
```

### `anime-ratings-fetch.py`

A workaround from when Kometa's MyAnimeList lookups broke (the Jikan API went offline). It reads AniDB IDs from Kometa's own logs, looks up each show's MAL rating through [mapping.animemap.dev](https://mapping.animemap.dev), converts it to the numeric age scale, and writes a Kometa metadata file. Anything it can't resolve is listed for you to handle by hand rather than guessed.

Run it inside the Kometa container (the Unraid host has no Python):

```bash
docker exec Kometa python3 /config/anime-ratings-fetch.py /config/logs /config/anime-ratings.yml
```

## Placeholders

Replace these before using the files:

| Placeholder | Where | What to put |
| --- | --- | --- |
| `YOUR_SERVER_IP` | `config.yml`, `monthly-health.sh`, `log-alerts.sh`, `docs/containers.md` | LAN IP of your server |
| `YOUR_APPRISE_KEY` | `log-alerts.sh` | Config key of the apprise-api configuration to notify |
| `YOUR_GATEWAY_HOSTNAME`, `YOUR_UNRAID_HOSTNAME` | `log-alerts.sh` (the gateway one also in `monthly-health.sh`) | Hostnames the UniFi gateway and Unraid use in their syslog |
| `YOUR_PLEX_TOKEN` | `config.yml` | Plex token |
| `YOUR_TMDB_API_KEY` | `config.yml` | TMDb API key |
| `YOUR_TAUTULLI_API_KEY` | `config.yml` | Tautulli API key |
| `YOUR_MDBLIST_API_KEY` | `config.yml` | MDBList API key |
| `YOUR_RADARR_API_KEY` | `config.yml` | Radarr API key |
| `YOUR_SONARR_API_KEY` | `config.yml` | Sonarr API key |
| `YOUR_MAL_CLIENT_ID`, `YOUR_MAL_CLIENT_SECRET` | `config.yml` | MyAnimeList API client |
| `YOUR_WEBHOOK_ID`, `YOUR_WEBHOOK_TOKEN` | `apprise.yml` | The two parts of a Discord webhook URL |
| `YOUR_ADGUARD_IP` | `docs/containers.md`, `docs/network.md` | Fixed LAN IP for the AdGuard Home container |
| `YOUR_NZBGET_USER`, `YOUR_NZBGET_PASSWORD` | `docs/containers.md` | NZBGet web UI login |
| `YOUR_PLEX_CLAIM` | `docs/containers.md` | Claim token from plex.tv/claim (first start only) |

The `mal: authorization:` block in `config.yml` is empty on purpose. Kometa fills it in after you authorize MyAnimeList.

## Notes

- Paths such as `/mnt/user/appdata/...` and `/boot/config/plugins/...` are Unraid defaults. Change them if your shares are laid out differently.
- Library names (`Movies`, `TV Shows`, `TV Shows - Anime`) must match the names in your Plex server.
- The Radarr and Sonarr quality profiles and root folders in `config.yml` are specific to this setup.
- GitHub Actions lint the repo on every push (ShellCheck, yamllint, Ruff) and scan it for secrets with gitleaks. Dependabot opens monthly PRs to update the actions.

## License

[MIT](LICENSE). Use and adapt anything here.
