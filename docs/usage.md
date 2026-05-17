# desperta — command reference

Every state-changing command runs as **dry-run by default**. Pass `--apply` to
execute. The `--json` flag produces structured output on commands that support
it (mostly `track`, `ignore`, `sync`).

Where this document says "the manifest" it means `desperta.toml` at the repo
root (or wherever `DESPERTA_REPO` points). The bare Git repo holding tracked
state is referred to as "the index" or "the bare repo".

---

## bootstrap

```
desperta bootstrap [--apply] [--profile <name>] [--from <host>|--adopt <host>] [--force]
```

End-to-end first-time setup. Runs 8 phases in order:

| Phase | Does |
|---|---|
| 0 — pre-flight | Refuses to run as root; checks `sudo`, `yay`/`paru`, manifest path, OS |
| 1 — system update | `sudo pacman -Syu --noconfirm` on Linux (no-op on macOS) |
| 2 — init repo | Creates the bare repo at `~/.local/state/despertaferro/repo.git` if absent |
| 3 — resolve profiles | Looks up hostname in manifest; `--profile` bypasses; falls back to `base` |
| 4 — install packages | `pacman` for repo packages, `yay` for AUR (or `brew` on macOS) |
| 5 — deploy dotfiles | Copies templates to `$HOME` and `$XDG_CONFIG_HOME`, **skip-if-exists** |
| 6 — post-install | systemd services, group memberships, `chsh`, font cache, `post_cmd` |
| 7 — track configs | Appends paths to `tracked-paths.txt` and stages files into the index |
| 8 — summary | Re-login reminder + manual steps (1Password, gcloud, aws, gitconfig) |

### Flags

| Flag | Meaning |
|---|---|
| `--apply` | Without this, bootstrap prints what it *would* do but executes nothing. |
| `--profile <name>` | Skip the manifest lookup; use this profile name directly. Useful for CI or testing a subset (`--profile test`). |
| `--from <host>` | Use the dotfile templates from `dotfiles/<host>/` but keep your own hostname as the active host. |
| `--adopt <host>` | Take over another host's identity: register this machine as `<host>` in the manifest and use its profiles + templates. |
| `--force` | In phase 5, overwrite existing files at destination instead of skipping. |

### Examples

```sh
# Standard first-time install (uses manifest)
desperta bootstrap --apply

# Quick test profile for a VM / container
desperta bootstrap --apply --profile test

# Migrating a config to a new machine, but keeping it as an independent host
desperta bootstrap --apply --from old-laptop

# Replacing an old machine — adopt its identity
desperta bootstrap --apply --adopt old-laptop

# Re-apply templates, overwriting local edits (destructive)
desperta bootstrap --apply --force
```

### Idempotency

A second `bootstrap --apply` on the same machine is mostly a no-op:

- Phase 4 reports "all installed".
- Phase 5 reports `deployed: 0, skipped: N`.
- Phase 6 skips `chsh` if your shell already matches the target.
- Phase 7 re-stages files (no change → identical SHAs in index).

---

## status

```
desperta status
```

Prints runtime info: manifest, worktree path, bare repo path, active branch,
and tracked-file status (`tracked / clean / modified / deleted`).

Useful as a "where am I?" overview.

---

## doctor

```
desperta doctor
```

Health check. Verifies presence of:

- `desperta.toml` (manifest) and its schema version
- `config/denylist.txt` plus the must-have patterns (zsh history, log, env, pem, …)
- `config/tracked-paths.txt`
- Runtime config (`~/.config/despertaferro/config.toml`)
- Bare repo path and worktree path consistency between manifest and runtime
- Host count and snapshot policy

All checks should report `ok:`. Anything else means follow-up.

---

## list

```
desperta list [--host <profile>]
```

Lists all packages in the catalog and whether they're installed. Without
`--host`, shows everything available for the current platform.

Columns: `package | status | profile | description`.

The `profile` column shows all profiles the package belongs to, comma-separated.

### Examples

```sh
desperta list                # everything for this OS
desperta list --host base    # packages in the 'base' profile only
desperta list --host test    # minimal CLI subset
```

---

## install

```
desperta install [--apply] [--host <profile>]
```

Installs packages from the given profile (defaults to `base`). Without
`--apply`, prints the install plan.

This is a subset of what `bootstrap` does — useful when you just want more
packages without re-running the full bootstrap flow.

```sh
desperta install --apply --host hyprland
```

---

## track

```
desperta track [--json] <path>...
```

Adds one or more paths to `tracked-paths.txt`. Paths that match a pattern in
`config/denylist.txt` are refused.

`bootstrap` does this automatically for deployed files; use `track` when you
add a new config by hand and want it under desperta's eye.

