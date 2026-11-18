# homelab repo

Kometa config and Unraid maintenance scripts for a Plex server. **This repo is public.**

## Rules

- Never commit real values: tokens, API keys, passwords, webhook URLs, IPs, domains, hostnames, usernames or family names. Use the `YOUR_...` placeholders already in the files and list any new ones in the README's Placeholders section.
- Real values live only in `private/` (git-ignored here; it is its own separate private repo, so commit real values there, never here) or in `*.local.*` files. Check `git status` and the diff for leaks before every commit.
- Scripts run on Unraid: Bash (`*.sh`), must pass ShellCheck. YAML must pass `yamllint` (see `.yamllint`). Python must pass `ruff check --select E,F`.
- Files use LF line endings (`.gitattributes`).
- CI runs lint (`lint.yml`) and a gitleaks secret scan (`secrets.yml`) on every push. GitHub secret scanning and push protection are also on; treat them as a second layer, not a replacement for checking the diff.
- Commit and push only when asked, and never use `--no-verify`.
- Never commit secret-bearing files: `secrets.yaml`, `.storage/`, certificates, databases or `*_Backup.yml`. Home Assistant config comes from an unencrypted backup, and only `configuration.yaml` and `automations.yaml` are kept (in `private/`).
- A local pre-commit guard in `.git/hooks` (not pushed; a fresh clone lacks it) blocks private IPs, token-like strings and words from `blocked-words.txt`. If it's missing, reinstall it before committing.
