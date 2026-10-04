<#
.SYNOPSIS
  Authenticode-sign files with Azure Artifact Signing, or skip cleanly when it isn't set up.

.DESCRIPTION
  Set up by .github/actions/artifact-signing, which exports ARTIFACT_SIGNING=1 and the paths
  used below. Tauri calls this for each binary it signs (see that action's signCommand overlay),

  Without ARTIFACT_SIGNING=1 it prints a notice and exits 0, so an unsigned build (a fork, or
  before the Azure account exists) still succeeds.

.EXAMPLE
  pwsh scripts/sign-windows.ps1 path	oile.exe
#>
param(
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
  [string[]] $Files
)

$ErrorActionPreference = 'Stop'

# Tauri runs this as its signCommand and shows none of its output when it fails (only
# "failed to run pwsh"), so keep a transcript the workflow can print afterwards.
if ($env:RUNNER_TEMP) {
  try { Start-Transcript -Path (Join-Path $env:RUNNER_TEMP 'sign-windows.log') -Append | Out-Null } catch { }
}

if ($env:ARTIFACT_SIGNING -ne '1') {
  Write-Host "sign-windows: signing not configured; leaving unsigned: $($Files -join ', ')"
  exit 0
}

foreach ($name in @('ARTIFACT_SIGNING_SIGNTOOL', 'ARTIFACT_SIGNING_DLIB', 'ARTIFACT_SIGNING_METADATA')) {
  if (-not (Get-Item "env:$name" -ErrorAction SilentlyContinue)) {
    throw "sign-windows: ARTIFACT_SIGNING=1 but $name is not set; run .github/actions/artifact-signing first"
  }
}

# The Azure login done before the build used a GitHub OIDC assertion that expires within minutes
# (AADSTS700024), long before a release build reaches signing. Log in again with a fresh token.
function Connect-AzureFresh {
  if (-not ($env:ACTIONS_ID_TOKEN_REQUEST_URL -and $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN -and
      $env:AZURE_CLIENT_ID -and $env:AZURE_TENANT_ID)) {
    Write-Host 'sign-windows: no OIDC request env (or Azure ids); keeping the existing az session'
    return
  }
  $uri = $env:ACTIONS_ID_TOKEN_REQUEST_URL + '&audience=' + [uri]::EscapeDataString('api://AzureADTokenExchange')
  $resp = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN" }
  $token = $resp.value
  if (-not $token) { throw 'sign-windows: GitHub returned no OIDC token' }
  Write-Host "::add-mask::$token"
  $o = & az login --service-principal -u $env:AZURE_CLIENT_ID --tenant $env:AZURE_TENANT_ID --federated-token $token --allow-no-subscriptions 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "sign-windows: az login failed: $o" }
  if ($env:AZURE_SUBSCRIPTION_ID) {
    & az account set --subscription $env:AZURE_SUBSCRIPTION_ID 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'sign-windows: az account set failed' }
  }
  Write-Host 'sign-windows: refreshed Azure login with a fresh OIDC token'
}

# Artifact Signing's certificates last three days, so every signature is timestamped with
# Microsoft's RFC 3161 service, which keeps it valid after the certificate expires.
$timestamp = 'http://timestamp.acs.microsoft.com'

foreach ($file in $Files) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    throw "sign-windows: no such file: $file"
  }
  # One retry: the service or the timestamp server occasionally drops a request, and a whole
  # release shouldn't fail over it.
  $signed = $false
  for ($attempt = 1; $attempt -le 3 -and -not $signed; $attempt++) {
    Connect-AzureFresh
    # Arguments as an array, so a path with a space stays one argument. Output is captured and
    # printed: Tauri shows nothing of this script's output when it fails.
    $signArgs = @('sign', '/v', '/debug', '/fd', 'SHA256', '/tr', $timestamp, '/td', 'SHA256',
      '/dlib', $env:ARTIFACT_SIGNING_DLIB, '/dmdf', $env:ARTIFACT_SIGNING_METADATA, $file)
    $out = & $env:ARTIFACT_SIGNING_SIGNTOOL @signArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host $out
    $signed = $code -eq 0
    if (-not $signed -and $attempt -lt 3) {
      Write-Host "sign-windows: signing $file failed (exit $code); retrying in 15 s"
      Start-Sleep -Seconds 15
    }
  }
  if (-not $signed) {
    throw "sign-windows: could not sign $file"
  }
  $vout = & $env:ARTIFACT_SIGNING_SIGNTOOL verify /pa /v $file 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    Write-Host $vout
    throw "sign-windows: $file was signed but its signature does not verify"
  }
  Write-Host "sign-windows: signed $file"
}
