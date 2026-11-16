# Backups

Three tiers, each covering a different failure.

| Tier | What | Schedule | Retention | Protects against |
|---|---|---|---|---|
| Daily | Appdata Backup plugin, all containers plus flash | 02:00 daily | 30 days, keep at least 10 | Corruption, bad updates |
| Snapshot | Copy of the daily archive, by post-run script | 1st and 15th | 24 (about a year) | Comparing or recovering older config |
| Offsite | Newest archive, rclone crypt remote to Dropbox | Sundays 02:45 | Newest 4 | Losing the server |

## Notes

- Backup shares are **array only**, never the cache NVMe they protect.
- Large regenerable data (Posterizarr's artwork assets) is excluded. Including it took the archive from under 10 GB to 46 GB.
- The offsite job ([`weekly-offsite.sh`](../weekly-offsite.sh)) is bandwidth-capped at 1 MB/s and sends an Unraid notification (to Discord) on success or failure.
- Snapshots are written outside the plugin's folder so its retention can't prune them.
- The rclone config (with crypt passwords) lives on the flash drive and is **not** in this repo.
- The Unraid license key and server details are kept in a password manager.
- Home Assistant writes its own backups to a dedicated SMB share.
