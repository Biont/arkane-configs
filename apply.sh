#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <image-name>"
    echo "Example: $0 biont"
    exit 1
fi

IMAGE="$1"

# Acquire sudo credentials once and keep them alive throughout the build
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null" EXIT

echo "Building image: $IMAGE"
sudo arkdep-build "$IMAGE"

echo "Moving image to cache..."
sudo mv target/"$IMAGE"*.tar.zst /arkdep/cache/

echo "Deploying image..."
sudo arkdep deploy cache "$IMAGE"

echo "Clearing build directory..."
rm -rf target/*
