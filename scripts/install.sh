#!/usr/bin/env bash
# despertaferro — one-shot bootstrap for a fresh CachyOS Minimal install.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jllopis/despertaferro/master/scripts/install.sh | bash
#   bash install.sh [--profile <name>] [--force]
#
# What it does:
#   1. pre-flight checks (uid, sudo, disk space, network)
#   2. install base tools (git, base-devel, curl)
#   3. install yay (AUR helper) if missing
#   4. clone despertaferro to ~/.local/share/despertaferro
#   5. build the desperta binary from source (release binaries WIP)
#   6. run `desperta bootstrap --apply`  (forwards --profile and --force if given)
#   7. print a re-login reminder + manual steps
#
# Notes:
#   - You may be prompted for sudo password at multiple points (pacman, makepkg).
#   - You will be prompted for YOUR OWN password by `chsh` if zsh is in the profile.
#   - Re-login is required after to pick up the new shell and group memberships.

set -euo pipefail

# --- options ----------------------------------------------------------------
PROFILE=""
FORCE=""
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      EXTRA_ARGS+=(--profile "$2")
      shift 2
      ;;
    --force)
      FORCE="--force"
      EXTRA_ARGS+=(--force)
      shift
      ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# --- helpers ----------------------------------------------------------------
log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- pre-flight -------------------------------------------------------------
log "despertaferro bootstrap"

[[ $(id -u) -ne 0 ]] || die "do not run as root"

command -v sudo &>/dev/null || die "'sudo' is required but not in PATH"
command -v pacman &>/dev/null || die "this script targets Arch-based systems (pacman not found)"

# Resolve username defensively (Docker / minimal envs leave $USER unset)
USERNAME="${USER:-${LOGNAME:-$(id -un)}}"
HOMEDIR="${HOME:-$(getent passwd "$USERNAME" | cut -d: -f6)}"
[[ -n "$HOMEDIR" && -d "$HOMEDIR" ]] || die "cannot resolve home directory for $USERNAME"

# Disk space: pacman + AUR builds need a few GB; full profile needs more.
# We only abort on clearly insufficient (< 5 GB on /); warn between 5–10 GB.
avail_kb=$(df -Pk / | awk 'NR==2 {print $4}')
avail_gb=$(( avail_kb / 1024 / 1024 ))
if (( avail_gb < 5 )); then
  die "insufficient disk space on / (${avail_gb} GB free, need >= 5 GB)"
elif (( avail_gb < 10 )); then
  warn "low disk space on / (${avail_gb} GB free) — full profile may fail"
fi

# Network sanity check
if ! curl -fsS --max-time 5 -o /dev/null https://archlinux.org/; then
  warn "network probe failed — pacman may not be able to fetch packages"
fi

log "user=$USERNAME  home=$HOMEDIR  disk=${avail_gb}G"

# --- base tools -------------------------------------------------------------
log "syncing pacman + installing base tools"
sudo pacman -Sy --noconfirm --needed git curl base-devel || die "pacman base-devel install failed"

# --- AUR helper -------------------------------------------------------------
if command -v yay &>/dev/null || command -v paru &>/dev/null; then
  log "AUR helper present — skipping"
else
  log "installing yay (AUR helper)"
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"
  (cd "$tmpdir/yay-bin" && makepkg -si --noconfirm) || die "yay install failed"
  rm -rf "$tmpdir"
  trap - EXIT
fi

# --- clone / update repo ----------------------------------------------------
REPO="${XDG_DATA_HOME:-$HOMEDIR/.local/share}/despertaferro"
mkdir -p "$(dirname "$REPO")"

if [[ -d "$REPO/.git" ]]; then
  log "updating repo at $REPO"
  git -C "$REPO" pull --ff-only || warn "git pull failed — continuing with existing checkout"
else
  log "cloning repo to $REPO"
  git clone --depth 50 https://github.com/jllopis/despertaferro.git "$REPO" \
    || die "git clone failed"
fi

# --- build desperta binary --------------------------------------------------
BIN="$HOMEDIR/.local/bin/desperta"
mkdir -p "$(dirname "$BIN")"

# Release binaries aren't published yet; build from source.
# When releases land, prepend a curl attempt here and fall through to build on miss.
log "building desperta from source (zig build)"
if ! command -v zig &>/dev/null; then
  log "installing zig"
  sudo pacman -S --noconfirm --needed zig || die "zig install failed"
fi
(cd "$REPO" && zig build -Doptimize=ReleaseSafe) || die "zig build failed"
cp "$REPO/zig-out/bin/desperta" "$BIN"
chmod +x "$BIN"

# --- run bootstrap ----------------------------------------------------------
export PATH="$HOMEDIR/.local/bin:$PATH"
export DESPERTA_REPO="$REPO"

log "running: desperta bootstrap --apply ${EXTRA_ARGS[*]:-}"
log "(you may be prompted for your password by sudo and/or chsh)"
echo ""
cd "$REPO"
desperta bootstrap --apply "${EXTRA_ARGS[@]}"

# --- post-install reminders -------------------------------------------------
echo ""
log "bootstrap complete"
cat <<EOF

next steps:
  - re-login (or reboot) to pick up shell + group membership changes
  - then run: desperta doctor
  - manual configuration:
      op signin              # 1Password
      gcloud auth login      # Google Cloud
      aws configure          # AWS
      edit ~/.gitconfig      # name + email

EOF
