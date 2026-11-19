# Render offload design notes

## Desired topology

    Metal application
          |
          +-- policy selects NVIDIA device
          |        |
          |        v
          |   NullMoth NVMTL / NVK / NVRM
          |        |
          |        v
          |   RTX 4050 Laptop (render only)
          |
          +-- desktop and system UI remain on Intel
                   |
                   v
              WhateverXe / Intel display engine
                   |
                   v
              internal eDP panel

This is a device-selection/render-offload design. It does not ask the NVIDIA driver to publish an Intel framebuffer as an NVIDIA display head.

## Confirmed source behavior

### Upstream NVIDIA driver

- NVAccel has a headless detector. Unless `-nvaccelnoheadless` is supplied, it checks whether an NVIDIA display head appears.
- When no NVIDIA head appears, it restores the Metal plugin name without arming the NVIDIA display accelerator, publishes `NVAccelHeadless`, and sets `debug.nvaccel_headless=1`.
- The headless path is intended for a second Metal GPU while another GPU owns the display. WindowServer is denied the headless NVIDIA device.
- This is not the NMIntelFB framebuffer-copy mechanism. No NVIDIA display head is created for the Intel panel.

### User's NVIDIA fork

- `plugin/NVMTLDevice.m` activates per-process GPU policy when either `debug.nmhybrid > 0` or `debug.nvaccel_headless > 0`.
- In headless mode, built-in desktop/UI processes are kept on the integrated GPU.
- The fork's example policy is `package/nvmtl-gpu-policy.offload.example`. It can force named apps to NVIDIA or keep named apps on the iGPU.
- The allow-list `/Library/GPUBundles/nvmtl-allow.txt` is a separate gate: a process must be allowed before the GPU policy can grant it the NVIDIA device.
- The policy file must be a regular root-owned file and not writable by group or others.

## Critical distinction

In the pinned upstream 3.0 baseline, the GPU policy reader in `NVMTLDevice.m` is gated by `debug.nmhybrid > 0`. The user's fork changes this to also activate for `debug.nvaccel_headless > 0`. That fork change is the intended route for headless per-process policy without enabling `nmhybrid` framebuffer transfer.

Do not ship upstream-only Metal plugin binaries with the fork's policy configuration and assume the fork behavior is present. Build and package the NVIDIA fork consistently.

## Test gates

- Confirm `debug.nvaccel_headless=1` after boot, without loading NMIntelFB.
- Confirm Intel remains the owner of the internal panel and WindowServer's display GPU.
- Confirm RTX 4050 appears as a second Metal device to an allow-listed test process.
- Confirm a selected app receives the NVIDIA device while Finder, Dock, WindowServer and Control Center remain on Intel.
- Confirm the app's output is presented correctly on the Intel-owned display. Device selection alone does not prove end-to-end offload/presentation.
- Confirm sleep/wake, external display behavior, thermals and power state before treating the configuration as usable.

Do not add `-nvaccelnoheadless`. Do not enable `nmhybrid=1..4` during the initial render-offload test.
