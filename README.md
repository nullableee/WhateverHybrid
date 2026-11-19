# WhateverHybrid

A shell-based installer and integration project for muxless Intel + NVIDIA laptops running macOS through OpenCore.

## Initial target

- Gigabyte G6 MF
- Intel Core i5-13500H (Raptor Lake-H)
- NVIDIA GeForce RTX 4050 Laptop GPU
- macOS Tahoe 26.7.x
- WhateverXe already provides Intel iGPU acceleration and Metal 3.
- The internal panel is connected to the Intel display engine (reported as eDP-1).

The existing customized WhateverXe installation must be preserved. WhateverHybrid must not replace it with upstream binaries.

## Intended architecture: render offload

- Intel / WhateverXe remains the display-owning GPU and drives the internal eDP panel and desktop.
- NVIDIA / NullMoth provides a second Metal device for selected applications.
- macOS system UI processes remain on the integrated GPU.
- The NVIDIA fork adds per-process policy activation in headless mode, so this policy can work without enabling the experimental framebuffer-transfer modes.

This is distinct from nmhybrid=1..4 panel-transfer. WhateverHybrid does not enable those modes by default.

## Explicit exclusions

- NMIntelFB is not part of the default setup. It is an experimental upstream panel provider, not a prerequisite for ordinary headless render offload.
- No nmhybrid boot argument is added automatically.
- No automatic edits to OpenCore, NVRAM, SIP, AMFI, or kernel patches.
- No replacement of the customized WhateverXe / WhateverXe Graphics installation.
- No claim of working render offload until real hardware confirms Metal device enumeration, per-process selection, frame presentation and stability.

## Source pins

- Upstream baseline: current 3.0 source snapshot at `87e524ab36f12d17c04626d6cf7fc3bde1cc63e`.
- NVIDIA development fork: `b76d3df1da4bf2497c938c7d78ac221e307319b0`, which includes the headless+iGPU GPU-policy activation and desktop-process preference changes.
- WhateverXe: preserve the already-installed customized build; source checkout is for inspection only.

The upstream 3.0 source installer explicitly accepts macOS 15 and 26. This repository pins source revisions rather than assuming an unverified release-tag name. The final install package and its checksum/signature still need to be verified before a system install is added.

## Current repository state

This is the safe bootstrap stage:

- `--check`: verifies host OS, architecture and required tools.
- `--fetch-sources`: checks out the user's NVIDIA fork, the upstream baseline and WhateverXe source for inspection.
- `--status`: prints the configured integration policy.

This stage does not install kexts or change system configuration.

## Next implementation gates

1. Build the NVIDIA fork from the pinned source revision and run its host test suite.
2. Verify the headless detector sets `debug.nvaccel_headless` when the NVIDIA GPU has no display head and the Intel framebuffer owns the desktop.
3. Verify the fork's policy code activates when `debug.nvaccel_headless > 0`, with no `nmhybrid` boot argument.
4. Verify allow-list and per-process policy behavior: system UI stays on Intel; explicitly selected applications receive the RTX 4050 Metal device.
5. Confirm package layout, signatures and checksums for macOS 26.
6. Add a read-only hardware/provider audit, then a staged installer with backup, explicit confirmation, rollback and post-install verification.

## Usage

```sh
chmod +x whateverhybrid.sh
./whateverhybrid.sh --check
./whateverhybrid.sh --fetch-sources
./whateverhybrid.sh --status
```

The utility is intentionally non-destructive at this stage.
