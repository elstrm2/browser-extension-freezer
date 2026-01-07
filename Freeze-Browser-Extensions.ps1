#!/usr/bin/env pwsh

# ============================================================================
# Freeze-Browser-Extensions.ps1
# PowerShell port of https://github.com/rehfeldchris/disable-chrome-extension-auto-update
# 
# This script enables or disables the automatic extension update feature 
# for specific browser extensions you have installed.
# It works by editing the extension manifest file to manipulate the update_url,
# basically breaking the update url by prepending a "+" character.
# ============================================================================

# Exit on errors
$ErrorActionPreference = "Stop"

# Edit these vars to point to the equivalent location used by Chromium based browsers.
# Windows 10/8/7/Vista: C:\Users\%USERNAME%\AppData\Local\Google\Chrome\User Data\Default\Extensions\<Extension ID>
# Windows XP: C:\Documents and Settings\%USERNAME%\Local Settings\Application Data\Google\Chrome\User Data\Default\Extensions\<Extension ID>
# macOS: ~/Library/Application Support/Google/Chrome/Default/Extensions/<Extension ID>
# Linux: ~/.config/google-chrome/Default/Extensions/<Extension ID>

$extensionInstallDirSearchBases = @(
    "$env:LOCALAPPDATA",
    "$env:APPDATA",
    "$env:USERPROFILE\.config",
    # Custom paths - add your portable browsers here, example:
    "C:\TCPU74\Programm\slimjet"
)

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Red {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Red -NoNewline
}

function Write-Green {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Green -NoNewline
}

function Write-Yellow {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Yellow -NoNewline
}

# Returns the value of a certain key from a json file.
# It's not a robust json parser - mimics the original bash grep/sed approach.
function Get-JsonKeyVal {
    param(
        [string]$FilePath,
        [string]$Key
    )
    
    try {
        $content = Get-Content $FilePath -Raw -ErrorAction Stop
        # Try proper JSON parsing first
        $json = $content | ConvertFrom-Json -ErrorAction Stop
        return $json.$Key
    }
    catch {
        # Fallback to regex like original bash script
        try {
            $content = Get-Content $FilePath -Raw -ErrorAction Stop
            if ($content -match "`"$Key`"\s*:\s*`"([^`"]+)`"") {
                return $matches[1]
            }
        }
        catch {}
        return $null
    }
}

# Edits the manifest file, altering the line which has the json "update_url" key and value.
# Normally, update_url is a valid url like "https://google.com/...." but this func will 
# prepend a "+" symbol, making the url look like "+https://google.com/....".
# The presence of the + symbol will cause the update process to fail, which prevents automatic updates.
function Edit-UpdateUrl {
    param(
        [string]$ManifestPath,
        [string]$EnableDisable
    )
    
    $content = Get-Content $ManifestPath -Raw
    
    if ($EnableDisable -eq "e") {
        # Enable: remove + before http
        # Original: sed -i 's/"update_url": "+http/"update_url": "http/g'
        $content = $content -replace '"update_url": "\+http', '"update_url": "http'
    }
    else {
        # Disable: add + before http  
        # Original: sed -i 's/"update_url": "http/"update_url": "+http/g'
        $content = $content -replace '"update_url": "http', '"update_url": "+http'
    }
    
    Set-Content -Path $ManifestPath -Value $content -NoNewline -Encoding UTF8
}

# ============================================================================
# Main Script
# ============================================================================

Write-Host ""
Write-Host "This script will enable or disable the automatic extension update feature for specific browser extensions you have installed."
Write-Host "It will not actually enable or disable the *operation* of the extension for you, it just controls the update process by editing the extension manifest file to manipulate the update_url variable, basically breaking the update url."
Write-Host ""
Write-Host "Scanning..."
Write-Host ""

# Find all the different extension install dirs, including those for different brands of chromium based browsers
# We search for all dirs containing "Default\Extensions" (exactly like original bash script)
# This will automatically find Chrome, Edge, Brave, Vivaldi, Slimjet, etc.
$extensionInstallPaths = @()

foreach ($baseDir in $extensionInstallDirSearchBases) {
    if (-not (Test-Path $baseDir)) {
        continue
    }
    
    # Replicate: find "$dir" -mindepth 1 -maxdepth 7 -path "*/Default/Extensions"
    # Search for any "Extensions" folder inside a "Default" folder (or Profile folders)
    try {
        # Replicate exactly: find "$dir" -mindepth 1 -maxdepth 7 -path "*/Default/Extensions"
        $found = Get-ChildItem -Path $baseDir -Directory -Recurse -Depth 7 -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.Name -eq "Extensions" -and 
                $_.Parent.Name -eq "Default"
            } |
            Select-Object -ExpandProperty FullName
        
        if ($found) {
            $extensionInstallPaths += $found
        }
    }
    catch {
        # Ignore errors during search
    }
}

# Give feedback about which browser installs we found
$numExtensionInstallPaths = $extensionInstallPaths.Count

if ($numExtensionInstallPaths -lt 1) {
    Write-Host "Didn't find any Chrome install directories in any of these paths: $($extensionInstallDirSearchBases -join ', ')"
    Write-Host "Edit the extensionInstallDirSearchBases variable, then try again."
    exit 1
}
elseif ($numExtensionInstallPaths -gt 1) {
    Write-Host "Found multiple Chromium based browser installs:"
    Write-Host ""
    
    $validatedIndex = -1
    while ($validatedIndex -lt 0) {
        for ($i = 0; $i -lt $numExtensionInstallPaths; $i++) {
            Write-Host "$i) $($extensionInstallPaths[$i])"
        }
        
        Write-Host ""
        $index = Read-Host "Enter the number for which browser install you wish to manage extensions for"
        
        if ($index -match '^\d+$' -and [int]$index -ge 0 -and [int]$index -lt $numExtensionInstallPaths) {
            $validatedIndex = [int]$index
        }
        else {
            Write-Host ""
            Write-Red "Bad input ($index).`n"
            Write-Red "Input wasn't a number, or the number was not within the range of values of 0 through $($numExtensionInstallPaths - 1).`n"
            Write-Host ""
            Start-Sleep -Seconds 1
        }
    }
    
    $browserInstallationPath = $extensionInstallPaths[$validatedIndex]
}
else {
    Write-Host "Found a single Chromium based browser install."
    $browserInstallationPath = $extensionInstallPaths[0]
}

