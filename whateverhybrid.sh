#!/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/config.sh"
WORKDIR="$WH_WORKDIR_DEFAULT"
ACTION=""
usage() {
  cat <<'EOF'
WhateverHybrid — safe preparation and integration utility
Usage:
  ./whateverhybrid.sh --check
  ./whateverhybrid.sh --fetch-sources [--workdir PATH]
  ./whateverhybrid.sh --test-driver [--workdir PATH]
  ./whateverhybrid.sh --audit [--workdir PATH]
  ./whateverhybrid.sh --build-plugin [--workdir PATH]
  ./whateverhybrid.sh --stage-payload [--workdir PATH]
  sudo ./whateverhybrid.sh --install [--workdir PATH]
  sudo ./whateverhybrid.sh --uninstall
  ./whateverhybrid.sh --status [--workdir PATH]
  ./whateverhybrid.sh --help

Actions:
  --check          Verify host OS, architecture, and essential commands.
  --fetch-sources  Check out pinned driver fork, baseline and test dependencies.
  --test-driver    Run the fork's 250+ host unit and regression tests.
  --audit          Read-only audit of iGPU, dGPU, EFI config, kexts, and SIP/AMFI.
  --build-plugin   Compile custom NVMTLDriver from fork with headless fused DMA.
  --stage-payload  Fetch base package, inject fork plugin & policy, stage firmware.
  --install        Install staged driver into AuxKC (requires root: sudo).
  --uninstall      Cleanly remove NVIDIA driver and restore previous state (sudo).
  --status         Print configured source pins and working paths.

This utility preserves WhateverXe and never enables NMIntelFB or nmhybrid blitting.
EOF
}
stop() { printf 'STOP: %s\n' "$*" >&2; exit 1; }
note() { printf '[*] %s\n' "$*"; }
ok() { printf '[ok] %s\n' "$*"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || stop "Required command not found: $1"; }
parse_args() {
  while (($#)); do
    case "$1" in
      --check|--fetch-sources|--test-driver|--audit|--build-plugin|--stage-payload|--install|--uninstall|--status)
        [[ -z "$ACTION" ]] || stop "Choose exactly one action."; ACTION="$1" ;;
      --workdir) (($# >= 2)) || stop "--workdir requires a path."; WORKDIR="$2"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) stop "Unknown argument: $1" ;;
    esac
    shift
  done
  [[ -n "$ACTION" ]] || { usage; exit 2; }
}
preflight() {
  [[ "$(uname -s)" == Darwin ]] || stop "This utility must run on macOS."
  [[ "$(uname -m)" == x86_64 ]] || stop "The NVIDIA package target is Intel x86_64."
  for c in sw_vers git curl shasum ditto; do need_cmd "$c"; done
  local version major
  version="$(sw_vers -productVersion)"; major="${version%%.*}"
  [[ "$major" == 15 || "$major" == 26 ]] || stop "Pinned NVIDIA source targets macOS 15/26; detected $version."
  ok "macOS $version / x86_64"
  note "Existing customized WhateverXe is preserved."
  note "NMIntelFB and nmhybrid display-transfer modes remain disabled."
}
fetch_repo() {
  local repo="$1" destination="$2" ref="$3"
  if [[ -e "$destination" ]]; then
    [[ -d "$destination/.git" ]] || stop "Existing source path is not a Git checkout: $destination"
    local current
    current="$(git -C "$destination" rev-parse HEAD 2>/dev/null)" || stop "Cannot inspect existing checkout: $destination"
    if [[ "$current" == "$ref" ]]; then
      local first_entry
      first_entry="$(git -C "$destination" ls-tree --name-only HEAD | sed -n '1p')"
      if [[ -n "$first_entry" && ! -e "$destination/$first_entry" ]]; then
        note "Materializing pinned checkout: $destination"
        git -C "$destination" checkout --detach "$current"
      else
        note "Pinned checkout already present: $destination"
      fi
      return
    fi
    [[ -z "$(git -C "$destination" status --porcelain)" ]] || stop "Existing checkout has local changes; refusing to overwrite: $destination"
    note "Updating clean checkout to pinned revision $ref"
    local target
    target="$(git -C "$destination" rev-parse --verify "${ref}^{commit}" 2>/dev/null || true)"
    if [[ -z "$target" ]]; then
      git -C "$destination" fetch --no-tags origin "$ref"
      target="$(git -C "$destination" rev-parse FETCH_HEAD)" || stop "Cannot resolve fetched revision: $ref"
    fi
    git -C "$destination" checkout --detach "$target"
    return
  fi
  mkdir -p "$(dirname "$destination")"
  note "Fetching $repo ($ref)"
  git clone --filter=blob:none "https://github.com/$repo.git" "$destination"
  local target
  target="$(git -C "$destination" rev-parse --verify "${ref}^{commit}" 2>/dev/null || true)"
  if [[ -z "$target" ]]; then
    git -C "$destination" fetch --no-tags origin "$ref"
    target="$(git -C "$destination" rev-parse FETCH_HEAD)" || stop "Cannot resolve fetched revision: $ref"
  fi
  git -C "$destination" checkout --detach "$target"
}
fetch_test_baselines() {
  local checkout="$1" tag
  for tag in v1.15.0 v2.8.1; do
    if ! git -C "$checkout" show-ref --verify --quiet "refs/tags/$tag"; then
      note "Fetching upstream test baseline tag $tag"
      git -C "$checkout" fetch --no-tags "https://github.com/$WH_NVIDIA_UPSTREAM.git" "refs/tags/$tag:refs/tags/$tag"
    fi
  done
}
fetch_sources() {
  preflight
  mkdir -p "$WORKDIR/sources"
  fetch_repo "$WH_NVIDIA_FORK" "$WORKDIR/sources/nvidia-macos-driver-fork" "$WH_NVIDIA_FORK_REF"
  fetch_test_baselines "$WORKDIR/sources/nvidia-macos-driver-fork"
  fetch_repo "$WH_NVIDIA_UPSTREAM" "$WORKDIR/sources/nvidia-macos-driver-upstream" "$WH_NVIDIA_UPSTREAM_REF"
  fetch_repo "$WH_VULKAN_HEADERS_REPO" "$WORKDIR/sources/Vulkan-Headers" "$WH_VULKAN_HEADERS_REF"
  fetch_repo "$WH_WHATEVERXE_REPO" "$WORKDIR/sources/WhateverXe" "main"
  ok "Source checkouts prepared under $WORKDIR/sources"
  note "No driver package installed; no boot settings changed."
}
test_driver() {
  preflight
  local src="$WORKDIR/sources/nvidia-macos-driver-fork"
  local vulkan="$WORKDIR/sources/Vulkan-Headers"
  [[ -f "$src/tools/run_all_tests.py" ]] || stop "Run --fetch-sources first."
  [[ -f "$vulkan/include/vulkan/vulkan.h" ]] || stop "Pinned Vulkan-Headers are missing; run --fetch-sources first."
  export VULKAN_HEADERS="$vulkan"
  if [[ -z "${ZSTD:-}" ]]; then
    local zstd_bin=""
    zstd_bin="$(command -v zstd || true)"
    [[ -n "$zstd_bin" ]] || { [[ -x /usr/local/bin/zstd ]] && zstd_bin=/usr/local/bin/zstd; }
    [[ -n "$zstd_bin" ]] || { [[ -x /opt/homebrew/bin/zstd ]] && zstd_bin=/opt/homebrew/bin/zstd; }
    [[ -z "$zstd_bin" ]] || export ZSTD="$zstd_bin"
  fi
  need_cmd python3
  need_cmd xcode-select
  need_cmd clang
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' || stop "Driver host tests require Python 3.12 or newer."
  xcode-select -p >/dev/null 2>&1 || stop "Xcode Command Line Tools are not selected."
  note "Running the fork's host test suite; no kexts are installed."
  (cd "$src" && python3 tools/run_all_tests.py)
}
audit_system() {
  preflight
  need_cmd python3
  python3 - <<'EOF'
import os, sys, subprocess, plistlib

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()

print("\n========================================================")
print("       WhateverHybrid System & Hardware Audit           ")
print("========================================================")

sw = sh("sw_vers -productVersion")
build = sh("sw_vers -buildVersion")
krn = sh("uname -r")
print(f"[*] OS: macOS {sw} (Build {build}), Kernel {krn}")

print("\n--- Integrated GPU (Intel Iris Xe) ---")
igpu_loaded = sh("kmutil showloaded --list-only | grep -E 'AppleIntelTGLGraphicsFramebuffer|AppleIntelTGLGraphics'")
if "AppleIntelTGLGraphicsFramebuffer" in igpu_loaded:
    print("[ok] Framebuffer driver: AppleIntelTGLGraphicsFramebuffer (ACTIVE)")
else:
    print("[!] Framebuffer driver: Not detected")
if "AppleIntelTGLGraphics" in igpu_loaded:
    print("[ok] Metal acceleration: AppleIntelTGLGraphics (ACTIVE, Metal 3)")
else:
    print("[!] Metal acceleration: Not detected")

print("\n--- Discrete GPU (NVIDIA RTX 4050) ---")
ioreg_pep = sh("ioreg -r -n PEGP -l")
if "28a1" in ioreg_pep:
    print("[ok] Hardware detected: NVIDIA GeForce RTX 4050 Laptop (0x28a1) at PEGP@0")
    if '"disable-gpu" = <01>' in ioreg_pep:
        print("[!] BLOCKER: IORegistry reports 'disable-gpu' = <01> on RTX 4050")
        print("    --> NVRM.kext cannot match or initialize this device until disable-gpu is removed.")
    else:
        print("[ok] RTX 4050 is active (no disable-gpu flag in IORegistry)")
else:
    print("[!] Discrete GPU 0x28a1 not found in IORegistry")

print("\n--- OpenCore Configuration ---")
oc_path = "/Volumes/EFI/EFI/OC/config.plist"
if os.path.exists(oc_path):
    print(f"[ok] Config path: {oc_path}")
    try:
        with open(oc_path, "rb") as f:
            pl = plistlib.load(f)
        dp = pl.get("DeviceProperties", {}).get("Add", {})
        peg_dp = dp.get("PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)", {})
        if peg_dp.get("disable-gpu") in (b"\x01", 1, True):
            print("[!] BLOCKER: DeviceProperties PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0) contains disable-gpu = 1")
            print("    Action required: Toggle disable-gpu to 0 or remove when enabling NVIDIA offload.")
        else:
            print("[ok] DeviceProperties PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0) has no disable-gpu flag")
        
        nv = pl.get("NVRAM", {}).get("Add", {}).get("7C436110-AB2A-4BBB-A880-FE41995C9F82", {})
        ba = nv.get("boot-args", "")
        print(f"[*] OpenCore boot-args: {ba}")
        if "nvaccel=1" in ba:
            print("    [ok] nvaccel=1 is present (accelerator safety arm enabled)")
        else:
            print("    [*] Tip: Add 'nvaccel=1' to boot-args to arm the accelerator in headless mode.")
        csr = nv.get("csr-active-config")
        if isinstance(csr, bytes):
            csr_val = int.from_bytes(csr, "little")
            print(f"[*] OpenCore csr-active-config: 0x{csr_val:04X} ({csr.hex()})")
            if (csr_val & 0x0803) == 0x0803:
                print("    [ok] Preserves all required WhateverXe SIP bits (0x0803)")
            if (csr_val & 0x0A43) == 0x0A43:
                print("    [ok] Satisfies NVIDIA KextPolicy database write bits (0x0A43)")
    except Exception as e:
        print(f"[!] Error reading config.plist: {e}")
else:
    print("[*] Note: EFI partition not mounted at /Volumes/EFI")

print("\n--- Active Helper Kexts ---")
for kext in ["as.vit9696.Lilu", "org.b00t0x.WhateverXe", "org.b00t0x.AMFIAnchor", "com.dhinakg.AMFIPass"]:
    loaded = sh(f"kmutil showloaded --list-only --bundle-identifier {kext}")
    if kext in loaded:
        print(f"[ok] {kext}: LOADED")
    else:
        print(f"[!] {kext}: NOT LOADED")

print("\n--- GPUBundles Status (/Library/GPUBundles) ---")
if os.path.exists("/Library/GPUBundles/AppleIntelTGLGraphicsMTLDriver.bundle"):
    print("[ok] WhateverXe Intel Metal bundle: PRESENT & UNTOUCHED")
else:
    print("[!] WhateverXe Intel Metal bundle: MISSING")
if os.path.exists("/Library/GPUBundles/NVMTLDriver.bundle"):
    print("[*] NVIDIA Metal bundle: ALREADY INSTALLED")
else:
    print("[*] NVIDIA Metal bundle: NOT INSTALLED (clean state)")
print("========================================================\n")
EOF
}
build_plugin() {
  preflight
  local src="$WORKDIR/sources/nvidia-macos-driver-fork"
  local vulkan="$WORKDIR/sources/Vulkan-Headers"
  [[ -d "$src/plugin" ]] || stop "Sources missing; run --fetch-sources first."
  [[ -f "$vulkan/include/vulkan/vulkan.h" ]] || stop "Pinned Vulkan-Headers missing; run --fetch-sources first."
  need_cmd clang
  need_cmd codesign

  local out="$WORKDIR/build/plugin"
  mkdir -p "$out"
  note "Compiling NVMTLDriver from fork source ($WH_NVIDIA_FORK_REF)"
  xcrun clang -arch x86_64 -mmacosx-version-min=15.0 -bundle -fobjc-arc -O1 -DNVMTL_RELEASE=1 \
    -Wno-protocol -Wno-incomplete-implementation \
    -I"$vulkan/include" -I"$src/plugin" \
    -o "$out/NVMTLDriver" "$src/plugin/NVMTLDevice.m" "$src/plugin/nvmtl_dlss.c" "$src/dlss/elfhost.c" "$src/dlss/lnxlibc.c" \
    -framework Foundation -framework Metal -framework IOSurface -framework IOKit -framework CoreFoundation -framework MetalFX -liconv 2>"$out/build.err" \
    || { stop "Compilation failed: $(head -20 "$out/build.err")"; }

  codesign -f -s - "$out/NVMTLDriver" 2>/dev/null || true
  
  local miss=0
  local patterns=("nvmtl-gpu-policy.txt" "served by DLSS" "NVIDIAShared" "NVMTL_NO_DIRTYONLY")
  for pat in "${patterns[@]}"; do
    if ! strings -a "$out/NVMTLDriver" | grep -- "$pat" >/dev/null; then
      note "WARNING: Marker string '$pat' missing in built driver"
      miss=$((miss+1))
    fi
  done
  [[ "$miss" -eq 0 ]] || stop "Built driver is missing required feature markers."
  local sha
  sha="$(shasum -a 256 "$out/NVMTLDriver" | awk '{print $1}')"
  ok "NVMTLDriver successfully built and verified (SHA256: ${sha:0:16}...)"
}
stage_payload() {
  preflight
  build_plugin
  local cachedir="$WORKDIR/cache"
  local tarpath="$cachedir/$WH_NVIDIA_PAYLOAD_TAR"
  mkdir -p "$cachedir"

  if [[ ! -f "$tarpath" ]]; then
    note "Downloading upstream payload: $WH_NVIDIA_PAYLOAD_TAR ($WH_NVIDIA_RELEASE_TAG)"
    curl -fL -o "$tarpath" "https://github.com/$WH_NVIDIA_UPSTREAM/releases/download/$WH_NVIDIA_RELEASE_TAG/$WH_NVIDIA_PAYLOAD_TAR"
  fi

  note "Verifying payload checksum"
  local actual_sha
  actual_sha="$(shasum -a 256 "$tarpath" | awk '{print $1}')"
  [[ "$actual_sha" == "$WH_NVIDIA_PAYLOAD_SHA256" ]] || stop "Payload SHA256 mismatch: got $actual_sha, expected $WH_NVIDIA_PAYLOAD_SHA256"
  ok "Payload checksum verified"

  local stagedir="$WORKDIR/staged-payload"
  rm -rf "$stagedir"
  mkdir -p "$stagedir"
  note "Extracting upstream base package into $stagedir"
  tar -xzf "$tarpath" -C "$stagedir"

  note "Injecting fork-built NVMTLDriver into staged NVMTLDriver.bundle"
  local bundle="$stagedir/pkgroot/Library/GPUBundles/NVMTLDriver.bundle"
  [[ -d "$bundle" ]] || stop "Staged NVMTLDriver.bundle not found in payload."
  ditto "$WORKDIR/build/plugin/NVMTLDriver" "$bundle/Contents/MacOS/NVMTLDriver"
  codesign -f -s - "$bundle" 2>/dev/null || true

  note "Injecting headless render-offload policy and allowlist"
  cp "$ROOT/patches/nvmtl-gpu-policy.example" "$stagedir/pkgroot/Library/GPUBundles/nvmtl-gpu-policy.txt"
  cp "$ROOT/patches/nvmtl-allow.example" "$stagedir/pkgroot/Library/GPUBundles/nvmtl-allow.txt"
  chmod 644 "$stagedir/pkgroot/Library/GPUBundles/nvmtl-gpu-policy.txt" "$stagedir/pkgroot/Library/GPUBundles/nvmtl-allow.txt"

  # Stage firmware if available
  if [[ -d /tmp/nvfw_test && ! -d "$stagedir/pkgroot/Users/Shared/nvfw" ]]; then
    note "Staging verified offline firmware"
    mkdir -p "$stagedir/pkgroot/Users/Shared"
    ditto /tmp/nvfw_test "$stagedir/pkgroot/Users/Shared/nvfw"
  fi

  # Ensure NMIntelFB is not in the staged package
  rm -rf "$stagedir/pkgroot/Library/Extensions/NMIntelFB.kext" "$stagedir/pkgroot/Library/NullMoth/kexts/"*/NMIntelFB.kext 2>/dev/null || true

  note "Refreshing SHA256SUMS for modified package files"
  (
    cd "$stagedir/pkgroot"
    local files=(
      Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
      Library/GPUBundles/NVMTLDriver.bundle/Contents/_CodeSignature/CodeResources
      Library/GPUBundles/nvmtl-gpu-policy.txt
      Library/GPUBundles/nvmtl-allow.txt
    )
    if [[ -d Users/Shared/nvfw/nvidia/620.70.06 ]]; then
      files+=(
        Users/Shared/nvfw/nvidia/620.70.06/gsp_ga10x.bin
        Users/Shared/nvfw/nvidia/620.70.06/gsp_tu10x.bin
        Users/Shared/nvfw/nvidia/620.70.06/ucodes_ga10x.bin
        Users/Shared/nvfw/nvidia/620.70.06/ucodes_tu10x.bin
      )
    fi
    "$WORKDIR/sources/nvidia-macos-driver-fork/package/sums_refresh.sh" . "${files[@]}"
    shasum -c SHA256SUMS >/dev/null
    ./sums_complete.sh . >/dev/null
  )
  ok "Package integrity and checksums verified"
  ok "Payload staged under $stagedir"
  note "Ready for system installation via: sudo ./whateverhybrid.sh --install"
}
install_driver() {
  preflight
  local stagedir="$WORKDIR/staged-payload/pkgroot"
  [[ -f "$stagedir/install.sh" ]] || stop "Staged payload not found. Run ./whateverhybrid.sh --stage-payload first."
  [[ "$EUID" -eq 0 ]] || stop "System installation requires root privileges. Please run:\nsudo ./whateverhybrid.sh --install"

  note "Starting staged installation into AuxiliaryKernelExtensions.kc..."
  "$stagedir/install.sh" --payload "$stagedir"
  ok "Installation finished successfully! Restart your Mac to load the driver."
}
uninstall_driver() {
  local stagedir="$WORKDIR/staged-payload/pkgroot"
  if [[ -f "$stagedir/uninstall.sh" ]]; then
    [[ "$EUID" -eq 0 ]] || stop "Driver uninstallation requires root privileges. Please run:\nsudo ./whateverhybrid.sh --uninstall"
    "$stagedir/uninstall.sh"
  elif [[ -f "/Library/NullMoth/uninstall.sh" ]]; then
    [[ "$EUID" -eq 0 ]] || stop "Driver uninstallation requires root privileges. Please run:\nsudo /Library/NullMoth/uninstall.sh"
    "/Library/NullMoth/uninstall.sh"
  else
    stop "No uninstaller found."
  fi
}
show_status() {
  printf 'NVIDIA upstream baseline: %s (%s)\n' "$WH_NVIDIA_UPSTREAM" "$WH_NVIDIA_UPSTREAM_REF"
  printf 'NVIDIA development fork: %s (%s)\n' "$WH_NVIDIA_FORK" "$WH_NVIDIA_FORK_REF"
  printf 'WhateverXe: preserve installed customized build\n'
  printf 'NMIntelFB: disabled\nnmhybrid display transfer: disabled\n'
  printf 'Work directory: %s\n' "$WORKDIR"
  [[ ! -d "$WORKDIR/sources" ]] || find "$WORKDIR/sources" -maxdepth 1 -mindepth 1 -type d -print
}
parse_args "$@"
case "$ACTION" in
  --check) preflight ;;
  --fetch-sources) fetch_sources ;;
  --test-driver) test_driver ;;
  --audit) audit_system ;;
  --build-plugin) build_plugin ;;
  --stage-payload) stage_payload ;;
  --install) install_driver ;;
  --uninstall) uninstall_driver ;;
  --status) show_status ;;
esac