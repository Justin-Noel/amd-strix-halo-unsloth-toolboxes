#!/usr/bin/env bash
# Interactive-shell banner: machine/GPU/torch-ROCm info.
# Adapted from kyuz0's Strix Halo toolboxes (https://github.com/kyuz0).

# Only show for interactive shells
case $- in *i*) ;; *) return 0 ;; esac

oem_info() {
  local v="" m="" d lv lm
  for d in /sys/class/dmi/id /sys/devices/virtual/dmi/id; do
    [[ -r "$d/sys_vendor" ]] && v=$(<"$d/sys_vendor")
    [[ -r "$d/product_name" ]] && m=$(<"$d/product_name")
    [[ -n "$v" || -n "$m" ]] && break
  done
  lv=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
  lm=$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]')
  if [[ -n "$m" && "$lm" == "$lv "* ]]; then
    printf '%s\n' "$m"
  else
    printf '%s %s\n' "${v:-Unknown}" "${m:-Unknown}"
  fi
}

gpu_name() {
  local name=""
  if command -v rocminfo >/dev/null 2>&1; then
    name=$(rocminfo 2>/dev/null | awk -F': ' '/^[[:space:]]*Marketing Name:/{print $2; exit}')
    [[ -z "$name" ]] && name=$(rocminfo 2>/dev/null | awk -F': ' '/^[[:space:]]*Name:/{print $2; exit}')
  fi
  if [[ -z "$name" ]] && command -v lspci >/dev/null 2>&1; then
    name=$(lspci -nn 2>/dev/null | grep -Ei 'vga|display|gpu' | grep -i amd | head -n1 | cut -d: -f3-)
  fi
  name=$(printf '%s' "$name" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//' -e 's/[[:space:]]\{2,\}/ /g')
  printf '%s\n' "${name:-Unknown AMD GPU}"
}

torch_info() {
  /opt/unsloth/studio/unsloth_studio/bin/python - <<'PY' 2>/dev/null || true
try:
    import torch
    print(f"{torch.__version__} (HIP {torch.version.hip})")
except Exception:
    print("")
PY
}

MACHINE="$(oem_info)"
GPU="$(gpu_name)"
TORCH="$(torch_info)"

echo
cat <<'ASCII'
███████╗████████╗██████╗ ██╗██╗  ██╗      ██╗  ██╗ █████╗ ██╗      ██████╗
██╔════╝╚══██╔══╝██╔══██╗██║╚██╗██╔╝      ██║  ██║██╔══██╗██║     ██╔═══██╗
███████╗   ██║   ██████╔╝██║ ╚███╔╝       ███████║███████║██║     ██║   ██║
╚════██║   ██║   ██╔══██╗██║ ██╔██╗       ██╔══██║██╔══██║██║     ██║   ██║
███████║   ██║   ██║  ██║██║██╔╝ ██╗      ██║  ██║██║  ██║███████╗╚██████╔╝
╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝      ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝ ╚═════╝

                      U N S L O T H   S T U D I O
ASCII
echo
printf 'AMD STRIX HALO — Unsloth Studio Toolbox (gfx1151, ROCm 7.2)\n'
[[ -n "$TORCH" ]] && printf 'PyTorch: %s\n' "$TORCH"
echo
printf 'Machine: %s\n' "$MACHINE"
printf 'GPU    : %s\n\n' "$GPU"
printf 'Repo   : https://github.com/Justin-Noel/amd-strix-halo-unsloth-toolboxes\n'
printf 'Image  : ghcr.io/justin-noel/amd-strix-halo-unsloth-toolboxes:rocm-7.2\n\n'
printf 'Included:\n'
printf '  - %-20s → %s\n' "start-unsloth-studio" "Launch Unsloth Studio web UI (port 8888)"
printf '  - %-20s → %s\n' "unsloth CLI"          "unsloth train -c config.yaml"
printf '  - %-20s → %s\n' "Health check"         "curl -s localhost:8888/api/health"
echo
printf 'SSH tip: ssh -L 8888:localhost:8888 user@host\n\n'

unset PROMPT_COMMAND
PS1='\u@\h:\w\$ '
