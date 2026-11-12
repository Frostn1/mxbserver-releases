#!/usr/bin/env bash
# box-update.sh: put a newer signed mxbserver on a native hosted box, without restarting it.
#
# Public script, no secrets. Run as the box's sudo user, as box-install.sh is.
#
#   box-update.sh --pubkey-file minisign.pub [--release-repo Frostn1/mxbserver-releases]
#       [--tag server-vX.Y.Z] [--dry-run]
#
# Fetches the release (default: the newest published, non-prerelease server-v*), checks the
# minisign signature over SHA256SUMS and the file hashes, and swaps /usr/local/bin/mxbserver
# with an atomic rename. Running mxbserver@sN units keep the binary they started with; the
# control plane restarts each slot once it has no riders, so nobody is cut off mid-race.
# Bike-set manifests from the release are refreshed the same way.
#
# Prints `installed <tag>` or `current <tag>` (already on it) as its last line.
set -euo pipefail

REPO=Frostn1/mxbserver-releases
PUBKEY=""
TAG=""
DRY=0

die() { echo "box-update: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-repo) REPO="${2:-}"; shift 2 ;;
    --pubkey-file) PUBKEY="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n 2,16p "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--release-repo must be owner/name"
[[ -n "$PUBKEY" ]] || die "--pubkey-file is required"
[[ "$DRY" == 1 || -f "$PUBKEY" ]] || die "--pubkey-file $PUBKEY not found"
[[ -z "$TAG" || "$TAG" =~ ^server-v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "--tag must be server-vX.Y.Z"

run() { if [[ "$DRY" == 1 ]]; then echo "+ $*"; else "$@"; fi; }
sudo_run() { run sudo "$@"; }

if [[ -z "$TAG" ]]; then
  if [[ "$DRY" == 1 ]]; then
    TAG=server-v0.0.0
  else
    TAG=$(curl -fsSL --proto '=https' "https://api.github.com/repos/$REPO/releases?per_page=50" |
      jq -r '[.[] | select((.draft|not) and (.prerelease|not) and (.tag_name|startswith("server-v")))][0].tag_name // empty')
  fi
  [[ -n "$TAG" ]] || die "no published server-v* release in $REPO"
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fetch() { run curl -fsSL --proto '=https' --retry 3 -o "$TMP/$2" "https://github.com/$REPO/releases/download/$1/$2"; }

elf=mxbserver-x86_64-unknown-linux-gnu.elf
fetch "$TAG" "$elf"
fetch "$TAG" SHA256SUMS
fetch "$TAG" SHA256SUMS.minisig

if [[ "$DRY" == 1 ]]; then
  echo "+ minisign -V -p $PUBKEY -m SHA256SUMS (comment must name $TAG)"
  echo "+ check sha256 of $elf against SHA256SUMS"
else
  out=$(minisign -V -p "$PUBKEY" -m "$TMP/SHA256SUMS" -x "$TMP/SHA256SUMS.minisig") || die "SHA256SUMS signature does not verify"
  grep -q "^Trusted comment: mxbserver $TAG " <<<"$out" || die "signature is not for $TAG"
  (cd "$TMP" && grep -F " $elf" SHA256SUMS | sed 's/ \*/  /' | sha256sum -c --quiet -) || die "$elf does not match SHA256SUMS"
  chmod 0755 "$TMP/$elf"
  "$TMP/$elf" --version >/dev/null || die "$elf does not run here"
  # Already on this release: the installed binary is byte for byte the release's.
  if cmp -s "$TMP/$elf" /usr/local/bin/mxbserver; then
    echo "current $TAG"
    exit 0
  fi
fi

# Same filesystem as the target, so the final mv is an atomic rename.
sudo_run install -m 0755 "$TMP/$elf" /usr/local/bin/.mxbserver.new
sudo_run mv -f /usr/local/bin/.mxbserver.new /usr/local/bin/mxbserver

for bs in oem-mx1.toml oem-mx2.toml; do
  if [[ "$DRY" == 1 ]] || grep -qF " $bs" "$TMP/SHA256SUMS"; then
    fetch "$TAG" "$bs"
    if [[ "$DRY" == 0 ]]; then
      (cd "$TMP" && grep -F " $bs" SHA256SUMS | sed 's/ \*/  /' | sha256sum -c --quiet -) || die "$bs does not match SHA256SUMS"
    fi
    sudo_run install -m 0644 "$TMP/$bs" "/etc/mxbserver/bike-sets/$bs"
  fi
done

echo "installed $TAG"
