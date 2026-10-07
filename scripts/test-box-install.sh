#!/usr/bin/env bash
# Local checks for box-install.sh: syntax, shellcheck (if installed), argument validation and
# the --dry-run plan for both pools. Needs only bash. Run: bash scripts/test-box-install.sh
set -euo pipefail
cd "$(dirname "$0")"
S=./box-install.sh
fail() { echo "FAIL: $*" >&2; exit 1; }

bash -n "$S" && echo "ok  bash -n"
if command -v shellcheck >/dev/null; then shellcheck "$S" "$0" && echo "ok  shellcheck"; else echo "skip shellcheck (not installed)"; fi

expect_fail() { if bash "$S" "$@" >/dev/null 2>&1; then fail "should reject: $*"; fi; }
expect_fail
expect_fail --pool nope --slots 2 --pubkey-file x --dry-run
expect_fail --pool native --slots 0 --pubkey-file x --dry-run
expect_fail --pool native --slots 2 --dry-run
expect_fail --pool legacy --slots 2 --pubkey-file x --dry-run
expect_fail --pool native --slots 2 --pubkey-file x --release-repo 'a b' --dry-run
echo "ok  argument validation"

native=$(bash "$S" --pool native --slots 2 --pubkey-file minisign.pub --ip 203.0.113.7 --dry-run)
for want in \
  "minisign -V" \
  "/usr/local/bin/mxbserver" \
  "/etc/mxbserver/s1/server.toml" "/etc/mxbserver/s2/server.toml" \
  "mxbserver admin token new --id cp-s2 --scope control" \
  "$(printf '%s' '/root/mxb-enroll/s1.token')" \
  "mxbserver@.service.d/hosted.conf" \
  "/etc/caddy/Caddyfile" \
  "ufw allow 54210/udp" "ufw allow 54211/udp" "ufw allow 443/tcp"; do
  grep -qF -- "$want" <<<"$native" || fail "native plan lacks: $want"
done
echo "ok  native dry-run"

legacy=$(bash "$S" --pool legacy --slots 2 --pubkey-file minisign.pub --ip 203.0.113.7 \
  --game-url https://example.invalid/mxb.zip --dry-run)
for want in "wine64" "7z x" "agent.token" "mxb-agent install" "ufw allow 54211/udp"; do
  grep -qF -- "$want" <<<"$legacy" || fail "legacy plan lacks: $want"
done
echo "ok  legacy dry-run"

# No token or secret may appear in the plans.
if grep -Eq '[0-9a-f]{40,}' <<<"$native$legacy"; then fail "long hex string in dry-run output"; fi
echo "all box-install checks passed"
