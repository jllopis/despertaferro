#!/usr/bin/env sh
set -eu

# One-off maintenance helper for active dotfiles branches.
# This script intentionally uses Git tooling because it rewrites repository
# history outside the normal desperta runtime. Run it on a mirror clone first.

echo "This script rewrites history and may require force-push."
echo "Set DESPERTA_CONFIRM_PURGE=yes to continue."

if [ "${DESPERTA_CONFIRM_PURGE:-}" != "yes" ]; then
  exit 2
fi

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "git-filter-repo is required." >&2
  exit 3
fi

git filter-repo \
  --path .config/zsh/.zsh_history \
  --path .config/zsh/.zcompdump \
  --path .config/zsh/.zcompcache \
  --invert-paths

echo "History rewritten locally. Verify before pushing:"
echo "  git grep -n -I -E '(token|secret|password|passwd|BEGIN|ghp_|eyJ)' --all-match -- ."
echo "Then coordinate any force-push explicitly."

