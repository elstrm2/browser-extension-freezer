$ErrorActionPreference = "Stop"

$POLICY_PATH = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionSettings"

$extensionInstallDirSearchBases = @(
    "$env:LOCALAPPDATA\Google\Chrome",
    "$env:LOCALAPPDATA\Chromium",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser",
    "$env:LOCALAPPDATA\Vivaldi",
    "$env:LOCALAPPDATA\Microsoft\Edge",
    "$env:APPDATA\Opera Software\Opera Stable"
)

function Write-Red { param([string]$Text) Write-Host $Text -ForegroundColor Red -NoNewline }
function Write-Green { param([string]$Text) Write-Host $Text -ForegroundColor Green -NoNewline }
function Write-Cyan { param([string]$Text) Write-Host $Text -ForegroundColor Cyan -NoNewline }

function Get-JsonKeyVal {
    param([string]$FilePath, [string]$Key)
    try {
        $content = Get-Content $FilePath -Raw -ErrorAction Stop
        $json = $content | ConvertFrom-Json -ErrorAction Stop
        return $json.$Key
    } catch {
        try {
            $content = Get-Content $FilePath -Raw -ErrorAction Stop
            if ($content -match "`"$Key`"\s*:\s*`"([^`"]+)`"") {
                return $matches[1]
            }
        } catch {}
        return $null
    }
}

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LatestVersionDir {
    param([string]$ExtPath)
    $dirs = Get-ChildItem -Path $ExtPath -Directory -ErrorAction SilentlyContinue
    if (-not $dirs) { return $null }

    $sorted = $dirs | Sort-Object {
        try {
            [Version]($_.Name -replace '_.*$', '')
        } catch {
            $_.Name
        }
    }
    return $sorted | Select-Object -Last 1
}

function Get-ExtensionBlocked {
    param([string]$ExtId)
    try {
        $extPath = Join-Path $POLICY_PATH $ExtId
        if (Test-Path $extPath) {
            $val = Get-ItemProperty -Path $extPath -Name "override_update_url" -ErrorAction SilentlyContinue
            return $val.override_update_url -eq 1
        }
    } catch {}
    return $false
}

function Set-ExtensionPolicy {
    param([string]$ExtId, [string]$Action)

    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Google\Chrome")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Google" -Name "Chrome" -Force | Out-Null
    }
    if (-not (Test-Path $POLICY_PATH)) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "ExtensionSettings" -Force | Out-Null
    }

    $extPath = Join-Path $POLICY_PATH $ExtId

    if ($Action -eq "d") {
        if (-not (Test-Path $extPath)) {
            New-Item -Path $POLICY_PATH -Name $ExtId -Force | Out-Null
        }
        Set-ItemProperty -Path $extPath -Name "update_url" -Value "https://127.0.0.1/blocked" -Type String
        Set-ItemProperty -Path $extPath -Name "override_update_url" -Value 1 -Type DWord
    } else {
        if (Test-Path $extPath) {
            Remove-Item -Path $extPath -Recurse -Force
        }
    }
}

if (-not (Test-IsAdmin)) {
    Write-Host ""
    Write-Red "ERROR: Run as Administrator!`n"
    Write-Host "Right-click PowerShell -> Run as Administrator"
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "+=============================================================================+"
Write-Host "|           CHROME EXTENSION UPDATE BLOCKER (Policy-based)                   |"
Write-Host "+=============================================================================+"
Write-Host "|  This script blocks extension updates using Chrome Enterprise Policies.    |"
Write-Host "|  It does NOT modify extension files, so no 'corrupted' warnings.           |"
Write-Host "|  Uses Windows Registry: HKLM\SOFTWARE\Policies\Google\Chrome               |"
Write-Host "+=============================================================================+"
Write-Host ""
Write-Host "Scanning for browsers..."
Write-Host ""

$extensionInstallPaths = @()

foreach ($baseDir in $extensionInstallDirSearchBases) {
    if (-not (Test-Path $baseDir)) { continue }

    try {
        $found = Get-ChildItem -Path $baseDir -Directory -Recurse -Depth 5 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "Extensions" -and
                ($_.Parent.Name -eq "Default" -or $_.Parent.Name -match "^Profile")
            } |
            Select-Object -ExpandProperty FullName

        if ($found) { $extensionInstallPaths += $found }
    } catch {}
}

$numExtensionInstallPaths = $extensionInstallPaths.Count

if ($numExtensionInstallPaths -lt 1) {
    Write-Red "No Chrome/Chromium browsers found.`n"
    exit 1
} elseif ($numExtensionInstallPaths -gt 1) {
    Write-Host "Found multiple browsers:"
    for ($i = 0; $i -lt $numExtensionInstallPaths; $i++) {
        Write-Host "  $i) $($extensionInstallPaths[$i])"
    }
    Write-Host ""
    $selectedIndex = Read-Host "Select browser [0-$($numExtensionInstallPaths-1)]"
    if ($selectedIndex -notmatch '^\d+$' -or [int]$selectedIndex -ge $numExtensionInstallPaths) {
        Write-Red "Invalid selection.`n"
        exit 1
    }
    $browserInstallationPath = $extensionInstallPaths[[int]$selectedIndex]
} else {
    Write-Host "Found: $($extensionInstallPaths[0])"
    $browserInstallationPath = $extensionInstallPaths[0]
}

Write-Host ""
Write-Host "Extensions:"
Write-Host "-----------------------------------------------------------------------------"

$extensionDirs = Get-ChildItem -Path $browserInstallationPath -Directory -ErrorAction SilentlyContinue

$extensionIds = @()
$extensionNames = @()
$extensionVersions = @()

$idx = 0
foreach ($extDir in $extensionDirs) {
    $extId = $extDir.Name

    if ($extensionIds -contains $extId) { continue }

    $versionDirs = Get-LatestVersionDir -ExtPath $extDir.FullName

    if (-not $versionDirs) { continue }

    $manifest = Join-Path $versionDirs.FullName "manifest.json"
    if (-not (Test-Path $manifest)) { continue }

    $extName = Get-JsonKeyVal -FilePath $manifest -Key "name"
    $version = Get-JsonKeyVal -FilePath $manifest -Key "version"

    if ([string]::IsNullOrEmpty($extName)) { $extName = $extId }

    $extensionIds += $extId
    $extensionNames += $extName
    $extensionVersions += $version

    if (Get-ExtensionBlocked $extId) {
        Write-Red "BLOCKED"
    } else {
        Write-Green "ALLOWED"
    }

    Write-Host (" {0,-3} {1,-45} v{2}" -f "$idx)", $extName, $version)
    $idx++
}

Write-Host "-----------------------------------------------------------------------------"
Write-Host ""

$numExtensions = $extensionIds.Count
if ($numExtensions -eq 0) {
    Write-Red "No extensions found.`n"
    exit 1
}

$maxIdx = $numExtensions - 1

Write-Host "Commands:"
Write-Cyan "  5 d"; Write-Host "       - block extension #5"
Write-Cyan "  1,3,5 d"; Write-Host "   - block extensions #1, #3, #5"
Write-Cyan "  all d"; Write-Host "     - block ALL extensions"
Write-Cyan "  5 e"; Write-Host "       - allow extension #5 (enable updates)"
Write-Cyan "  all e"; Write-Host "     - allow ALL extensions"
Write-Host ""

$command = Read-Host ">"
$commandArgs = $command -split '\s+'
$indexDescriptor = $commandArgs[0]
$action = $commandArgs[1]

if ($action -notmatch '^[ed]$') {
    Write-Red "Invalid action. Use 'e' (enable) or 'd' (disable/block).`n"
    exit 1
}

$indexesToModify = @()
if ($indexDescriptor -eq "all") {
    $indexesToModify = 0..$maxIdx
} else {
    $indexesToModify = $indexDescriptor -split ',' | ForEach-Object { [int]$_ }
}

Write-Host ""

foreach ($i in $indexesToModify) {
    if ($i -lt 0 -or $i -gt $maxIdx) {
        Write-Red "Index $i out of range (0-$maxIdx)`n"
        continue
    }

    $extId = $extensionIds[$i]
    $extName = $extensionNames[$i]

    if ($action -eq "d") {
        Write-Host -NoNewline "Blocking $extName... "
        Set-ExtensionPolicy -ExtId $extId -Action "d"
        Write-Green "OK"; Write-Host ""
    } else {
        Write-Host -NoNewline "Allowing $extName... "
        Set-ExtensionPolicy -ExtId $extId -Action "e"
        Write-Green "OK"; Write-Host ""
    }
}

Write-Host ""
Write-Host "-----------------------------------------------------------------------------"
if ($action -eq "d") {
    Write-Host "Extensions blocked via Chrome Policy."
    Write-Host "Updates will fail silently (redirected to 127.0.0.1)."
} else {
    Write-Host "Extensions allowed. Updates will work normally."
}
Write-Host ""
Write-Cyan "Restart Chrome and check chrome://policy/ to verify.`n"
Write-Host "-----------------------------------------------------------------------------"
Write-Host ""
