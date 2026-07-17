# Unsloth Studio toolbox environment (gfx1151 / ROCm 7.2)
# Mirrors the sitecustomize.py defaults for shell-launched tools
# (`unsloth train`, ad-hoc python). Values can be overridden per-session.

export UNSLOTH_STUDIO_HOME=/opt/unsloth/studio
export UNSLOTH_MOE_BACKEND="${UNSLOTH_MOE_BACKEND:-native_torch}"
export UNSLOTH_COMPILE_LOCATION="${UNSLOTH_COMPILE_LOCATION:-/opt/unsloth/studio/unsloth_compiled_cache}"
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-0}"
export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
export TOKENIZERS_PARALLELISM="${TOKENIZERS_PARALLELISM:-false}"

# ROCm tools (rocminfo, rocm-smi) — bitsandbytes needs rocminfo on PATH
case ":$PATH:" in
    *":/opt/rocm/bin:"*) ;;
    *) export PATH="/opt/rocm/bin:$PATH" ;;
esac

# Studio venv tools (unsloth CLI, its python) at the end of PATH so the
# system python3 stays the default interpreter.
case ":$PATH:" in
    *":/opt/unsloth/studio/unsloth_studio/bin:"*) ;;
    *) export PATH="$PATH:/opt/unsloth/studio/unsloth_studio/bin" ;;
esac
