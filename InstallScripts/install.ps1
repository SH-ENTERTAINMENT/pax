#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$PaxRepoOwner = "SH-ENTERTAINMENT"
$PaxRepoName = "pax"
$PaxInstallDir = if ($env:PAX_INSTALL_DIR) { $env:PAX_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Pax\bin" }

function Write-Info($message) {
    Write-Host "[pax] $message"
}

function Write-Failure($message) {
    Write-Host "[pax] error: $message" -ForegroundColor Red
    exit 1
}

$arch = if ([Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
} else {
    Write-Failure "32-bit Windows is not supported"
}

$target = "$arch-pc-windows-msvc"

Write-Info "detecting latest release for $target..."
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$PaxRepoOwner/$PaxRepoName/releases/latest" -UseBasicParsing
} catch {
    Write-Failure "failed to query the GitHub releases API: $_"
}

$version = $release.tag_name.TrimStart("v")
if (-not $version) {
    Write-Failure "could not determine the latest pax version"
}

$assetName = "pax-$version-$target.exe"
$downloadUrl = "https://github.com/$PaxRepoOwner/$PaxRepoName/releases/download/v$version/$assetName"
$checksumsUrl = "https://github.com/$PaxRepoOwner/$PaxRepoName/releases/download/v$version/SHA256SUMS"

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $workDir | Out-Null

try {
    Write-Info "downloading pax v$version for $target..."
    $exePath = Join-Path $workDir "pax.exe"
    $checksumsPath = Join-Path $workDir "SHA256SUMS"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $exePath -UseBasicParsing
    Invoke-WebRequest -Uri $checksumsUrl -OutFile $checksumsPath -UseBasicParsing

    Write-Info "verifying checksum..."
    $checksumLine = Select-String -Path $checksumsPath -Pattern ([regex]::Escape($assetName))
    if (-not $checksumLine) {
        Write-Failure "no checksum entry found for $assetName"
    }
    $expectedSum = ($checksumLine.Line -split '\s+')[0].TrimStart("*")
    $actualSum = (Get-FileHash -Path $exePath -Algorithm SHA256).Hash

    if ($expectedSum.ToLower() -ne $actualSum.ToLower()) {
        Write-Failure "checksum mismatch: expected $expectedSum, got $actualSum"
    }

    Write-Info "installing to $PaxInstallDir..."
    New-Item -ItemType Directory -Path $PaxInstallDir -Force | Out-Null
    Copy-Item -Path $exePath -Destination (Join-Path $PaxInstallDir "pax.exe") -Force
} finally {
    Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
}

$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $currentUserPath) { $currentUserPath = "" }

if (($currentUserPath -split ";") -notcontains $PaxInstallDir) {
    Write-Info "adding $PaxInstallDir to your user PATH..."
    $newPath = if ($currentUserPath.Trim().Length -gt 0) { "$currentUserPath;$PaxInstallDir" } else { $PaxInstallDir }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$env:Path;$PaxInstallDir"
}

Write-Info "pax v$version installed successfully."
Write-Info "restart your terminal for the updated PATH to take effect."
& (Join-Path $PaxInstallDir "pax.exe") version
