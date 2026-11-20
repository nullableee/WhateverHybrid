# Compatibility blockers before installation

## Existing Intel graphics setup

The target system already boots with a customized WhateverXe installation. Treat that as a known-good dependency and preserve its EFI entries, kext versions, AMFIAnchor configuration and boot arguments.

WhateverXe's installation guide specifies:

- Keep AMFI enabled.
- Use AMFIAnchor and its injector.
- Its documented SIP value is `csr-active-config=03080000` (0x803).

Reference: [WhateverXe README](https://github.com/nullableee/WhateverXe/blob/main/README.md).

## NVIDIA driver requirements

The current NVIDIA fork's installation guide documents a different OpenCore setup, including:

- `csr-active-config` bits `0x0A43`.
- AMFI-related boot arguments used by the NVIDIA package.
- Lilu and AMFIPass in OpenCore.

Reference: [NVIDIA fork README](https://github.com/nullableee/nvidia-macos-driver/blob/main/README.md).

These are not interchangeable configuration recipes. Do not copy the NVIDIA boot arguments or replace the current SIP/AMFI configuration without a verified combined configuration for this exact machine and macOS build.

## Hardware Blocker Identified in Live Audit

During the live audit on the target Gigabyte G6 MF laptop:

- **RTX 4050 is disabled via OpenCore DeviceProperties**:
  - `PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)` has `disable-gpu: <01>`.
  - As a result, macOS does not match or attach graphics drivers to the dGPU, leaving it on unaccelerated `IONDRVFramebuffer`.
  - **Resolution**: When proceeding to hardware render-offload testing, `disable-gpu` must be toggled off (`<00>` or deleted) in OpenCore's `config.plist` so `NVRM.kext` can bind to the Ada Lovelace (AD107M) device.

## Verified Coexistence Analysis

1. **AMFI & Helper Kexts**:
   - `AMFIAnchor.kext` (v0.1.2) and `com.dhinakg.AMFIPass` (v1.4.1) are both active and loaded simultaneously on macOS 26.7.2.
   - Under render-offload, `WindowServer` remains on Intel Iris Xe and does not load `NVMTLDriver.bundle` (the fork explicitly denies WindowServer the headless device).
   - Therefore, the upstream issue where WindowServer refuses third-party Metal bundles under AMFI does not apply to this setup, eliminating the need for `amfi_get_out_of_my_way=0x1 amfi=0x80`.

2. **SIP Configuration**:
   - Current value: `csr-active-config = 03080000` (`0x0803`).
   - The NVIDIA package default (`0x0A43`) is a clean superset:
     - `0x0803` = `0x001` (untrusted kexts) + `0x002` (unrestricted fs) + `0x800` (apple internal).
     - `0x0A43` = `0x0803` + `0x040` (unrestricted nvram) + `0x200` (executable policy override).
   - `0x0A43` preserves every bit needed by WhateverXe while permitting silent KextPolicy approval.

## Installer rule

WhateverHybrid must stop before system installation until all of the following are verified:

1. The exact kext-signing and AMFI requirements for the selected NVIDIA fork build.
2. Whether the existing AMFIAnchor setup can coexist with the NVIDIA driver and its plugin.
3. The minimum SIP bits required by both projects, and whether one combined value is supported.
4. That the NVIDIA driver can be installed through the Auxiliary Kernel Collection without replacing WhateverXe's working installation.
5. A tested rollback path that restores the previous Auxiliary Kernel Collection and does not alter the OpenCore configuration.

No automated SIP/AMFI changes, no OpenCore writes and no automatic removal of AMFIAnchor are permitted in the installer.
