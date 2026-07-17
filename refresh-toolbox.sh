#!/usr/bin/env bash
# (Re)create the Unsloth Studio toolbox from the published image.
# Works with Fedora Toolbx (podman) or Distrobox (Ubuntu and others).
# Adapted from kyuz0's Strix Halo toolboxes (https://github.com/kyuz0).

set -e

TOOLBOX_NAME="unsloth-rocm-7.2"
IMAGE_REPO="ghcr.io/justin-noel/amd-strix-halo-unsloth-toolboxes"
TAG="${1:-rocm-7.2}"
IMAGE="${IMAGE_REPO}:${TAG}"

# GPU access for ROCm inside the container
OPTIONS="--device /dev/dri --device /dev/kfd --group-add video --group-add render --security-opt seccomp=unconfined"

# Detect container manager (toolbox requires podman; distrobox works with either)
if command -v toolbox &>/dev/null && command -v podman &>/dev/null; then
    MANAGER="toolbox"
elif command -v distrobox &>/dev/null; then
    MANAGER="distrobox"
else
    echo "Error: neither 'toolbox' (with podman) nor 'distrobox' is installed." >&2
    exit 1
fi

# Detect container runtime for image pull and cleanup
if command -v podman &>/dev/null; then
    RUNTIME="podman"
elif command -v docker &>/dev/null; then
    RUNTIME="docker"
else
    echo "Error: neither 'podman' nor 'docker' is installed." >&2
    exit 1
fi

echo "🔄 Refreshing $TOOLBOX_NAME via $MANAGER (image: $IMAGE)"

# Remove existing container if it exists
if $MANAGER list 2>/dev/null | grep -q "$TOOLBOX_NAME"; then
    echo "🧹 Removing existing $MANAGER: $TOOLBOX_NAME"
    $MANAGER rm -f "$TOOLBOX_NAME"
fi

echo "⬇️ Pulling image: $IMAGE"
$RUNTIME pull "$IMAGE"

new_id="$($RUNTIME image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || true)"
new_digest="$($RUNTIME image inspect --format '{{.Digest}}' "$IMAGE" 2>/dev/null || true)"

echo "📦 Recreating $MANAGER: $TOOLBOX_NAME"
echo "   Options: $OPTIONS"

if [ "$MANAGER" = "toolbox" ]; then
    # toolbox passes extra flags to podman via '--'
    toolbox create "$TOOLBOX_NAME" --image "$IMAGE" -- $OPTIONS
else
    # distrobox passes extra flags via --additional-flags
    distrobox create -n "$TOOLBOX_NAME" --image "$IMAGE" --additional-flags "$OPTIONS"
fi

# --- Cleanup: keep only the most recent image for this tag ---
repo="${IMAGE%:*}"

while read -r id ref dig; do
    if [[ "$id" != "$new_id" ]]; then
        $RUNTIME image rm -f "$id" >/dev/null 2>&1 || true
    fi
done < <($RUNTIME images --digests --format '{{.ID}} {{.Repository}}:{{.Tag}} {{.Digest}}' \
         | awk -v ref="$IMAGE" -v ndig="$new_digest" '$2==ref && $3!=ndig')

while read -r id; do
    $RUNTIME image rm -f "$id" >/dev/null 2>&1 || true
done < <($RUNTIME images --format '{{.ID}} {{.Repository}}:{{.Tag}}' \
         | awk -v r="$repo" '$2==r":<none>" {print $1}')
# --- end cleanup ---

echo "✅ $TOOLBOX_NAME refreshed (image: $IMAGE)"
echo "   Enter it with:  $MANAGER enter $TOOLBOX_NAME"
echo "   Then run:       start-unsloth-studio"
