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
- Per-process selection uses the driver's GPU policy mechanism, subject to activation and real-hardware validation.

This is distinct from the experimental nmhybrid=1..4 panel-transfer path. WhateverHybrid does not enable that path by default.

## Explicit exclusions

- NMIntelFB is not part of the default setup. It is an experimental upstream panel provider, not a prerequisite for ordinary headless render offload.
- No nmhybrid boot argument is added automatically.
- No automatic edits to OpenCore, NVRAM, SIP, AMFI, or kernel patches.
- No replacement of the customized WhateverXe / WhateverXe Graphics installation.
- No claim of working render offload until real hardware confirms Metal device enumeration, per-process selection, frame presentation and stability.

## Version policy

The 2.9 release line is the final NullMoth release line documented for macOS 15 Sequoia and macOS 26 Tahoe. The repository pins the source checkout to the release changelog commit `3d8ffab7fd737bc175089b0bc21900abf9f38bec`, rather than assuming a tag name. The 3.0 line is not selected for this Tahoe target.

The user's NVIDIA fork is tracked separately for development; it is not silently substituted for the stable source. WhateverXe and its Graphics companion are treated as already installed, customized dependencies. Their versions and compatibility are checked before any future installation step; they are not updated automatically.

## Current repository state

This is the safe bootstrap stage:

- `--check`: verifies host OS, architecture and required tools.
- `--fetch-sources`: checks out the user's NVIDIA fork, pinned upstream 2.9 source and WhateverXe source for inspection.
- `--status`: prints the configured integration policy.

This stage does not install kexts or change system configuration.

## Next implementation gates

1. Confirm the exact kernel-side activation mechanism for `debug.nvaccel_headless` in the selected driver source.
2. Verify that the driver's GPU policy is active in headless+iGPU mode without NMIntelFB.
3. Confirm package layout, signatures and release checksums for the 2.9 Tahoe package.
4. Add a read-only hardware/provider audit for the Intel eDP owner and NVIDIA PCI device.
5. Implement a staged installer with backup, explicit confirmation, rollback and post-install verification.
6. Continue performance and compatibility work in the NVIDIA fork only after the basic offload path is validated.

## Usage

```sh
chmod +x whateverhybrid.sh
./whateverhybrid.sh --check
./whateverhybrid.sh --fetch-sources
./whateverhybrid.sh --status
```

The utility is intentionally non-destructive at this stage.
