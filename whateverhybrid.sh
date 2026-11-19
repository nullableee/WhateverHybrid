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
      --check|--fetch-sources|--status) [[ -z "$ACTION" ]] || stop "Choose exactly one action."; ACTION="$1" ;;
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
  [[ "$major" == 15 || "$major" == 26 ]] || stop "Stable NVIDIA target $WH_NVIDIA_STABLE_TAG supports macOS 15/26; detected $version."
  ok "macOS $version / x86_64"
  note "Existing customized WhateverXe is preserved."
  note "NMIntelFB and nmhybrid display-transfer modes remain disabled."
}
fetch_repo() {
  local repo="$1" destination="$2" ref="$3"
  if [[ -e "$destination" ]]; then note "Keeping existing checkout: $destination"; return; fi
  mkdir -p "$(dirname "$destination")"
  note "Fetching $repo ($ref)"
  git clone --filter=blob:none --no-checkout "https://github.com/$repo.git" "$destination"
  git -C "$destination" checkout --detach "$ref"
}
fetch_sources() {
  preflight
  mkdir -p "$WORKDIR/sources"
  fetch_repo "$WH_NVIDIA_FORK" "$WORKDIR/sources/nvidia-macos-driver-fork" "main"
  fetch_repo "$WH_NVIDIA_UPSTREAM" "$WORKDIR/sources/nvidia-macos-driver-upstream" "$WH_NVIDIA_STABLE_REF"
  fetch_repo "$WH_WHATEVERXE_REPO" "$WORKDIR/sources/WhateverXe" "main"
  ok "Source checkouts prepared under $WORKDIR/sources"
  note "No driver package installed; no boot settings changed."
}
show_status() {
  printf 'NVIDIA stable target: %s (%s)\n' "$WH_NVIDIA_UPSTREAM" "$WH_NVIDIA_STABLE_TAG"
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
  --status) show_status ;;
esac
