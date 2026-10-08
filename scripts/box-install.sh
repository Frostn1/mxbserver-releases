#!/usr/bin/env bash
# box-install.sh: set up a freshly rebuilt OVH VPS as a hosted-server box.
#
# Public script, no secrets. Run as the default sudo user (sudo is used inside; the user
# must have passwordless sudo, as OVH's `ubuntu` and `debian` users do). The control plane reads the
# tokens this script writes under /root/mxb-enroll/ and then deletes that folder.
#
#   box-install.sh --pool native|legacy --slots N --pubkey-file minisign.pub \
#       [--release-repo Frostn1/mxbserver-releases] [--ip 1.2.3.4] \
#       [--tracks-json tracks.json] [--game-url URL] [--admin-keys-file keys] [--dry-run]
#
# --admin-keys-file: operator SSH public keys, one per line, added to the running user's
# authorized_keys so an operator can log in next to the install key.
#
# native: minisign-verified server-v* release, one mxbserver@sN unit per slot, Caddy in front.
# legacy: Wine + PiBoSo's dedicated-server download + mxb-agent (agent-v*) with N instances.
#         The whole legacy path is a TRIAL: nothing here has run on a real box yet.
#
# Layout the control plane assumes (native, slot i = 1..N):
#   game port UDP 54209+i, admin API 127.0.0.1:(9808+2*i), /etc/mxbserver/s$i/server.toml,
#   tokens_file /etc/mxbserver/s$i/admin-tokens.toml, unit mxbserver@s$i,
#   public path https://<ip-dashed>.sslip.io/s$i/...
# legacy: instances s1..sN on game ports 54209+i, agent on 127.0.0.1:8787, path /agent/...
#
# Tokens are never printed. Plaintext goes only to root-only files in /root/mxb-enroll.
set -euo pipefail
umask 077

POOL=""; SLOTS=""; REPO="Frostn1/mxbserver-releases"; PUBKEY=""; IP=""
TRACKS_JSON=""; GAME_URL=""; ADMIN_KEYS=""; DRY=0

die() { echo "box-install: $*" >&2; exit 1; }
say() { echo "== $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pool) POOL="${2:-}"; shift 2 ;;
    --slots) SLOTS="${2:-}"; shift 2 ;;
    --release-repo) REPO="${2:-}"; shift 2 ;;
    --pubkey-file) PUBKEY="${2:-}"; shift 2 ;;
    --ip) IP="${2:-}"; shift 2 ;;
    --tracks-json) TRACKS_JSON="${2:-}"; shift 2 ;;
    --game-url) GAME_URL="${2:-}"; shift 2 ;;
    --admin-keys-file) ADMIN_KEYS="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n 2,25p "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$POOL" == native || "$POOL" == legacy ]] || die "--pool must be native or legacy"
