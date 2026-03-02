# Vesper Windows Installer
# Usage:
#   powershell -c "irm https://raw.githubusercontent.com/sipherxyz/vesper-internal-release/main/install.ps1 | iex"

$ErrorActionPreference = "Stop"

$RepoOwner = "sipherxyz"
$RepoName = "vesper-internal-release"
$LatestReleaseApi = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
$DownloadDir = Join-Path $env:TEMP "vesper-install"
$AssetName = "Vesper-x64.exe"

function Write-Info { Write-Host "> $args" -ForegroundColor Blue }
function Write-Success { Write-Host "> $args" -ForegroundColor Green }
function Write-Warn { Write-Host "! $args" -ForegroundColor Yellow }
function Write-Err { Write-Host "x $args" -ForegroundColor Red; exit 1 }

function Refresh-UserPathInCurrentSession {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $combined = @($machinePath, $userPath) -join ";"
    $env:Path = $combined
}

function Install-ClaudeIfNeeded {
    Refresh-UserPathInCurrentSession
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        Write-Success "Found Claude CLI: $($claudeCmd.Source)"
        return
    }

    Write-Info "Claude CLI not found. Installing from https://code.claude.com/docs/en/overview ..."
    try {
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            "irm https://claude.ai/install.ps1 | iex"
        ) -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Claude installer exited with code $($proc.ExitCode)"
        }
        Refresh-UserPathInCurrentSession
        $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
        if ($claudeCmd) {
            Write-Success "Claude CLI installed: $($claudeCmd.Source)"
        } else {
            Write-Warn "Claude installer ran, but 'claude' is not in PATH yet. Restart terminal if needed."
        }
    } catch {
        Write-Warn "Failed to install Claude CLI automatically. Install manually via https://code.claude.com/docs/en/overview"
    }
}

function Install-AiGatewayIfNeeded {
    Refresh-UserPathInCurrentSession
    $gatewayCmd = Get-Command ai-gateway -ErrorAction SilentlyContinue
    if ($gatewayCmd) {
        Write-Success "Found ai-gateway CLI: $($gatewayCmd.Source)"
        return
    }

    Write-Info "ai-gateway CLI not found. Installing from https://github.com/sipherxyz/ai-gateway-cli ..."
    try {
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            "irm https://ai-gateway.atherlabs.com/install.ps1 | iex"
        ) -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "ai-gateway installer exited with code $($proc.ExitCode)"
        }
        Refresh-UserPathInCurrentSession
        $gatewayCmd = Get-Command ai-gateway -ErrorAction SilentlyContinue
        if ($gatewayCmd) {
            Write-Success "ai-gateway CLI installed: $($gatewayCmd.Source)"
        } else {
            Write-Warn "ai-gateway installer ran, but 'ai-gateway' is not in PATH yet. Restart terminal if needed."
        }
    } catch {
        Write-Warn "Failed to install ai-gateway automatically. Install manually via https://github.com/sipherxyz/ai-gateway-cli"
    }
}

function Ensure-AiGatewayLoginIfNeeded {
    Refresh-UserPathInCurrentSession
    $gatewayCmd = Get-Command ai-gateway -ErrorAction SilentlyContinue
    if (-not $gatewayCmd) {
        Write-Warn "Skipping ai-gateway login check because ai-gateway is not available."
        return
    }

    Write-Info "Checking ai-gateway login status..."
    $statusOutput = & ai-gateway status 2>&1 | Out-String

    $hasKeyMissing = $statusOutput -match '(?i)(^|\s)key=missing($|\s)'
    $hasSessionOk = $statusOutput -match '(?i)(^|\s)session=ok($|\s)'
    $hasSessionPresent = $statusOutput -match '(?i)(^|\s)session=present($|\s)'
    $needsLogin = $hasKeyMissing -or (-not $hasSessionOk -and -not $hasSessionPresent)

    if ($needsLogin) {
        Write-Info "ai-gateway is not logged in. Running 'ai-gateway login'..."
        & ai-gateway login
        if ($LASTEXITCODE -eq 0) {
            Write-Success "ai-gateway login completed."
        } else {
            Write-Warn "ai-gateway login did not complete. You can run 'ai-gateway login' manually."
        }
    } else {
        Write-Success "ai-gateway status does not indicate a missing login."
    }
}

