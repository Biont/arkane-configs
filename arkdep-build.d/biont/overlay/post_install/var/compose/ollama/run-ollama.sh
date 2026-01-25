#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# Detect ROCm availability
# -------------------------------------------------
detect_rocm() {
  [[ -e /dev/kfd ]] || return 1
  [[ -e /dev/dri ]] || return 1

  if command -v rocminfo >/dev/null 2>&1; then
    rocminfo >/dev/null 2>&1 || return 1
  elif command -v rocm-smi >/dev/null 2>&1; then
    rocm-smi >/dev/null 2>&1 || return 1
  fi

  return 0
}

# -------------------------------------------------
# Detect GFX ID (gfxXXXX)
# -------------------------------------------------
detect_gfx_id() {
  command -v rocminfo >/dev/null 2>&1 || return 1

  local gfx
  gfx="$(rocminfo | awk '/Name:/ && $2 ~ /^gfx[0-9]+/ { print $2; exit }')"

  [[ -n "$gfx" ]] || return 1
  echo "$gfx"
}

# -------------------------------------------------
# Main logic
# -------------------------------------------------
PROFILE="cpu"

if detect_rocm; then
  PROFILE="amd"
  echo "✔ ROCm detected — using AMD GPU profile"

  if GFX_ID="$(detect_gfx_id)"; then
    echo "✔ Detected GPU: $GFX_ID"

    # Apply override only for newer / commonly unsupported GPUs (gfx11+)
    if [[ "$GFX_ID" =~ ^gfx1[1-9] ]]; then
      export HSA_OVERRIDE_GFX_VERSION="11.0.0"
      echo "✔ Setting HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE_GFX_VERSION"
    else
      echo "ℹ GPU is officially supported — no HSA override needed"
    fi
  else
    echo "ℹ Could not determine GFX ID — not setting HSA override"
  fi
else
  echo "ℹ ROCm not detected — falling back to CPU"
fi

# -------------------------------------------------
# Run Docker Compose
# -------------------------------------------------
export COMPOSE_PROFILES="$PROFILE"

docker compose up -d --remove-orphans
