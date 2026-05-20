# Vesper Windows Installer
# Usage: irm https://github.com/sipherxyz/vesper-internal-release/releases/latest/download/install-app.ps1 | iex
# Optional override:
#   $env:VESPER_ELECTRON_VERSIONS_URL = "https://raw.githubusercontent.com/sipherxyz/vesper-internal-release/gh-pages/electron"

$ErrorActionPreference = "Stop"

$DEFAULT_VERSIONS_URL = "https://raw.githubusercontent.com/sipherxyz/vesper-internal-release/gh-pages/electron"
$VERSIONS_URL = if ($env:VESPER_ELECTRON_VERSIONS_URL -and $env:VESPER_ELECTRON_VERSIONS_URL.Trim().Length -gt 0) {
    $env:VESPER_ELECTRON_VERSIONS_URL.TrimEnd('/')
} else {
    $DEFAULT_VERSIONS_URL
}
$RELEASE_CHANNEL = if ($env:VESPER_RELEASE_CHANNEL -and $env:VESPER_RELEASE_CHANNEL.Trim().Length -gt 0) {
    $env:VESPER_RELEASE_CHANNEL.Trim().ToLowerInvariant()
} else {
    'latest'
}
$DOWNLOAD_DIR = "$env:TEMP\vesper-install"
$APP_NAME = "Vesper"

if ($RELEASE_CHANNEL -notin @('latest', 'beta', 'nightly')) {
    Write-Err "Unsupported release channel: $RELEASE_CHANNEL"
}

# Colors for output
function Write-Info { Write-Host "> $args" -ForegroundColor Blue }
function Write-Success { Write-Host "> $args" -ForegroundColor Green }
function Write-Warn { Write-Host "! $args" -ForegroundColor Yellow }
function Write-Err { Write-Host "x $args" -ForegroundColor Red; exit 1 }

function Get-GitHubReleaseRepo([string]$Url) {
    if (-not $Url.StartsWith("https://github.com/")) {
        return $null
    }

    $trimmed = $Url.Substring("https://github.com/".Length).TrimEnd('/')
    $parts = $trimmed.Split('/')
    if ($parts.Length -lt 2) {
        return $null
    }

    if ($parts.Length -ge 3 -and $parts[2] -ne 'releases') {
        return $null
    }

    return @{
        owner = $parts[0]
        repo = $parts[1]
    }
}

function Get-ReleaseAssetName([string]$Platform) {
    switch ($Platform) {
        'darwin-arm64' { return 'Vesper-arm64.dmg' }
        'darwin-x64' { return 'Vesper-x64.dmg' }
        'win32-x64' { return 'Vesper-x64.exe' }
        'linux-x64' { return 'Vesper-x86_64.AppImage' }
        default { return $null }
    }
}

function Get-ReleaseChannelForVersion([string]$Version) {
    if ($Version -match '^\d+\.\d+\.\d+-nightly\.\d{12}$') {
        return 'nightly'
    }
    if ($Version -match '^\d+\.\d+\.\d+-beta\.\d+$') {
        return 'beta'
    }
    if ($Version -match '^\d+\.\d+\.\d+$') {
        return 'latest'
    }
    return $null
}

function Test-ReleaseChannelAllowed([string]$SelectedChannel, [string]$CandidateChannel) {
    switch ($SelectedChannel) {
        'latest' { return $CandidateChannel -eq 'latest' }
        'beta' { return $CandidateChannel -in @('latest', 'beta') }
        'nightly' { return $CandidateChannel -in @('latest', 'beta', 'nightly') }
        default { return $false }
    }
}

function Get-ReleaseVersionParts([string]$Version) {
    if ($Version -match '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)-nightly\.(?<build>\d{12})$') {
        return @{
            major = [int]$Matches.major
            minor = [int]$Matches.minor
            patch = [int]$Matches.patch
            rank = 2
            prerelease = [long]$Matches.build
        }
    }

    if ($Version -match '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)-beta\.(?<build>\d+)$') {
        return @{
            major = [int]$Matches.major
            minor = [int]$Matches.minor
            patch = [int]$Matches.patch
            rank = 1
            prerelease = [long]$Matches.build
        }
    }

    if ($Version -match '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$') {
        return @{
            major = [int]$Matches.major
            minor = [int]$Matches.minor
            patch = [int]$Matches.patch
            rank = 3
            prerelease = [long]0
        }
    }

    return $null
}

function Compare-ReleaseVersion([string]$Left, [string]$Right) {
    $leftParts = Get-ReleaseVersionParts $Left
    $rightParts = Get-ReleaseVersionParts $Right
    if (-not $leftParts -or -not $rightParts) {
        return 0
    }

    foreach ($field in @('major', 'minor', 'patch', 'rank', 'prerelease')) {
        if ($leftParts[$field] -gt $rightParts[$field]) {
            return 1
        }
        if ($leftParts[$field] -lt $rightParts[$field]) {
            return -1
        }
    }

    return 0
}