Write-Host "Using: $browserInstallationPath"
Write-Host ""

# Scan the filesystem for extension directory names inside the install dir.
# Replicate: find . -maxdepth 2 -mindepth 2 -type d
# This gets extension_id/version directories
$extensionPaths = @()
$extensionDirs = Get-ChildItem -Path $browserInstallationPath -Directory -ErrorAction SilentlyContinue

foreach ($extDir in $extensionDirs) {
    $versionDirs = Get-ChildItem -Path $extDir.FullName -Directory -ErrorAction SilentlyContinue
    foreach ($verDir in $versionDirs) {
        $extensionPaths += @{
            ExtensionId = $extDir.Name
            VersionDir = $verDir.Name
            FullPath = $verDir.FullName
        }
    }
}

$numExtensionPaths = $extensionPaths.Count

if ($numExtensionPaths -eq 0) {
    Write-Host ""
    Write-Red "Zero installed extensions found.`n"
    Write-Red "Are you sure any are actually installed in $browserInstallationPath ?`n"
    exit 1
}

Write-Host "Extensions found:"
Write-Host ""

# Parse each extension's manifest.json file
$extensions = @()
$i = 0

foreach ($extPath in $extensionPaths) {
    $manifestPath = Join-Path $extPath.FullPath "manifest.json"
    
    if (-not (Test-Path $manifestPath)) {
        continue
    }
    
    $extName = Get-JsonKeyVal -FilePath $manifestPath -Key "name"
    $updateUrl = Get-JsonKeyVal -FilePath $manifestPath -Key "update_url"
    $version = Get-JsonKeyVal -FilePath $manifestPath -Key "version"
    
    # Skip extensions without update_url (like unpacked extensions)
    if ([string]::IsNullOrEmpty($updateUrl)) {
        continue
    }
    
    # Output some info about the extension.
    # If the first char is a +, it means we already disabled the update process for this extension.
    if ($updateUrl.StartsWith("+")) {
        Write-Red "D"
    }
    else {
        Write-Green "E"
    }
    
    # Handle __MSG_ placeholders in extension names
    $displayName = $extName
    if ([string]::IsNullOrEmpty($extName) -or $extName -match "^__MSG_") {
        $displayName = "$extName [$($extPath.ExtensionId)]"
    }
    
    # Format like original: printf "%s %-4s %s\n" "$enabledDisabled" "$i)" "$extName v$version"
    Write-Host (" {0,-4} {1} v{2}" -f "$i)", $displayName, $version)
    
    $extensions += @{
        Index = $i
        Path = $manifestPath
        Name = $displayName
        ExtensionId = $extPath.ExtensionId
        UpdateUrl = $updateUrl
    }
    
    $i++
}

