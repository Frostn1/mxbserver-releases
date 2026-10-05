# mxbserver releases

Downloads for **MXB Servers** (the desktop manager) and **mxbserver** (the native MX Bikes
dedicated server for Linux). This repo holds releases and the workflow that builds them. It holds
no source code.

## Download

Open [Releases](../../releases):

| Release | File | For |
| --- | --- | --- |
| `MXB Servers x.y.z` | `MXB-Servers-x.y.z-x64-setup.exe` | Windows 10/11 x64. Signed by Creste LLC. |
| `mxbserver x.y.z` | `mxbserver-x86_64-unknown-linux-gnu.elf`, `VERSION`, `SHA256SUMS` | Linux x86-64 servers |
| `mxb-agent x.y.z` | `mxb-agent-windows-x64.zip` (signed exe + `install.ps1`), `mxb-agent-windows-x64.exe`, `mxb-agent-linux-x86_64`, `SHA256SUMS` | The helper next to an official MX Bikes dedicated server that MXB Servers installs and pairs |

Check a server or agent download:

```sh
sha256sum -c SHA256SUMS
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
