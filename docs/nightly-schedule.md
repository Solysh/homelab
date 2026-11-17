# Nightly schedule

| Time | Job | Runtime |
|---|---|---|
| 00:30 | Maintainerr rule evaluation | minutes |
| 02:00 | Appdata Backup (stop, back up, start each container) | ~45 min |
| 02:45 Sun | Encrypted offsite copy to Dropbox | varies |
| 03:00 | Posterizarr artwork run | minutes |
| 05:00 to 08:00 | Plex scheduled tasks window | |
| 08:30 | Kometa (`--low-priority`) | ~90 min |

## User Scripts

Run by the User Scripts plugin. The three repo scripts are installed under `/boot/config/plugins/...`, and each User Script is a one-line wrapper that calls it.

| Script | Schedule | Repo file |
|---|---|---|
| `monthly-health` | 1st of the month, 12:00 (`0 12 1 * *`) | [`monthly-health.sh`](../monthly-health.sh) |
| `orphan-assets-report` | 15th of the month, 11:00 (`0 11 15 * *`) | [`orphan-assets-report.sh`](../orphan-assets-report.sh) |
| `offsite-backup` | Sundays 02:45 (`45 2 * * 0`) | [`weekly-offsite.sh`](../weekly-offsite.sh) |
| `APM Fix` | At array start | [`apm-fix.sh`](../apm-fix.sh) |
| `delete_dangling_images` | Weekly | [`delete-dangling-images.sh`](../delete-dangling-images.sh) |
| `viewDockerLogSize` | Weekly | [`docker-log-size.sh`](../docker-log-size.sh) |
| `delete.ds_store` | Weekly | none (deletes macOS `.DS_Store` files under `/mnt/user`; stock community script) |
| `fix_docker_client` | Disabled | none (old fix for Unraid 6.7's update check; not needed since 6.8) |
| `unlock nvidia` | Disabled | none (third-party NVIDIA encode-session patch) |

## Why this order

- **Posterizarr before Kometa**, so fresh artwork is on disk when Kometa applies assets and overlays.
- **Nothing overlaps Plex maintenance.** Plex's window originally sat at 02:00 to 05:00, right on top of the backup. The backup plugin stopped Plex mid-maintenance and corrupted the database several nights in a row. Moving the window to 05:00 to 08:00 then collided with Kometa at 05:00, so Kometa moved to 08:30.
- **Plex gets a 120 s stop timeout** (`--stop-timeout=120` in Extra Parameters) so it can shut down cleanly when the backup stops it.
- **Nothing heavy in the evening**, when the server is in use.
- **One container updater.** The backup plugin updates each container right after backing it up. Community Applications' Docker auto-update is off so the two don't race.

## Recovering from Plex DB corruption

If corruption happens anyway:

1. Stop Plex.
2. Run `PRAGMA integrity_check;` with the Plex SQLite binary to find the damaged table.
3. `REINDEX` clears index errors.
4. For row damage, dump with `.recover` into a fresh database and swap it in.
5. Re-run `integrity_check` before starting Plex.

Restoring the nightly appdata backup is the fallback.