function Test-FoundRequiredReleaseChannels(
    [string]$SelectedChannel,
    [bool]$FoundLatest,
    [bool]$FoundBeta,
    [bool]$FoundNightly
) {
    switch ($SelectedChannel) {
        'latest' { return $FoundLatest }
        'beta' { return $FoundLatest -and $FoundBeta }
        'nightly' { return $FoundLatest -and $FoundBeta -and $FoundNightly }
        default { return $false }
    }
}

# Check for Windows
if ($env:OS -ne "Windows_NT") {
    Write-Err "This installer is for Windows only."
}

# Detect architecture
$arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
$platform = "win32-$arch"

Write-Host ""
Write-Info "Detected platform: $platform"
Write-Info "Using metadata source: $VERSIONS_URL"
Write-Info "Using release channel: $RELEASE_CHANNEL"

$githubRepo = Get-GitHubReleaseRepo $VERSIONS_URL

# Create download directory
New-Item -ItemType Directory -Force -Path $DOWNLOAD_DIR | Out-Null

# Get latest version
if ($githubRepo) {
    Write-Info "Fetching release list..."
    try {
        $releases = @()
        $foundLatest = $false
        $foundBeta = $false
        $foundNightly = $false
        for ($page = 1; $page -le 10; $page++) {
            $pageReleases = Invoke-RestMethod -Uri "https://api.github.com/repos/$($githubRepo.owner)/$($githubRepo.repo)/releases?per_page=100&page=$page" -UseBasicParsing
            if ($pageReleases) {
                $releases += @($pageReleases)
                foreach ($pageRelease in @($pageReleases)) {
                    if ($pageRelease.draft) {
                        continue
                    }

                    $pageVersion = if ($pageRelease.tag_name) { $pageRelease.tag_name -replace '^[Vv]', '' } else { '' }
                    switch (Get-ReleaseChannelForVersion $pageVersion) {
                        'latest' { $foundLatest = $true }
                        'beta' { $foundBeta = $true }
                        'nightly' { $foundNightly = $true }
                    }
                }
            }
            if (Test-FoundRequiredReleaseChannels $RELEASE_CHANNEL $foundLatest $foundBeta $foundNightly) {
                break
            }
            if (@($pageReleases).Count -lt 100) {
                break
            }
        }
        $release = $null
        $bestVersion = $null
        foreach ($candidateRelease in $releases) {
            if ($candidateRelease.draft) {
                continue
            }

            $candidateVersion = if ($candidateRelease.tag_name) { $candidateRelease.tag_name -replace '^[Vv]', '' } else { '' }
            $candidateChannel = Get-ReleaseChannelForVersion $candidateVersion
            if (-not (Test-ReleaseChannelAllowed $RELEASE_CHANNEL $candidateChannel)) {
                continue
            }

            if (-not $bestVersion -or (Compare-ReleaseVersion $candidateVersion $bestVersion) -gt 0) {
                $release = $candidateRelease
                $bestVersion = $candidateVersion
            }
        }
        $releaseTag = $release.tag_name
        if (-not $releaseTag) {
            Write-Err "Failed to resolve a release tag for channel $RELEASE_CHANNEL"
        }
        $latestJson = Invoke-RestMethod -Uri "https://api.github.com/repos/$($githubRepo.owner)/$($githubRepo.repo)/releases/tags/$releaseTag" -UseBasicParsing
        $version = if ($releaseTag) { $releaseTag -replace '^[Vv]', '' } else { $null }
    } catch {
        Write-Err "Failed to fetch latest release: $_"
    }
} else {
    Write-Info "Fetching $RELEASE_CHANNEL pointer..."
    try {
        $latestJson = Invoke-RestMethod -Uri "$VERSIONS_URL/$RELEASE_CHANNEL" -UseBasicParsing
        $version = $latestJson.version
    } catch {
        Write-Err "Failed to fetch latest version: $_"
    }
}

if (-not $version) {
    Write-Err "Failed to get latest version"
}

Write-Info "Latest version: $version"

# Download manifest and extract checksum
if ($githubRepo) {
    Write-Info "Fetching release asset metadata..."
    $assetName = Get-ReleaseAssetName $platform
    if (-not $assetName) {
        Write-Err "Platform $platform is not supported"
    }

    $binaryInfo = $latestJson.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $binaryInfo) {
        Write-Err "Platform $platform not found in latest release assets"
    }

    $checksum = if ($binaryInfo.digest) { $binaryInfo.digest -replace '^sha256:', '' } else { $null }
    $filename = $binaryInfo.name
    $installerUrl = $binaryInfo.browser_download_url
} else {
    Write-Info "Fetching manifest..."
    try {
        $manifest = Invoke-RestMethod -Uri "$VERSIONS_URL/$version/manifest.json" -UseBasicParsing
        $binaryInfo = $manifest.binaries.$platform
        if (-not $binaryInfo) {
            Write-Err "Platform $platform not found in manifest"
        }
        $checksum = $binaryInfo.sha256
        $filename = $binaryInfo.filename
        $installerUrl = $binaryInfo.url
    } catch {
        Write-Err "Failed to fetch manifest: $_"
    }
}

