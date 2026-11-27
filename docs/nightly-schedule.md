# Nightly schedule

| Time | Job | Runtime |
|---|---|---|
| 00:30 | Maintainerr rule evaluation | minutes |
| 03:00 | Appdata Backup (stop, back up, start each container; [exceptions](containers.md#summary)) | ~20 min |
| 03:45 Sun | Encrypted offsite copy to Dropbox | ~3 h at the current size |
| 04:00 | UniFi OS and Network auto-update | only when there's an update |
| 04:30 | Posterizarr artwork run | minutes |
| 04:30 Sun | Weekly User Scripts | |
| 05:00 to 08:00 | Plex scheduled tasks window | |
| 08:30 | Kometa (`--low-priority`) | ~90 min |

## Other scheduled jobs

| Job | Schedule |
|---|---|
| Parity check | First Sunday of January, April, July and October, from 00:00, in daily 2-hour increments. No corrections written. |
| Mover Tuning | Daily at 10:00 and 22:00. The built-in mover schedule is disabled. |
| SSD TRIM | Sundays 10:00 |

## User Scripts

Run by the User Scripts plugin. The three repo scripts are installed under `/boot/config/plugins/...`, and each User Script is a one-line wrapper that calls it.

| Script | Schedule | Repo file |
|---|---|---|
| `monthly-health` | 1st of the month, 12:00 (`0 12 1 * *`) | [`monthly-health.sh`](../monthly-health.sh) |
| `log-alerts` | Every 5 minutes (`*/5 * * * *`) | [`log-alerts.sh`](../log-alerts.sh) |
| `orphan-assets-report` | 15th of the month, 11:00 (`0 11 15 * *`) | [`orphan-assets-report.sh`](../orphan-assets-report.sh) |
| `offsite-backup` | Sundays 03:45 (`45 3 * * 0`) | [`weekly-offsite.sh`](../weekly-offsite.sh) |
| `APM Fix` | At array start | [`apm-fix.sh`](../apm-fix.sh) |
| `delete_dangling_images` | Weekly (Sundays 04:30) | [`delete-dangling-images.sh`](../delete-dangling-images.sh) |
| `viewDockerLogSize` | Weekly (Sundays 04:30) | [`docker-log-size.sh`](../docker-log-size.sh) |
| `delete.ds_store` | Weekly (Sundays 04:30) | none (deletes macOS `.DS_Store` files under `/mnt/user`; stock community script) |
| `fix_docker_client` | Disabled | none (old fix for Unraid 6.7's update check; not needed since 6.8) |
| `unlock nvidia` | Disabled | none (third-party NVIDIA encode-session patch) |

## Why this order

- **Backup at 03:00.** It ran at 02:00 until November 2026. Plex playback history showed far less use at 03:00.
- **Offsite copy after the backup starts.** The script waits for a backup that's already running. If it started first, it would upload the previous day's backup and still report success. Move it whenever the backup moves.
- **UniFi updates after the backup**, so a gateway restart doesn't cut off the image pulls for container updates. On a Sunday it can still interrupt the offsite upload.
- **Posterizarr before Kometa**, so fresh artwork is on disk when Kometa applies assets and overlays. It starts 30 minutes after the UniFi update to give the network time to come back.
- **Nothing overlaps Plex maintenance.** Plex's window originally sat at 02:00 to 05:00, right on top of the backup. The backup plugin stopped Plex mid-maintenance and corrupted the database several nights in a row. Moving the window to 05:00 to 08:00 then collided with Kometa at 05:00, so Kometa moved to 08:30.
- **Plex gets a 120 s stop timeout** (`--stop-timeout=120` in Extra Parameters) so it can shut down cleanly when the backup stops it.
- **Nothing heavy in the evening**, when the server is in use. Mover Tuning's 22:00 run only moves files once the cache passes its usage threshold.
- **One automatic container updater.** The backup plugin updates containers right after backing them up ([exceptions](containers.md#summary)). Community Applications' Docker auto-update is off so the two don't race.

## Recovering from Plex DB corruption

If corruption happens anyway:

1. Stop Plex.
2. Run `PRAGMA integrity_check;` with the Plex SQLite binary to find the damaged table.
3. `REINDEX` clears index errors.
4. For row damage, dump with `.recover` into a fresh database and swap it in.
5. Re-run `integrity_check` before starting Plex.

Restoring the nightly appdata backup is the fallback.