function Install-RequiredCliDependencies {
    Write-Host ""
    Write-Info "Checking required CLI dependencies (claude, ai-gateway)..."
    Install-ClaudeIfNeeded
    Install-AiGatewayIfNeeded
    Ensure-AiGatewayLoginIfNeeded
}

if ($env:OS -ne "Windows_NT") {
    Write-Err "This installer is for Windows only."
}

if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Err "Vesper currently supports Windows 64-bit only."
}

Write-Host ""
Write-Info "Detected platform: win32-x64"

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

Write-Info "Fetching latest release metadata..."
try {
    $release = Invoke-RestMethod -Uri $LatestReleaseApi -UseBasicParsing
} catch {
    Write-Err "Failed to fetch latest release metadata: $_"
}

$tagName = $release.tag_name
if (-not $tagName) {
    Write-Err "Could not determine latest release tag"
}

$asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
if (-not $asset) {
    Write-Err "Asset '$AssetName' not found in latest release ($tagName)."
}

$installerUrl = $asset.browser_download_url
if (-not $installerUrl) {
    Write-Err "No download URL found for asset '$AssetName'"
}

$expectedChecksum = $null
if ($asset.digest -and $asset.digest.StartsWith("sha256:")) {
    $expectedChecksum = $asset.digest.Substring(7).ToLower()
}

Write-Info "Latest release: $tagName"
$installerPath = Join-Path $DownloadDir $AssetName

if (Test-Path $installerPath) {
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
}

Write-Info "Downloading $AssetName..."
try {
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
} catch {
    Write-Err "Download failed: $_"
}

if (-not (Test-Path $installerPath)) {
    Write-Err "Download failed: file not found"
}

if ($expectedChecksum) {
    Write-Info "Verifying SHA-256 checksum..."
    $actualChecksum = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower()

    if ($actualChecksum -ne $expectedChecksum) {
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        Write-Err "Checksum verification failed`n  Expected: $expectedChecksum`n  Actual:   $actualChecksum"
    }

    Write-Success "Checksum verified"
} else {
    Write-Warn "No checksum digest published for this asset. Skipping verification."
}

$running = Get-Process -Name "Vesper" -ErrorAction SilentlyContinue
if ($running) {
    Write-Info "Closing running Vesper process..."
    $running | Stop-Process -Force
    Start-Sleep -Seconds 2
}

Write-Info "Running installer (follow the installer prompts)..."
try {
    $proc = Start-Process -FilePath $installerPath -PassThru
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        Write-Err "Installer exited with code $($proc.ExitCode)"
    }
} catch {
    Write-Err "Failed to run installer: $_"
}

Write-Info "Cleaning up installer file..."
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

$binDir = Join-Path $env:LOCALAPPDATA "Vesper\bin"
$cmdPath = Join-Path $binDir "vesper.cmd"
$exePath = Join-Path $env:LOCALAPPDATA "Programs\Vesper\Vesper.exe"

New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$cmdContent = "@echo off`r`nstart `"`" `"$exePath`" %*"
Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) {
    $userPath = ""
}

if ($userPath -notlike "*$binDir*") {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $binDir } else { "$userPath;$binDir" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Success "Added '$binDir' to your user PATH (restart terminal to use 'vesper')."
} else {
    Write-Success "'vesper' command is available in your user PATH."
}

Install-RequiredCliDependencies

Write-Host ""
Write-Success "Installation complete"
Write-Host "  Installed to: $exePath"
Write-Host "  Launch from Start Menu, desktop shortcut, or by running: vesper"
