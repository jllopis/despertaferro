#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="desperta-test"
CONTAINER="desperta-test-env"

cmd="${1:-shell}"

case "$cmd" in
  build)
    echo "Building $IMAGE..."
    # Context is repo root so COPY zig-out/bin/desperta works
    docker build --platform linux/amd64 -t "$IMAGE" -f "$REPO_ROOT/docker/Dockerfile" "$REPO_ROOT"
    ;;

  shell)
    # Mount the repo read-only at /repo. On shell entry, copy it to a writable
    # location under $HOME — this mirrors what install.sh will do (clone the
    # repo to ~/.local/share/despertaferro) so state files (tracked-paths.txt)
    # can be written.
    docker run --rm -it \
      --platform linux/amd64 \
      --name "$CONTAINER" \
      -v "$REPO_ROOT:/repo:ro" \
      "$IMAGE" bash -c '
        DEST="$HOME/.local/share/despertaferro"
        if [ ! -d "$DEST" ]; then
          mkdir -p "$(dirname "$DEST")"
          cp -r /repo "$DEST"
          echo "copied /repo → $DEST"
        fi
        export DESPERTA_REPO="$DEST"
        cd "$DEST"
        exec bash
      '
    ;;

  # Run with systemd for service testing (needs privileged)
  systemd)
    docker run --rm -it \
      --platform linux/amd64 \
      --privileged \
      --cgroupns host \
      -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      --name "${CONTAINER}-systemd" \
      -v "$REPO_ROOT:/repo:ro" \
      -e DESPERTA_REPO=/repo \
      "$IMAGE" bash
    ;;

  clean)
    docker rmi "$IMAGE" 2>/dev/null || true
    echo "Cleaned"
    ;;

  *)
    echo "usage: $0 <build|shell|systemd|clean>"
    exit 1
    ;;
esac