```sh
desperta track ~/.config/wezterm/wezterm.lua
desperta track ~/.config/some/dir/        # directories are walked recursively at snapshot
```

> **Note**: `track` does not (yet) stage files into the Git index — `bootstrap`
> phase 7 does that. A future `desperta sync` will close the gap.

---

## ignore

```
desperta ignore <pattern>...
```

Adds glob patterns to `config/denylist.txt`. Patterns can match the full
relative path or the basename.

```sh
desperta ignore "*.bak"
desperta ignore "**/cache/*"
```

The denylist is consulted at every `track` and at index staging.

---

## sync

```
desperta sync [--apply] [--json]
```

Re-reads `tracked-paths.txt` and stages everything into the index of the
**personal dotfiles bare repo** at `~/.local/state/despertaferro/repo.git`.
Today this overlaps with `bootstrap` phase 7.

In the next iteration (see `planning/next-phase.md`) `sync` will also commit
and push to a remote set in `desperta.toml`:

```toml
[git]
remote = "git@github.com:youruser/your-dotfiles.git"   # PRIVATE recommended
```

The push always targets the branch `hosts/<hostname>` — one branch per
machine, no manifest field controls this.

> **Note**: there are two distinct repos. The *project repo* (this codebase)
> is cloned by `install.sh` and lives under `~/.local/share/despertaferro`.
> The *personal dotfiles repo* is a separate bare repo under
> `~/.local/state/despertaferro/repo.git`. The remote in `desperta.toml`
> applies to the personal repo, not the project. The project's location is
> implicit (the binary knows where it was built from).

---

## snapshot

```
desperta snapshot
```

Copies every file in the current index to a fresh directory under
`~/.cache/despertaferro/snapshots/<unix-timestamp>/`. Used for safe inspection
of what desperta is "seeing" without touching live configs.

If the index is empty (`bootstrap` not run yet, or `track` called but never
synced), prints `no tracked files yet`.

---

## migrate

```
desperta migrate --from <host> --to <host>
```

Helper for renaming/duplicating a host in the manifest. Most users use
`bootstrap --from` or `--adopt` instead; `migrate` is the lower-level
plumbing.

---

## init

```
desperta init [--host <name>]
```

Creates the bare repo at `~/.local/state/despertaferro/repo.git`, writes
`HEAD`, `config`, and an empty `tracked-paths.txt`. Called implicitly by
`bootstrap` phase 2, but you can run it standalone for a tracking-only setup
without the package install side.

---

## service

```
desperta service install [--apply]
desperta service status
desperta service enable [--system] <name>
```

Manage systemd services declared by the active profile's packages.

- `service install` — enable + start every `service_user` / `service_system`
  defined by installed packages.
- `service status` — table of services and their `active`/`inactive` state per
  scope.
- `service enable <name>` — enable a single service. Defaults to user scope;
  pass `--system` for system scope (uses `sudo`).

Requires an active user session (`$XDG_RUNTIME_DIR` set) for `--user` services.
If that's missing, run `loginctl enable-linger $USER` first.

---

## Global flags

| Flag | Effect | Commands |
|---|---|---|
| `--apply` | Execute instead of dry-run | `bootstrap`, `install`, `sync`, `service install` |
| `--json` | Structured JSON output | `track`, `ignore`, `sync` |
| `--host <name>` | Reuse as filter or target | `list`, `install`, `bootstrap`, `init` |
| `--profile <name>` | Override profile selection | `bootstrap` |
| `--from <host>` | Source templates from another host | `bootstrap` |
| `--adopt <host>` | Take ownership of another host identity | `bootstrap` |
| `--force` | Overwrite existing dotfiles | `bootstrap` |
| `--system` | Target system scope (vs user) | `service enable` |

## Environment variables

| Variable | Used by | Purpose |
|---|---|---|
| `DESPERTA_REPO` | All commands | Override path to the repo (defaults to cwd) |
| `DESPERTA_REPO_PATH` | All commands | Override bare repo path |
| `DESPERTA_WORKTREE` | All commands | Override worktree path |
| `XDG_CONFIG_HOME` | `bootstrap` phase 5 | Where to deploy `config/` templates |
| `XDG_STATE_HOME` | All commands | Where to default the bare repo |
| `XDG_DATA_HOME` | `install.sh` | Where to clone the repo |
| `XDG_RUNTIME_DIR` | `service enable --user` | Detect active user session |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Operation failed (specific error printed to stderr) |
| `2` | Invalid arguments / usage error |

## Tips

- Run `desperta doctor` after every `bootstrap` to confirm the runtime is sane.
- Run `desperta status` whenever you're unsure what's tracked.
- Manual edits to `tracked-paths.txt` and `denylist.txt` are allowed — desperta
  re-reads them on every command. Comment lines start with `#`.
