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

## Installer rule

WhateverHybrid must stop before system installation until all of the following are verified:

1. The exact kext-signing and AMFI requirements for the selected NVIDIA fork build.
2. Whether the existing AMFIAnchor setup can coexist with the NVIDIA driver and its plugin.
3. The minimum SIP bits required by both projects, and whether one combined value is supported.
4. That the NVIDIA driver can be installed through the Auxiliary Kernel Collection without replacing WhateverXe's working installation.
5. A tested rollback path that restores the previous Auxiliary Kernel Collection and does not alter the OpenCore configuration.

No automated SIP/AMFI changes, no OpenCore writes and no automatic removal of AMFIAnchor are permitted in the installer.
