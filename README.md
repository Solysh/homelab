# homelab

Config files and maintenance scripts for a Plex media server running on Unraid.

- **Kometa config** for three Plex libraries (Movies, TV Shows, TV Shows - Anime): collections, overlays, and age-based content ratings.
- **Three Bash scripts** for Unraid: a monthly health check, an orphaned-artwork report, and a weekly encrypted offsite backup.

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
| `monthly-health.sh` | Monthly server health check with one summary notification |
| `orphan-assets-report.sh` | Read-only report of artwork folders whose movie or show is gone |
| `weekly-offsite.sh` | Weekly encrypted copy of the newest appdata backup to Dropbox |

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

All three run on Unraid and report through Unraid's built-in notification script, which can forward to Discord or any other agent you've set up. Run them on a schedule, for example with the User Scripts plugin.

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

Edit `HOSTIP`, `SERVICES`, `EXPECT_DRIVES` and `CAP_LIMIT` at the top to match your server.

Test it without sending a notification:

```bash
NONOTIFY=1 bash /boot/config/plugins/health-check/monthly-health.sh
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

## Placeholders

Replace these before using the files:

| Placeholder | Where | What to put |
| --- | --- | --- |
| `YOUR_SERVER_IP` | `config.yml`, `monthly-health.sh` | LAN IP of your server |
| `YOUR_PLEX_TOKEN` | `config.yml` | Plex token |
| `YOUR_TMDB_API_KEY` | `config.yml` | TMDb API key |
| `YOUR_TAUTULLI_API_KEY` | `config.yml` | Tautulli API key |
| `YOUR_MDBLIST_API_KEY` | `config.yml` | MDBList API key |
| `YOUR_RADARR_API_KEY` | `config.yml` | Radarr API key |
| `YOUR_SONARR_API_KEY` | `config.yml` | Sonarr API key |
| `YOUR_MAL_CLIENT_ID`, `YOUR_MAL_CLIENT_SECRET` | `config.yml` | MyAnimeList API client |
| `YOUR_WEBHOOK_ID`, `YOUR_WEBHOOK_TOKEN` | `apprise.yml` | The two parts of a Discord webhook URL |

The `mal: authorization:` block in `config.yml` is empty on purpose. Kometa fills it in after you authorize MyAnimeList.

## Notes

- Paths such as `/mnt/user/appdata/...` and `/boot/config/plugins/...` are Unraid defaults. Change them if your shares are laid out differently.
- Library names (`Movies`, `TV Shows`, `TV Shows - Anime`) must match the names in your Plex server.
- The Radarr and Sonarr quality profiles and root folders in `config.yml` are specific to this setup.
- `anime-ratings.yml` mentions a generator script, `anime-ratings-fetch.py`. It isn't included here.

## License

[MIT](LICENSE). Use and adapt anything here.
