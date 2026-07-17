#!/usr/bin/env bash
# Build-time installer: Unsloth Studio + ROCm 7.2 PyTorch for gfx1151.
#
# Runs inside `docker build` (no GPU visible). Unsloth's install.sh detects
# GPUs via rocminfo//sys/class/kfd, which are absent at build time, so it
# installs CPU-only torch — we force-reinstall the ROCm wheels afterwards.
# Recovery steps follow GUIDE_UNSLOTH_STUDIO_ROCM_AMD.md (t-sinclair2500).

set -euo pipefail

export STUDIO_HOME=/opt/unsloth/studio
export VENV="$STUDIO_HOME/unsloth_studio"
export PY="$VENV/bin/python"
ROCM_INDEX="https://download.pytorch.org/whl/rocm7.2"
BNB_WHEEL="https://github.com/bitsandbytes-foundation/bitsandbytes/releases/download/continuous-release_main/bitsandbytes-1.33.7.preview-py3-none-manylinux_2_24_x86_64.whl"

echo "==> Installing uv"
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

echo "==> Running Unsloth Studio installer (non-interactive)"
mkdir -p "$STUDIO_HOME"
curl -fsSL https://unsloth.ai/install.sh -o /tmp/unsloth-install.sh
UNSLOTH_STUDIO_HOME="$STUDIO_HOME" UNSLOTH_SKIP_AUTOSTART=1 \
    sh /tmp/unsloth-install.sh --skip-autostart
rm -f /tmp/unsloth-install.sh

[ -x "$PY" ] || { echo "ERROR: Studio venv python not found at $PY" >&2; exit 1; }

echo "==> Forcing ROCm 7.2 torch into the Studio venv (+cpu trap recovery)"
# Pinned pattern from unsloth's AMD doc first; unpinned triple as fallback
# (the rocm7.2 index may only carry torch >= 2.11, outside the pins).
uv pip install --python "$PY" \
    "torch>=2.4,<2.11.0" "torchvision<0.26.0" "torchaudio<2.11.0" \
    --index-url "$ROCM_INDEX" --upgrade --force-reinstall \
|| uv pip install --python "$PY" \
    torch torchvision torchaudio \
    --index-url "$ROCM_INDEX" --upgrade --force-reinstall

echo "==> Installing bitsandbytes preview wheel (AMD 4-bit NaN fix)"
# Per unsloth AMD docs: plain pip, --no-deps, force.
"$PY" -m pip install --force-reinstall --no-cache-dir --no-deps "$BNB_WHEEL"

echo "==> Purging any nvidia-* wheels pulled in by dependency resolution"
NVIDIA_PKGS="$("$PY" -m pip list --format=freeze 2>/dev/null | grep -E '^nvidia-' | cut -d= -f1 || true)"
if [ -n "$NVIDIA_PKGS" ]; then
    echo "$NVIDIA_PKGS" | xargs "$PY" -m pip uninstall -y
else
    echo "none found"
fi

echo "==> Writing sitecustomize.py (gfx1151/ROCm workarounds)"
SITE_PACKAGES="$("$PY" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
cat > "$SITE_PACKAGES/sitecustomize.py" <<'EOF'
# gfx1151/ROCm defaults for Unsloth Studio (APPENDIX_STRIX_HALO.md).
# setdefault so users can still override from the environment.
import os

# unsloth_zoo's torch._grouped_mm probe SIGSEGVs on ROCm; use native fallback
os.environ.setdefault("UNSLOTH_MOE_BACKEND", "native_torch")
# Default compile cache is cwd-relative and litters repositories
os.environ.setdefault("UNSLOTH_COMPILE_LOCATION",
                      "/opt/unsloth/studio/unsloth_compiled_cache")
# HF transfer/xet backends misbehave on this stack
os.environ.setdefault("HF_HUB_ENABLE_HF_TRANSFER", "0")
os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
EOF

mkdir -p "$STUDIO_HOME/unsloth_compiled_cache"

echo "==> Build-time sanity checks"
"$PY" - <<'EOF'
import torch
assert torch.version.hip, f"torch is not a ROCm build: {torch.__version__}"
print(f"OK torch {torch.__version__} (HIP {torch.version.hip})")
EOF
# bitsandbytes import is best-effort without a GPU present
"$PY" -c "import bitsandbytes; print('OK bitsandbytes', bitsandbytes.__version__)" \
    || echo "WARN: bitsandbytes import failed at build time (no GPU); verify at runtime"
# The installer places the CLI in the venv and/or $STUDIO_HOME/bin
UNSLOTH_CLI="$VENV/bin/unsloth"
[ -x "$UNSLOTH_CLI" ] || UNSLOTH_CLI="$STUDIO_HOME/bin/unsloth"
"$UNSLOTH_CLI" studio --help >/dev/null && echo "OK unsloth studio CLI ($UNSLOTH_CLI)"

echo "==> Fixing permissions (toolbox runs as the host user, not root)"
chmod -R a+rwX /opt/unsloth

echo "==> Unsloth Studio install complete"
