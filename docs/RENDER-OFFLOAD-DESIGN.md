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

## Findings from current source

- plugin/nvmtl_gpu_policy.h contains a per-process decision policy.
- plugin/NVMTLDevice.m reads debug.nmhybrid and debug.nvaccel_headless; policy is active when either value is positive.
- In headless mode, WindowServer is explicitly denied the NVIDIA device so it composites on the GPU that owns the display.
- With no policy file in headless mode, the policy defaults to Apple's automatic graphics switching behavior, keeping desktop/UI processes on the iGPU.
- The example policy is package/nvmtl-gpu-policy.offload.example.

## Open activation question

The source inspected so far confirms the sysctl consumed by the Metal plugin, but does not yet establish which supported boot argument or kernel-side setting publishes debug.nvaccel_headless in the selected stable build. Do not guess the spelling or add a boot argument until the matching kernel source is traced and tested.

## Test gates

- Confirm debug.nvaccel_headless > 0 after boot, without loading NMIntelFB.
- Confirm Intel remains the owner of the internal panel and WindowServer's Metal device.
- Confirm RTX 4050 appears as a second Metal device to an allow-listed test process.
- Confirm a selected app receives the NVIDIA device while Finder, Dock, WindowServer and Control Center remain on Intel.
- Confirm the app's output is presented correctly on the Intel-owned display. Device selection alone does not prove end-to-end offload/presentation.
- Confirm sleep/wake, external display behavior, thermals and power state before treating the configuration as usable.

No nmhybrid=1..4 mode is part of this test plan.
