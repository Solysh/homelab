# homelab repo

Kometa config and Unraid maintenance scripts for a Plex server. **This repo is public.**

## Rules

- Never commit real values: tokens, API keys, passwords, webhook URLs, IPs, domains, hostnames, usernames or family names. Use the `YOUR_...` placeholders already in the files and list any new ones in the README's Placeholders section.
- Real values live only in `private/` (git-ignored) or in `*.local.*` files. Check `git status` and the diff for leaks before every commit.
- Scripts run on Unraid: Bash (`*.sh`), must pass ShellCheck. YAML must pass `yamllint` (see `.yamllint`). Python must pass `ruff check --select E,F`.
- Files use LF line endings (`.gitattributes`).
- CI runs lint (`lint.yml`) and a gitleaks secret scan (`secrets.yml`) on every push.