# Validate checksum format
if (-not $checksum -or $checksum.Length -ne 64) {
    Write-Err "Invalid checksum in manifest"
}

# Use default filename if not in manifest
if (-not $filename) {
    $filename = "Vesper-$arch.exe"
}

# Use default URL if not in manifest
if (-not $installerUrl) {
    $installerUrl = "$VERSIONS_URL/$version/$filename"
}

Write-Info "Expected checksum: $($checksum.Substring(0, 16))..."

# Download installer with progress
$installerPath = Join-Path $DOWNLOAD_DIR $filename
$fileSize = $binaryInfo.size
$fileSizeMB = [math]::Round($fileSize / 1MB, 1)

# Clean up any partial download from previous attempts
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

Write-Info "Downloading $filename ($fileSizeMB MB)..."

try {
    # Use WebRequest for download with progress
    $webRequest = [System.Net.HttpWebRequest]::Create($installerUrl)
    $webRequest.Timeout = 600000  # 10 minutes
    $response = $webRequest.GetResponse()
    $responseStream = $response.GetResponseStream()
    $fileStream = [System.IO.File]::Create($installerPath)

    $buffer = New-Object byte[] 65536
    $totalRead = 0
    $lastPercent = -1

    while (($read = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $fileStream.Write($buffer, 0, $read)
        $totalRead += $read

        if ($fileSize -gt 0) {
            $percent = [math]::Floor(($totalRead / $fileSize) * 100)
            if ($percent -ne $lastPercent) {
                $downloadedMB = [math]::Round($totalRead / 1MB, 1)
                $barWidth = 40
                # Cap at 100% for display (actual download may exceed manifest size slightly)
                $displayPercent = [math]::Min($percent, 100)
                $filled = [math]::Min([math]::Floor($displayPercent / (100 / $barWidth)), $barWidth)
                $bar = "[" + ("#" * $filled) + ("-" * ($barWidth - $filled)) + "]"
                Write-Host -NoNewline ("`r  $bar $percent% ($downloadedMB / $fileSizeMB MB)   ")
                $lastPercent = $percent
            }
        }
    }

    $fileStream.Close()
    $responseStream.Close()
    $response.Close()

    Write-Host ""
    Write-Success "Download complete!"
} catch {
    # Clean up partial download on failure
    if ($fileStream) { $fileStream.Close() }
    if ($responseStream) { $responseStream.Close() }
    if ($response) { $response.Close() }
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    Write-Err "Download failed: $_"
}

# Verify file was downloaded
if (-not (Test-Path $installerPath)) {
    Write-Err "Download failed: file not found"
}

# Verify checksum
Write-Info "Verifying checksum..."
$actualHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower()

if ($actualHash -ne $checksum) {
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    Write-Err "Checksum verification failed`n  Expected: $checksum`n  Actual:   $actualHash"
}

Write-Success "Checksum verified!"

# Close the app if it's running
$process = Get-Process -Name "Vesper" -ErrorAction SilentlyContinue
if ($process) {
    Write-Info "Closing Vesper..."
    $process | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# Run the installer
Write-Info "Running installer (follow the installer prompts)..."

try {
    $installerProcess = Start-Process -FilePath $installerPath -PassThru
    $spinner = @('|', '/', '-', '\')
    $i = 0

    while (-not $installerProcess.HasExited) {
        Write-Host -NoNewline ("`r  Installing... " + $spinner[$i % 4] + "   ")
        Start-Sleep -Milliseconds 200
        $i++
    }

    Write-Host -NoNewline "`r                      `r"

    if ($installerProcess.ExitCode -ne 0) {
        Write-Err "Installation failed with exit code: $($installerProcess.ExitCode)"
    }
} catch {
    Write-Err "Installation failed: $_"
}

# Clean up installer
Write-Info "Cleaning up..."
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

# Add command line shortcut
Write-Info "Adding 'vesper' command to PATH..."

$binDir = "$env:LOCALAPPDATA\Vesper\bin"
$cmdFile = "$binDir\vesper.cmd"
$exePath = "$env:LOCALAPPDATA\Programs\Vesper\Vesper.exe"

# Create bin directory
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

# Create batch file launcher
$cmdContent = "@echo off`r`nstart `"`" `"$exePath`" %*"
Set-Content -Path $cmdFile -Value $cmdContent -Encoding ASCII

# Add to user PATH if not already there
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$binDir*") {
    $newPath = "$userPath;$binDir"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Success "Added to PATH (restart terminal to use 'vesper' command)"
} else {
    Write-Success "Command 'vesper' is ready"
}

Write-Host ""
Write-Host "---------------------------------------------------------------------"
Write-Host ""
Write-Success "Installation complete!"
Write-Host ""
Write-Host "  Vesper has been installed."
Write-Host ""
Write-Host "  Launch from:"
Write-Host "    - Start Menu or desktop shortcut"
Write-Host "    - Command line: vesper (restart terminal first)"
Write-Host ""
