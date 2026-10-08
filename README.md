# mxbserver releases

Downloads for **MXB Servers** (the desktop manager) and **mxbserver** (the native MX Bikes
dedicated server for Linux). This repo holds releases and the workflow that builds them. It holds
no source code.

## Download

Open [Releases](../../releases):

| Release | File | For |
| --- | --- | --- |
| `MXB Servers x.y.z` | `MXB-Servers-x.y.z-x64-setup.exe` | Windows 10/11 x64. Signed by Creste LLC. |
| `mxbserver x.y.z` | `mxbserver-x86_64-unknown-linux-gnu.elf` (+ `.minisig`), `VERSION`, `SHA256SUMS`, `SHA256SUMS.minisig`, `oem-*.toml` bike sets | Linux x86-64 servers |
| `mxb-agent x.y.z` | `mxb-agent-windows-x64.zip` (signed exe + `install.ps1`), `mxb-agent-windows-x64.exe`, `mxb-agent-linux-x86_64`, `SHA256SUMS` | The helper next to an official MX Bikes dedicated server that MXB Servers installs and pairs |

Check a server or agent download:

```sh
sha256sum -c SHA256SUMS
```

`server-v*` releases are ordinary **public** releases (never drafts), signed with minisign.
Verify with the public key `minisign.pub` at the root of this repo:

```sh
minisign -V -p minisign.pub -m SHA256SUMS -x SHA256SUMS.minisig
```

## How releases are made (maintainers)

`.github/workflows/release.yml` runs when a tag is pushed here:

| Tag | Builds |
| --- | --- |
| `msm-v0.1.0` | MXB Servers: NSIS installer, Authenticode-signed with Azure Artifact Signing |
| `server-v0.1.0` | mxbserver: `cargo build --release --locked -p mxbserver` on Ubuntu |
| `agent-v0.1.0` | mxb-agent (`apps/agent`): Windows x64 exe Authenticode-signed and zipped with `install.ps1`, Linux x86-64 binary, `SHA256SUMS` over all of them. The tag's version must match `apps/agent/Cargo.toml`. The release stays a draft until every file and `SHA256SUMS` are attached |

A tag with a suffix (`msm-v0.2.0-beta.1`) is published as a pre-release.

The source is private. The workflow checks it out with a read-only deploy key and builds the
commit that carries the same tag there, or the tip of `main` if there is no such tag. The release
notes name the commit. Releases are published with the workflow's own `GITHUB_TOKEN`.

What the workflow needs:

| Kind | Name | What |
| --- | --- | --- |
| Secret | `MXBSERVER_DEPLOY_KEY` | Private half of a read-only deploy key on the source repo |
| Secret | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | The Azure app registration used for code signing |
| Secret | `MSM_SIGNING_PRIVATE_KEY`, `MSM_SIGNING_PRIVATE_KEY_PASSWORD` | MSM's Tauri updater key and its password. The public half is `plugins.updater.pubkey` in `apps/msm/src-tauri/tauri.conf.json` |
| Variable | `ARTIFACT_SIGNING_ENDPOINT`, `ARTIFACT_SIGNING_ACCOUNT`, `ARTIFACT_SIGNING_PROFILE` | The Artifact Signing account and certificate profile |
| Azure | Federated credential `repo:Frostn1/mxbserver-releases:environment:code-signing` | Lets the `code-signing` environment log in over OIDC, with no stored password |

An MSM tag fails before publishing if signing is not configured, so an unsigned installer is
never released. It also fails if the updater key secret is missing or the app's updater public
key is still the placeholder, so every MSM release carries a signed `latest.json`.

MSM finds its updates by listing this repo's releases and taking the newest `msm-v` tag with a
`latest.json` (betas only when the user turns them on). It does not use `releases/latest`,
which a `server-v` release can take.

## Signing server releases (minisign)

A `server-v*` tag signs `SHA256SUMS` (the file `mxbserver ctl update` verifies, as
`SHA256SUMS.minisig`) and the Linux binary, with the trusted comment `mxbserver <tag> <commit>`.
The job fails if the secrets are missing. If `minisign.pub` is committed at the repo root, the
job verifies its own signatures against it before publishing.

Create the key pair once (on a machine you trust):

```sh
minisign -G -p minisign.pub -s minisign.key     # choose a password
```

1. Commit `minisign.pub` at the repo root. Copy it to `/etc/mxbserver/release.pub` on servers that use `ctl update`.
2. Set the secret `MINISIGN_SECRET_KEY` to the full contents of `minisign.key`, and `MINISIGN_PASSWORD` to its password.
3. Keep `minisign.key` out of every repo.

## Hosted boxes

`scripts/box-install.sh` turns a fresh OVH Debian 12 VPS into a box (native: signed `mxbserver`
release, one `mxbserver@sN` unit and Caddy route per slot; legacy: Wine plus `mxb-agent`, a
trial). `.github/workflows/box-install.yml` runs it over SSH when the control plane dispatches
it, reads the tokens back without printing them and enrolls them. Try the script safely with
`bash scripts/test-box-install.sh` (syntax, shellcheck if installed, `--dry-run` plans).

| Kind | Name | What |
| --- | --- | --- |
| Secret | `MINISIGN_SECRET_KEY`, `MINISIGN_PASSWORD` | Release signing key and password (above) |
| Secret | `BOX_SSH_PRIVATE_KEY` | Private half of the SSH key the control plane installs on new boxes (`MXB_HOST_SSH_PUBLIC_KEY`); logs in as `debian` |
| Secret | `MXB_BOX_ENROLL_KEY` | Bearer key for the control plane's `/v1/hosting/boxes/*` and `/v1/hosting/tracks` endpoints |
