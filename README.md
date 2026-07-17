# AMD Strix Halo — Unsloth Studio Toolboxes

Containerized [Unsloth Studio](https://unsloth.ai/docs/new/studio) for **AMD Strix Halo** (Ryzen AI Max+, gfx1151) on **ROCm 7.2** — fine-tune LLMs on the iGPU's large unified memory using the Studio web UI, from any Linux host via [Toolbx](https://containertoolbx.org/) or [Distrobox](https://distrobox.it/).

The image is Ubuntu 24.04 with a minimal ROCm 7.2 userspace, ROCm PyTorch, the AMD-fixed bitsandbytes preview wheel, and the known gfx1151 workarounds pre-applied, with Unsloth Studio baked in at `/opt/unsloth/studio`.

## Project Context & Credits

This repo follows the **Strix Halo Toolboxes** pattern created by **[kyuz0](https://github.com/kyuz0)** — see [strix-halo-toolboxes.com](https://strix-halo-toolboxes.com/) and the original [amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes), [amd-strix-halo-vllm-toolboxes](https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes), and [amd-strix-halo-llm-finetuning](https://github.com/kyuz0/amd-strix-halo-llm-finetuning) repos. Huge thanks to kyuz0 for pioneering this ecosystem.

The ROCm/gfx1151 Unsloth Studio workarounds baked into this image come from the [unsloth_studio_rocm_Halo_Strix](https://github.com/t-sinclair2500/unsloth_studio_rocm_Halo_Strix) guide (CC BY 4.0) and [Unsloth's official AMD install docs](https://unsloth.ai/docs/get-started/install/amd). Thanks to the [Unsloth](https://github.com/unslothai/unsloth) team for official AMD support.

## Toolboxes

| Toolbox | Image tag | Stack |
|---|---|---|
| `rocm-7.2` | `ghcr.io/justin-noel/amd-strix-halo-unsloth-toolboxes:rocm-7.2` | Ubuntu 24.04 · ROCm 7.2 · torch +rocm7.2 · Unsloth Studio |
| `gfx1151-nightlies` | `ghcr.io/justin-noel/amd-strix-halo-unsloth-toolboxes:gfx1151-nightlies` | Ubuntu 24.04 · TheRock gfx1151 nightly ROCm SDK + torch nightly · Unsloth Studio |

`rocm-7.2` is the stable default. `gfx1151-nightlies` tracks TheRock's gfx1151 nightly wheels (`rocm.nightlies.amd.com/v2/gfx1151/`) — the [Strix Halo guide's](https://github.com/t-sinclair2500/unsloth_studio_rocm_Halo_Strix) primary validated track, fresher kernels/fixes but a moving target. Immutable snapshots are also published as `<variant>_<timestamp>`.

## Quick Start

The easy way (auto-detects Toolbx vs Distrobox; pass a variant tag, default `rocm-7.2`):

```bash
./refresh-toolbox.sh                    # rocm-7.2
./refresh-toolbox.sh gfx1151-nightlies  # TheRock nightlies variant
```

Or manually — Fedora / Toolbx:

```bash
toolbox create unsloth-rocm-7.2 \
  --image ghcr.io/justin-noel/amd-strix-halo-unsloth-toolboxes:rocm-7.2 \
  -- --device /dev/dri --device /dev/kfd \
     --group-add video --group-add render \
     --security-opt seccomp=unconfined
toolbox enter unsloth-rocm-7.2
```

Ubuntu / Distrobox:

```bash
distrobox create -n unsloth-rocm-7.2 \
  --image ghcr.io/justin-noel/amd-strix-halo-unsloth-toolboxes:rocm-7.2 \
  --additional-flags "--device /dev/dri --device /dev/kfd --group-add video --group-add render --security-opt seccomp=unconfined"
distrobox enter unsloth-rocm-7.2
```

## Launching Unsloth Studio

Inside the toolbox:

```bash
start-unsloth-studio
```

Then open <http://localhost:8888>. The first-login password is written to `~/.unsloth/studio/auth/.bootstrap_password`.

Verify the GPU training path is active:

```bash
curl -s http://127.0.0.1:8888/api/health
# "chat_only": false  → ROCm PyTorch loaded, GPU fine-tuning available
# "chat_only": true   → CPU-only torch, something is wrong (see Troubleshooting)
```

The `unsloth` CLI is also on the PATH for headless training:

```bash
unsloth train -c config.yaml
```

> [!NOTE]
> Prefer YAML `local_dataset:` lists over the `--local-dataset` CLI flag — the flag has a known upstream parsing bug.

## Host Setup (Strix Halo)

Tested target: Ubuntu 24.04+ host with a recent kernel. To give the iGPU most of your unified memory, add kernel parameters (example caps GPU memory at ~124 GiB on a 128 GiB machine):

```
amd_iommu=off amdgpu.gttsize=126976 ttm.pages_limit=32505856
```

Add them to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, then `sudo update-grub` and reboot. No ROCm install is needed on the host — only the `amdgpu` kernel driver (in-tree) plus podman/docker and toolbox/distrobox.

## Persistence

Toolbx/Distrobox mount your host `$HOME`, so everything that matters survives container rebuilds:

- Studio auth/config and datasets: `~/.unsloth/`
- Hugging Face model cache: `~/.cache/huggingface/`

The Studio venv itself lives in the image (`/opt/unsloth/studio`), so refreshing the toolbox gives you a clean, updated stack without losing your data.

## Troubleshooting

**Hard gate — run this first.** Inside the toolbox:

```bash
/opt/unsloth/studio/unsloth_studio/bin/python -c \
  "import torch; print(torch.__version__, torch.version.hip); print(torch.tensor([1.0], device='cuda'))"
```

- Prints a `+rocm7.2` version and a tensor → stack is healthy.
- **Exit 139 (SIGSEGV)** → ROCm/kernel problem on the host; fix that before blaming Unsloth (check kernel version, firmware, and that `/dev/kfd` is passed in).
- `torch.version.hip is None` or `+cpu` version → the venv lost its ROCm torch (usually after an `unsloth` upgrade pulled CUDA wheels); recreate the toolbox with `./refresh-toolbox.sh`.

**`import unsloth` segfaults** → the image sets `UNSLOTH_MOE_BACKEND=native_torch` to avoid a `torch._grouped_mm` crash on ROCm; make sure you haven't overridden it.

**bitsandbytes errors** → the image ships the preview wheel (≥1.33.7-preview) because older releases (≤0.49.2) have a 4-bit NaN bug on AMD. If bitsandbytes can't find its ROCm library at runtime, set `BNB_ROCM_VERSION=71`.

**GPU not visible** → confirm the container was created with `--device /dev/dri --device /dev/kfd --group-add video --group-add render`, and `rocminfo` shows `gfx1151`.

**Chat runs on CPU** → Studio's chat/GGUF engine is a separate `llama.cpp` from the PyTorch training path. This image ships the ROCm gfx1151 build (check with `/opt/unsloth/studio/llama.cpp/llama-server --list-devices` — it should list `ROCm0: Radeon 8060S`). Beware `unsloth studio update`: run without a GPU visible it can reinstall the CPU build. Note the bundled TheRock HSA runtime in Unsloth's rocm-gfx1151 prebuilt segfaults on gfx1151 with recent kernels; the image symlinks the system ROCm 7.2 HSA runtime over it (see `scripts/install-llamacpp-gfx1151.sh`).

Do **not** set `HSA_OVERRIDE_GFX_VERSION` on gfx1151 — the stack targets it natively.

## Building Locally

```bash
podman build -f toolboxes/Dockerfile.rocm-7.2 -t unsloth-rocm-7.2 .
```

Expect multi-gigabyte downloads and a ~25 GiB image (the Studio venv dominates).

## References

- [Strix Halo Toolboxes](https://strix-halo-toolboxes.com/) by [kyuz0](https://github.com/kyuz0)
- [unsloth_studio_rocm_Halo_Strix guide](https://github.com/t-sinclair2500/unsloth_studio_rocm_Halo_Strix)
- [Unsloth AMD install docs](https://unsloth.ai/docs/get-started/install/amd)
- [ROCm documentation](https://rocm.docs.amd.com/)