[[ "$SLOTS" =~ ^[0-9]+$ && "$SLOTS" -ge 1 && "$SLOTS" -le 20 ]] || die "--slots must be 1-20"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--release-repo must be owner/name"
[[ -n "$PUBKEY" ]] || die "--pubkey-file is required"
[[ "$IP" == "" || "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--ip must be an IPv4 address"
[[ "$DRY" == 1 || -f "$PUBKEY" ]] || die "--pubkey-file $PUBKEY not found"
[[ -z "$TRACKS_JSON" || "$DRY" == 1 || -f "$TRACKS_JSON" ]] || die "--tracks-json $TRACKS_JSON not found"
if [[ "$POOL" == legacy && -z "$GAME_URL" ]]; then die "--game-url is required for --pool legacy"; fi
[[ -z "$ADMIN_KEYS" || "$DRY" == 1 || -f "$ADMIN_KEYS" ]] || die "--admin-keys-file $ADMIN_KEYS not found"

ENROLL=/root/mxb-enroll
TRACKS_DIR=/etc/mxbserver/tracks
BIKE_DIR=/etc/mxbserver/bike-sets
GAME_DIR=/opt/mxbikes
AGENT_DIR=/opt/mxb-agent
TMP=""

# run CMD...: execute, or print in --dry-run.
run() {
  if [[ "$DRY" == 1 ]]; then echo "+ $*"; else "$@"; fi
}
# sudo_run CMD...: same, as root.
sudo_run() { run sudo "$@"; }

# put FILE MODE OWNER:GROUP < content. Never logs content.
put() {
  local file="$1" mode="$2" owner="$3"
  if [[ "$DRY" == 1 ]]; then
    cat >/dev/null
    echo "+ write $file (mode $mode, $owner)"
  else
    local tmp
    tmp=$(mktemp)
    cat >"$tmp"
    sudo install -D -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$tmp" "$file"
    rm -f "$tmp"
  fi
}

latest_tag() { # latest_tag PREFIX -> newest published, non-prerelease release tag with PREFIX
  if [[ "$DRY" == 1 ]]; then echo "${1}0.0.0"; return; fi
  curl -fsSL --proto '=https' "https://api.github.com/repos/$REPO/releases?per_page=50" |
    jq -r --arg p "$1" '[.[] | select((.draft|not) and (.prerelease|not) and (.tag_name|startswith($p)))][0].tag_name // empty'
}

fetch() { # fetch TAG NAME DEST
  run curl -fsSL --proto '=https' --retry 3 -o "$3" "https://github.com/$REPO/releases/download/$1/$2"
}

# verify_release TAG DIR: SHA256SUMS must carry a minisign signature from --pubkey-file whose
# trusted comment names this tag. Files are then checked against the signed sums by check_sum.
verify_release() {
  local tag="$1" dir="$2"
  if [[ "$DRY" == 1 ]]; then echo "+ minisign -V -p $PUBKEY -m $dir/SHA256SUMS (comment must name $tag)"; return; fi
  local out
  out=$(minisign -V -p "$PUBKEY" -m "$dir/SHA256SUMS" -x "$dir/SHA256SUMS.minisig") || die "SHA256SUMS signature does not verify"
  grep -q "^Trusted comment: mxbserver $tag " <<<"$out" || die "signature is not for $tag"
}

check_sum() { # check_sum DIR NAME: NAME's hash in the (verified) SHA256SUMS must match the file
  local dir="$1" name="$2"
  if [[ "$DRY" == 1 ]]; then echo "+ check sha256 of $name against SHA256SUMS"; return; fi
  (cd "$dir" && grep -F " $name" SHA256SUMS | sed 's/ \*/  /' | sha256sum -c --quiet -) || die "$name does not match SHA256SUMS"
}

apt_base() {
  say "packages"
  sudo_run apt-get update -qq
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl ca-certificates gnupg jq ufw debian-keyring debian-archive-keyring apt-transport-https openssl "$@"
}

install_caddy() {
  say "caddy (official apt repo)"
  if [[ "$DRY" == 0 ]] && command -v caddy >/dev/null; then echo "caddy already installed"; return; fi
  run bash -c 'curl -fsSL --proto "=https" https://dl.cloudsmith.io/public/caddy/stable/gpg.key | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg'
  run bash -c 'curl -fsSL --proto "=https" https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null'
  sudo_run apt-get update -qq
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq caddy
}

host_name() {
  local ip="$IP"
  if [[ -z "$ip" ]]; then
    if [[ "$DRY" == 1 ]]; then ip="203.0.113.10"; else ip=$(curl -4 -fsS --max-time 10 https://api.ipify.org) || die "pass --ip"; fi
  fi
  echo "${ip//./-}.sslip.io"
}

# track_sync DEST_DIR NAMING (id|url): download every track in --tracks-json, checking sha256.
track_sync() {
  local dest="$1" naming="$2"
  sudo_run install -d -m 0755 "$dest"
  if [[ -z "$TRACKS_JSON" ]]; then echo "no --tracks-json: no tracks synced"; return; fi
  say "tracks -> $dest"
  if [[ "$DRY" == 1 ]]; then echo "+ for each {id,url,sha256} in $TRACKS_JSON: download, verify sha256, install"; return; fi
  local n i id url sha file got
  n=$(jq '.tracks | length' "$TRACKS_JSON")
  for ((i = 0; i < n; i++)); do
    id=$(jq -r ".tracks[$i].id" "$TRACKS_JSON")
    url=$(jq -r ".tracks[$i].url" "$TRACKS_JSON")
    sha=$(jq -r ".tracks[$i].sha256" "$TRACKS_JSON")
    [[ "$id" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || die "bad track id in tracks json"
    [[ "$sha" =~ ^[0-9a-fA-F]{64}$ ]] || die "bad sha256 for track $id"
    [[ "$url" == https://* ]] || die "track $id url is not https"
    if [[ "$naming" == id ]]; then
      file="$id.pkz"
    else
      file=$(basename "${url%%\?*}")
      [[ "$file" =~ ^[A-Za-z0-9._-]+$ ]] || file="$id.pkz"
    fi
    if [[ -f "$dest/$file" ]] && [[ "$(sha256sum "$dest/$file" | cut -d' ' -f1)" == "${sha,,}" ]]; then continue; fi
    curl -fsSL --proto '=https' --retry 3 -o "$TMP/track.part" "$url"
    got=$(sha256sum "$TMP/track.part" | cut -d' ' -f1)
    [[ "$got" == "${sha,,}" ]] || die "track $id: sha256 mismatch"
    sudo install -m 0644 "$TMP/track.part" "$dest/$file"
    echo "track $id ok"
  done
}

first_track_id() { # first manifest track's id, or empty
  if [[ -n "$TRACKS_JSON" && "$DRY" == 0 ]]; then jq -r '.tracks[0].id // empty' "$TRACKS_JSON"; fi
}

write_caddy() { # write_caddy HOST "PATH PORT"...: one handle_path block per argument
  local host="$1"
  shift
  {
    echo "$host {"
    local b
    for b in "$@"; do
      printf '\thandle_path %s {\n' "${b%% *}"
      printf '\t\treverse_proxy 127.0.0.1:%s\n' "${b##* }"
      printf '\t}\n'
    done
    printf '\trespond 404\n}\n'
  } | put /etc/caddy/Caddyfile 0644 root:root
  sudo_run systemctl enable caddy
  sudo_run systemctl restart caddy
}

firewall() { # firewall UDP_PORT...
  say "firewall"
  sudo_run ufw allow 22/tcp
  sudo_run ufw allow 80/tcp
  sudo_run ufw allow 443/tcp
  local p
  for p in "$@"; do sudo_run ufw allow "$p/udp"; done
  sudo_run ufw --force enable
}

# ---------------------------------------------------------------- native

unit_file() {
  # From deploy/mxbserver@.service in the mxbserver source (an ops file).
  cat <<'UNIT'
[Unit]
Description=Native MX Bikes dedicated server (%i)
Documentation=https://github.com/Frostn1/mxbserver
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=mxbserver
Group=mxbserver
WorkingDirectory=/etc/mxbserver/%i
EnvironmentFile=-/etc/mxbserver/%i/mxbserver.env
ExecStart=/usr/local/bin/mxbserver --config /etc/mxbserver/%i/server.toml $MXBSERVER_ARGS
Restart=on-failure
RestartForceExitStatus=75
RestartSec=3
StateDirectory=mxbserver/%i
TimeoutStopSec=15
KillSignal=SIGINT
LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictAddressFamilies=AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
UNIT
}

# new_control_token ID TOKEN_FILE TOKENS_TOML: runs `mxbserver admin token new`, keeps the
# plaintext only in TOKEN_FILE (root-only) and the digest entry in TOKENS_TOML. Prints nothing.
new_control_token() {
  local id="$1" tokfile="$2" tomlfile="$3"
  if [[ "$DRY" == 1 ]]; then
    echo "+ mxbserver admin token new --id $id --scope control  (plaintext -> $tokfile, digest entry -> $tomlfile)"
    return
  fi
  if sudo test -s "$tokfile" && sudo test -s "$tomlfile"; then echo "token $id already present"; return; fi
  local out bearer entry
  out=$(/usr/local/bin/mxbserver admin token new --id "$id" --scope control)
  bearer=$(grep -v -e '^#' -e '^$' <<<"$out" | head -n1)
  entry=$(sed -n '/^\[\[token\]\]/,$p' <<<"$out")
  [[ -n "$bearer" && -n "$entry" ]] || die "could not parse 'admin token new' output for $id"
  printf '%s\n' "$bearer" | put "$tokfile" 0600 root:root
  printf '%s\n' "$entry" | put "$tomlfile" 0640 root:mxbserver
}

install_native() {
  local host
  host=$(host_name)
  apt_base minisign
  install_caddy

  say "mxbserver release"
  local tag
  tag=$(latest_tag server-v)
  [[ -n "$tag" ]] || die "no published server-v* release in $REPO"
  local elf=mxbserver-x86_64-unknown-linux-gnu.elf
  fetch "$tag" "$elf" "$TMP/$elf"
  fetch "$tag" SHA256SUMS "$TMP/SHA256SUMS"
  fetch "$tag" SHA256SUMS.minisig "$TMP/SHA256SUMS.minisig"
  verify_release "$tag" "$TMP"
  check_sum "$TMP" "$elf"
  sudo_run install -m 0755 "$TMP/$elf" /usr/local/bin/mxbserver

  say "service user, unit"
  if [[ "$DRY" == 1 ]] || ! id mxbserver >/dev/null 2>&1; then
    sudo_run useradd --system --home /nonexistent --shell /usr/sbin/nologin mxbserver
  fi
  sudo_run install -d -m 0755 /etc/mxbserver
  if [[ "$DRY" == 1 ]]; then
    echo "+ install $PUBKEY as /etc/mxbserver/release.pub (for mxbserver ctl update)"
  else
    put /etc/mxbserver/release.pub 0644 root:root <"$PUBKEY"
  fi
  unit_file | put /etc/systemd/system/mxbserver@.service 0644 root:root
  # ProtectSystem=strict: let the service rewrite its own config (control plane config/write).
  printf '[Service]\nReadWritePaths=/etc/mxbserver/%%i\n' | put /etc/systemd/system/mxbserver@.service.d/hosted.conf 0644 root:root
  sudo_run systemctl daemon-reload

  say "bike sets"
  sudo_run install -d -m 0755 "$BIKE_DIR"
  local bs have_mx2=0
  for bs in oem-mx1.toml oem-mx2.toml; do
    # Attached to server-v* releases and covered by the signed SHA256SUMS.
    if [[ "$DRY" == 1 ]] || grep -qF " $bs" "$TMP/SHA256SUMS"; then
      fetch "$tag" "$bs" "$TMP/$bs"
      check_sum "$TMP" "$bs"
      sudo_run install -m 0644 "$TMP/$bs" "$BIKE_DIR/$bs"
      if [[ "$bs" == oem-mx2.toml ]]; then have_mx2=1; fi
    else
      echo "warning: $bs is not in release $tag"
    fi
  done

  track_sync "$TRACKS_DIR" id
  local first package
  first=$(first_track_id)
  package="$TRACKS_DIR/${first:-track-server}.pkz"

  say "slots"
  sudo_run install -d -m 0700 "$ENROLL"
  local i game admin
  for ((i = 1; i <= SLOTS; i++)); do
    game=$((54209 + i))
    admin=$((9808 + 2 * i))
    sudo_run install -d -m 0755 -o mxbserver -g mxbserver "/etc/mxbserver/s$i"
    new_control_token "cp-s$i" "$ENROLL/s$i.token" "/etc/mxbserver/s$i/admin-tokens.toml"
    if [[ "$DRY" == 0 ]] && sudo test -s "/etc/mxbserver/s$i/server.toml"; then
      echo "s$i server.toml exists, left alone"
    else
      {
        printf '[server]\nname = "MXB Server %s"\nlisten = "0.0.0.0:%s"\nmax_clients = 20\n\n' "$i" "$game"
        printf '[track]\npackage = "%s"\n\n' "$package"
        if [[ "$have_mx2" == 1 ]]; then printf '[bike_set]\nmanifest = "%s/oem-mx2.toml"\n\n' "$BIKE_DIR"; fi
        printf '[admin]\nlisten = "127.0.0.1:%s"\ntokens_file = "/etc/mxbserver/s%s/admin-tokens.toml"\n' "$admin" "$i"
      } | put "/etc/mxbserver/s$i/server.toml" 0644 mxbserver:mxbserver
    fi
    sudo_run systemctl enable "mxbserver@s$i"
    run sudo systemctl restart "mxbserver@s$i" || echo "warning: mxbserver@s$i did not start (no track yet?)"
  done

  local blocks=() ports=()
  for ((i = 1; i <= SLOTS; i++)); do
    blocks+=("/s$i/* $((9808 + 2 * i))")
    ports+=($((54209 + i)))
  done
  write_caddy "$host" "${blocks[@]}"
  firewall "${ports[@]}"
  say "native box ready: https://$host/s1/"
}

# ---------------------------------------------------------------- legacy (trial)

install_legacy() {
  local host
  host=$(host_name)
  apt_base wine64 p7zip-full xvfb
  install_caddy

  # TRIAL / UNPROVEN: the PiBoSo download is expected to be an archive or installer that 7z can
  # unpack into a folder holding mxbikes.exe. Nobody has run this on a real box.
  say "game files (unproven)"
  sudo_run install -d -m 0755 "$GAME_DIR"
  if [[ "$DRY" == 1 ]] || [[ ! -f "$GAME_DIR/mxbikes.exe" ]]; then
    run curl -fsSL --proto '=https' --retry 3 -o "$TMP/game.bin" "$GAME_URL"
    sudo_run 7z x -y "-o$GAME_DIR" "$TMP/game.bin"
  fi
  track_sync "$GAME_DIR/mods/tracks" url

  say "mxb-agent"
  local tag
  tag=$(latest_tag agent-v)
  [[ -n "$tag" ]] || die "no published agent-v* release in $REPO"
  fetch "$tag" mxb-agent-linux-x86_64 "$TMP/mxb-agent-linux-x86_64"
  fetch "$tag" SHA256SUMS "$TMP/SHA256SUMS"
  # agent-v* releases carry no minisign signature yet; SHA256SUMS comes from the same release.
  check_sum "$TMP" mxb-agent-linux-x86_64
  sudo_run install -m 0755 "$TMP/mxb-agent-linux-x86_64" /usr/local/bin/mxb-agent

  sudo_run install -d -m 0700 "$ENROLL"
  local i json inst="" ports=()
  for ((i = 1; i <= SLOTS; i++)); do
    # Placeholder ini per instance; the control plane edits it through the agent.
    printf '[connection]\nname = "MXB Server %s"\nport = %s\n' "$i" $((54209 + i)) | put "$GAME_DIR/s$i.ini" 0644 root:root
    inst+="{\"id\":\"s$i\",\"ini\":\"s$i.ini\",\"game_port\":$((54209 + i))}"
    if [[ $i -lt $SLOTS ]]; then inst+=","; fi
    ports+=($((54209 + i)))
  done
  if [[ "$DRY" == 1 ]]; then
    echo "+ write $AGENT_DIR/agent.json (fresh token -> $ENROLL/agent.token, instances s1..s$SLOTS, launch_prefix wine)"
  elif sudo test -s "$ENROLL/agent.token" && sudo test -s "$AGENT_DIR/agent.json"; then
    echo "agent.json already present"
  else
    local token
    token=$(openssl rand -hex 32)
    printf '%s\n' "$token" | put "$ENROLL/agent.token" 0600 root:root
    json=$(jq -n --arg t "$token" --arg g "$GAME_DIR" --argjson inst "[$inst]" \
      '{token:$t, listen:"127.0.0.1:8787", game_dir:$g, tracks_path:($g+"/mods/tracks"),
        launch_prefix:["xvfb-run","-a","wine"], instances:$inst}')
    printf '%s\n' "$json" | put "$AGENT_DIR/agent.json" 0600 root:root
    token=""
    json=""
  fi
  # `install` keeps an existing agent.json; the Linux service uses the account that ran sudo.
  # Its output is the pairing line, which carries the token: never shown.
  if [[ "$DRY" == 1 ]]; then
    echo "+ sudo /usr/local/bin/mxb-agent install --game-dir $GAME_DIR --listen 127.0.0.1:8787 (output discarded)"
  else
    sudo /usr/local/bin/mxb-agent install --game-dir "$GAME_DIR" --listen 127.0.0.1:8787 --user "${SUDO_USER:-$(id -un)}" >/dev/null
  fi

  write_caddy "$host" "/agent/* 8787"
  firewall "${ports[@]}"
  say "legacy box ready (trial): https://$host/agent/"
}

if [[ "$DRY" == 1 ]]; then
  TMP=/tmp/box-install.DRYRUN
  echo "DRY RUN: pool=$POOL slots=$SLOTS repo=$REPO ip=${IP:-auto} tracks=${TRACKS_JSON:-none}"
else
  command -v sudo >/dev/null || die "sudo is required"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
fi

# admin_keys: append each public key line of --admin-keys-file to this user's authorized_keys,
# once. Lines that aren't a public key are skipped.
admin_keys() {
  [[ -n "$ADMIN_KEYS" ]] || return 0
  say "operator ssh keys"
  local auth="$HOME/.ssh/authorized_keys" line n=0
  if [[ "$DRY" == 1 ]]; then echo "+ append keys from $ADMIN_KEYS to $auth"; return; fi
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$auth"
  chmod 600 "$auth"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521)|sk-[a-z0-9@.-]+)\ [A-Za-z0-9+/=]+(\ .*)?$ ]] || continue
    grep -qxF -- "$line" "$auth" || { printf '%s\n' "$line" >>"$auth"; n=$((n + 1)); }
  done <"$ADMIN_KEYS"
  echo "added $n key(s)"
}

admin_keys
if [[ "$POOL" == native ]]; then install_native; else install_legacy; fi