if ($extensions.Count -eq 0) {
    Write-Host ""
    Write-Red "No extensions with update_url found.`n"
    exit 1
}

$numExtensions = $extensions.Count
$maxExtensionIndex = $numExtensions - 1

# Ask the user which extensions to enable/disable.
$validatedArgs = -1

while ($validatedArgs -lt 0) {
    Write-Host ""
    Write-Host "Enter an extension index number, followed by either e or d to enable or disable it."
    Write-Host "Examples:"
    Write-Host "4 e - enable extension at index 4"
    Write-Host "4,7,11 d - disable extensions at indexes 4, 7, and 11"
    Write-Host "all e - enable all extensions"
    Write-Host "q - quit"
    
    $command = Read-Host ">"
    
    if ($command -eq "q" -or $command -eq "quit" -or $command -eq "exit") {
        Write-Host "Exiting."
        exit 0
    }
    
    $commandParts = $command -split '\s+'
    $indexDescriptor = $commandParts[0]
    $enableDisable = $commandParts[1]
    
    # Validate: [[ $enableDisable =~ ^[ed]$ ]] && [[ $indexDescriptor =~ ^(all|[0-9]+(,[0-9]+)*)$ ]]
    if ($enableDisable -match '^[ed]$' -and $indexDescriptor -match '^(all|\d+(,\d+)*)$') {
        $validatedArgs = 1
        
        if ($indexDescriptor -eq "all") {
            $indexesToModify = 0..$maxExtensionIndex
        }
        else {
            $indexesToModify = $indexDescriptor -split ',' | ForEach-Object { [int]$_ }
            
            # Validate each index is in range
            foreach ($idx in $indexesToModify) {
                if ($idx -lt 0 -or $idx -gt $maxExtensionIndex) {
                    Write-Host ""
                    Write-Red "Bad input.`n"
                    Write-Red "Index $idx is out of range. Indexes must be between 0 and $maxExtensionIndex.`n"
                    Write-Host ""
                    Start-Sleep -Seconds 1
                    $validatedArgs = -1
                    break
                }
            }
        }
    }
    else {
        Write-Host ""
        Write-Red "Bad input. Follow the examples, and try again.`n"
        Write-Host ""
        Start-Sleep -Seconds 1
    }
}

# Loop over the list of extension indexes, and modify each extension.
foreach ($idx in $indexesToModify) {
    $ext = $extensions[$idx]
    
    Write-Host ""
    Write-Host "modifying $($ext.Name)"
    Write-Host "$($ext.Path)"
    
    try {
        Edit-UpdateUrl -ManifestPath $ext.Path -EnableDisable $enableDisable
        
        # Verify the change (like original script)
        $newUpdateUrl = Get-JsonKeyVal -FilePath $ext.Path -Key "update_url"
        
        if ($newUpdateUrl -match "^h" -and $enableDisable -eq "e") {
            Write-Host "Success. Enabled."
        }
        elseif ($newUpdateUrl -match "^\+" -and $enableDisable -eq "d") {
            Write-Host "Success. Disabled."
        }
    }
    catch {
        Write-Red "Error: $_`n"
    }
}

Write-Host ""
Write-Host "Done."