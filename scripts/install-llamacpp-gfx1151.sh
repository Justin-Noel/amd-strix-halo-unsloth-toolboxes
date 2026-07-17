#!/usr/bin/env bash
# Build-time: replace Studio's bundled CPU llama.cpp with the ROCm gfx1151
# prebuilt of the SAME unslothai/llama.cpp release.
#
# Why: Unsloth's installer picks the CPU asset during `docker build` (no GPU
# visible), so Studio's chat/GGUF inference would run CPU-only. The fork's
# releases ship a rocm-gfx1151 asset with identical CLI flags.
#
# The prebuilt bundles a TheRock HSA runtime whose GpuAgent::InitDma()
# SIGSEGVs on gfx1151 with recent kernels; the system ROCm 7.2 HSA runtime
# (hsa-rocr, pulled in via hip-runtime-amd) works, so we symlink it over
# the bundled copy.

set -euo pipefail

LLAMA_DIR=/opt/unsloth/studio/llama.cpp
INFO="$LLAMA_DIR/UNSLOTH_PREBUILT_INFO.json"

[ -f "$INFO" ] || { echo "ERROR: $INFO not found — Studio install layout changed?" >&2; exit 1; }

RELEASE_TAG="$(python3 -c "import json; print(json.load(open('$INFO'))['release_tag'])")"
REPO="$(python3 -c "import json; print(json.load(open('$INFO'))['published_repo'])")"
ASSET="app-${RELEASE_TAG}-linux-x64-rocm-gfx1151.tar.gz"
URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${ASSET}"

echo "==> Replacing bundled CPU llama.cpp with $ASSET"
curl -fsSL -o /tmp/llama-rocm.tar.gz "$URL"

cd "$LLAMA_DIR/build"
rm -rf bin.cpu
mv bin bin.cpu
mkdir bin
tar xzf /tmp/llama-rocm.tar.gz -C bin
rm /tmp/llama-rocm.tar.gz
# CPU backend libs double as the fallback; drop the old tree to save space
rm -rf bin.cpu

echo "==> Using system ROCm HSA runtime instead of the bundled TheRock one"
[ -f /opt/rocm/lib/libhsa-runtime64.so.1 ] || { echo "ERROR: system libhsa-runtime64 missing" >&2; exit 1; }
mv bin/libhsa-runtime64.so.1 bin/libhsa-runtime64.so.1.therock
ln -s /opt/rocm/lib/libhsa-runtime64.so.1 bin/libhsa-runtime64.so.1

chmod -R a+rwX "$LLAMA_DIR/build/bin"

echo "==> Wrapping llama-server to force --no-mmap"
# Studio launches $LLAMA_DIR/llama-server (normally a symlink). On Strix
# Halo mmap paging over GTT is slow and fragments unified memory, so force
# --no-mmap on every launch (appended after Studio's args; llama.cpp
# parsing is last-wins, and users can still override per-load via Studio's
# extra-args field).
rm -f "$LLAMA_DIR/llama-server"
cat > "$LLAMA_DIR/llama-server" <<'EOF'
#!/usr/bin/env bash
exec /opt/unsloth/studio/llama.cpp/build/bin/llama-server "$@" --no-mmap
EOF
chmod 0755 "$LLAMA_DIR/llama-server"

# No GPU at build time: verify the swap structurally (HIP backend present,
# binary loadable). Device visibility is checked at runtime/CI differently.
[ -f bin/libggml-hip.so.0 ] || { echo "ERROR: HIP backend lib missing from asset" >&2; exit 1; }
[ -x bin/llama-server ] || { echo "ERROR: llama-server missing from asset" >&2; exit 1; }
echo "OK llama.cpp $RELEASE_TAG (rocm-gfx1151) installed"
