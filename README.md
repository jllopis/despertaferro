# despertaferro

`despertaferro` turns a fresh CachyOS / Arch install into a fully-configured
workstation with a single command, then keeps the dotfiles synced through a
Git-backed runtime that lives entirely behind a CLI.

It's an opinionated personal tool — not a generic dotfiles manager — but the
mechanism is general: package catalog + dotfile templates + tracked paths in a
bare repo, all driven by `desperta`.

## Quickstart

On a fresh CachyOS Minimal install (no GUI required to bootstrap):

```sh
curl -fsSL https://raw.githubusercontent.com/jllopis/despertaferro/master/scripts/install.sh | bash
```

That's it. The script will:

1. Install base tools (`git`, `base-devel`, `curl`) and `yay` (AUR helper).
2. Clone this repo to `~/.local/share/despertaferro`.
3. Build the `desperta` binary with `zig`.
4. Run `desperta bootstrap --apply`, which:
   - installs every package in your active profile,
   - deploys dotfile templates to `$HOME` and `$XDG_CONFIG_HOME`,
   - enables systemd services, adds you to relevant groups (e.g. `docker`),
   - changes your login shell (if `zsh` is in the profile),
   - tracks the deployed files in a bare Git repo for snapshot/sync.

Re-login afterwards so the new shell and group memberships take effect, then
run `desperta doctor` to confirm everything is in order.

### Just want to try it? Test profile

The `test` profile installs only 11 essential CLI tools (zsh, neovim, tmux, fzf,
ripgrep, zoxide, btop, jq, starship, curl, wget). Useful for a quick spin in a
VM or container:

```sh
curl -fsSL https://raw.githubusercontent.com/jllopis/despertaferro/master/scripts/install.sh \
  | bash -s -- --profile test
```

## Concepts

**Host** — a single machine identified by its hostname. Each host has one or
more profiles assigned in the manifest.

**Profile** — a named subset of the package catalog, e.g. `base` (everyday CLI
tools), `hyprland` (desktop), `work` (work-only stuff), `test` (minimal subset
for CI/VMs). A package can be in multiple profiles.

**Template** — files under `dotfiles/default/` get copied to `$HOME` (`home/`
subtree) and `$XDG_CONFIG_HOME` (`config/` subtree). Host-specific overrides
live in `dotfiles/<hostname>/`. Templates are seed configs — they don't
overwrite existing files unless you pass `--force`.

**Tracked path** — files registered in `tracked-paths.txt` and staged in the
bare Git repo at `$XDG_STATE_HOME/despertaferro/repo.git`. `desperta snapshot`
copies them out for inspection; `desperta status` reports drift between
worktree and index.

### Two repos, not one

There are two separate Git repos in play and it's important to keep them apart:

- **The project repo** (this one). Holds the desperta source, dotfile
  templates, and package catalog. Cloned by `install.sh` into
  `~/.local/share/despertaferro`.
- **Your personal dotfiles repo** (created locally by `desperta init` /
  `bootstrap` at `~/.local/state/despertaferro/repo.git`). This is the bare
  Git repo that holds *your actual deployed configs*, one branch per host
  (`hosts/<hostname>`).

Today the personal dotfiles repo is **local only** — nothing is pushed to a
remote yet. To sync across machines you'll set `[git] remote = "..."` in
`desperta.toml` (pointing at a **private** repo of your own) and run
`desperta sync` (coming — see `planning/next-phase.md`).

Until `desperta sync` ships, use the local snapshot/index for inspection and
optionally push the bare repo manually with `git -C ~/.local/state/despertaferro/repo.git push <url> hosts/<hostname>`.

## Common commands

```sh
desperta status                       # overview: branch, tracked, clean/modified
desperta doctor                       # health check (manifest, denylist, runtime)
desperta list --host <profile>        # show packages in a profile + install state

desperta bootstrap --apply            # full first-time setup (uses manifest host)
desperta bootstrap --apply --profile test     # use a specific profile, ignore manifest
desperta bootstrap --apply --force            # overwrite existing dotfiles
desperta bootstrap --apply --from other-host  # start from another host's templates
desperta bootstrap --apply --adopt other-host # take over another host's identity

desperta track ~/.config/nvim         # add a path to tracked-paths.txt and index
desperta ignore "*.log"               # add a denylist pattern
desperta snapshot                     # materialize tracked files to a snapshot dir

desperta service status               # systemd services from active profiles
desperta service enable syncthing     # enable+start a user service
desperta service enable --system docker
```

Every command that mutates state runs as **dry-run by default**; pass `--apply`
to execute. JSON output is available on most commands with `--json`.

See `planning/bootstrap-test-log.md` for the full feature matrix and the
issues that have been fixed during development.

## Where things live

| Path | Purpose |
|---|---|
| `~/.local/share/despertaferro/` | The repo itself (cloned by `install.sh`) |
| `~/.local/state/despertaferro/repo.git/` | Bare repo backing `track`/`snapshot`/`sync` |
| `~/.config/despertaferro/config.toml` | Runtime config (repo_path, work_tree) |
| `~/.cache/despertaferro/snapshots/` | `desperta snapshot` outputs |
| `dotfiles/default/` (in this repo) | Seed templates deployed by `bootstrap` |
| `config/packages.toml` (in this repo) | Package catalog |
| `config/denylist.txt` (in this repo) | Glob patterns excluded from tracking |
| `desperta.toml` (in this repo) | Manifest: hosts ↔ profiles, remote URL |

## Build from source

```sh
zig build                                          # native build → zig-out/bin/desperta
zig build -Doptimize=ReleaseSafe                   # optimized
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe  # static Linux binary
zig build test                                     # run unit tests
```

Requires Zig 0.16. `install.sh` installs it for you on Arch-based systems.

## Testing in a Docker container

A ready-made Dockerfile for end-to-end testing on CachyOS lives in `docker/`:

```sh
# build the image (uses a pre-built static binary from zig-out/bin/desperta)
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
bash docker/run.sh build

# open a shell as a non-root user with sudo and yay configured
bash docker/run.sh shell

# inside the container:
desperta bootstrap --apply --profile test
```

The container is ephemeral — exiting throws everything away.

## Reference

- [`docs/usage.md`](docs/usage.md) — full command reference with flags and examples
- [`planning/purpose.md`](planning/purpose.md) — design intent and scope
- [`planning/plan.md`](planning/plan.md) — implementation plan
- [`planning/next-phase.md`](planning/next-phase.md) — what's coming
- [`planning/bootstrap-test-log.md`](planning/bootstrap-test-log.md) — bug log and validation history

## Status

The bootstrap path is operational and validated end-to-end on CachyOS:

- 8-phase bootstrap (pre-flight → update → init → resolve → install → deploy → post-install → track → summary)
- Dotfile templates with skip-if-exists semantics
- Package catalog with services, groups, post-install commands, font-cache flag
- Native Git backend: bare repo with worktree status, index staging, snapshots
- Idempotent re-runs (skips re-installs, re-deploys, re-chsh)

Pending (see `planning/next-phase.md`):

- Pre-built binary releases (skip Zig install on clients)
- `desperta sync` (commit + push the index to the remote)
- `loginctl enable-linger` automation for user services
