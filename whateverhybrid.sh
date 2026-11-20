#!/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/config.sh"
WORKDIR="$WH_WORKDIR_DEFAULT"
ACTION=""
usage() {
  cat <<'EOF'
WhateverHybrid — safe preparation utility
Usage:
  ./whateverhybrid.sh --check
  ./whateverhybrid.sh --fetch-sources [--workdir PATH]
  ./whateverhybrid.sh --test-driver [--workdir PATH]
  ./whateverhybrid.sh --status [--workdir PATH]
  ./whateverhybrid.sh --help
This stage does not install kexts, change OpenCore/NVRAM, alter SIP/AMFI,
or enable experimental hybrid display paths.
EOF
}
stop() { printf 'STOP: %s\n' "$*" >&2; exit 1; }
note() { printf '[*] %s\n' "$*"; }
ok() { printf '[ok] %s\n' "$*"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || stop "Required command not found: $1"; }
parse_args() {
  while (($#)); do
    case "$1" in
      --check|--fetch-sources|--test-driver|--status) [[ -z "$ACTION" ]] || stop "Choose exactly one action."; ACTION="$1" ;;
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
    if [[ "$current" == "$ref" ]]; then note "Pinned checkout already present: $destination"; return; fi
    [[ -z "$(git -C "$destination" status --porcelain)" ]] || stop "Existing checkout has local changes; refusing to overwrite: $destination"
    note "Updating clean checkout to pinned revision $ref"
    git -C "$destination" fetch --no-tags origin "$ref"
    local target
    target="$(git -C "$destination" rev-parse FETCH_HEAD)" || stop "Cannot resolve fetched revision: $ref"
    git -C "$destination" checkout --detach "$target"
    return
  fi
  mkdir -p "$(dirname "$destination")"
  note "Fetching $repo ($ref)"
  git clone --filter=blob:none --no-checkout "https://github.com/$repo.git" "$destination"
  git -C "$destination" fetch --no-tags origin "$ref"
  local target
  target="$(git -C "$destination" rev-parse FETCH_HEAD)" || stop "Cannot resolve fetched revision: $ref"
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
show_status() {
  printf 'NVIDIA upstream baseline: %s (%s)\n' "$WH_NVIDIA_UPSTREAM" "$WH_NVIDIA_UPSTREAM_REF"
  printf 'NVIDIA development fork: %s\n' "$WH_NVIDIA_FORK"
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
  --status) show_status ;;
esac
