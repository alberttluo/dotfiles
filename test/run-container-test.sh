#!/usr/bin/env bash
# Build the Rocky 9 image and run a full install + verify inside it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="dotfiles-rocky9-test"

if ! command -v docker >/dev/null 2>&1; then
  printf 'docker is required for the container test and was not found\n' >&2
  exit 1
fi

printf '▶ building %s\n' "$IMAGE"
docker build -q -t "$IMAGE" -f "$ROOT/test/Dockerfile.rocky9" "$ROOT/test"

printf '▶ running install.sh + verify.sh in the container\n'
docker run --rm \
  -v "$ROOT:/dotfiles:ro" \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    cp -R /dotfiles ~/dotfiles
    cd ~/dotfiles
    ./install.sh
    ./verify.sh
  '
