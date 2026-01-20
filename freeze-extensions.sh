#!/bin/bash

POLICY_DIR="/etc/opt/chrome/policies/managed"
POLICY_FILE="$POLICY_DIR/extension_updates.json"

extensionInstallDirSearchBases=(
    "$HOME/.config/google-chrome"
    "$HOME/.config/chromium"
    "$HOME/.config/BraveSoftware/Brave-Browser"
    "$HOME/.config/vivaldi"
    "$HOME/.config/opera"
    "/dev/null/skip"
)

set -e
err_report() {
    echo "Error on line $(caller). Exiting." >&2
}
trap 'err_report' ERR

if [ "$EUID" -ne 0 ]; then
    if ! sudo -v 2>/dev/null; then
        echo "ERROR: This script requires sudo privileges."
        echo "Run with: sudo $0"
        exit 1
    fi
fi

getJsonKeyVal() {
    local file="$1"
    local key="$2"
    grep '"'$key'":' "$file" 2>/dev/null | sed 's/.*"'$key'": "\([^"]\+\)".*/\1/' | head -1
}

extractExtensionIdFromPath() {
    local path="$1"
    echo "${path%%/*}"
}

getCurrentPolicy() {
    if [ -f "$POLICY_FILE" ]; then
        cat "$POLICY_FILE"
    else
        echo '{"ExtensionSettings":{}}'
    fi
}

isExtensionBlocked() {
    local extId="$1"
    local policy=$(getCurrentPolicy)
    if command -v jq &> /dev/null; then
        local blocked=$(echo "$policy" | jq -r --arg id "$extId" '.ExtensionSettings[$id].override_update_url // false')
        [ "$blocked" = "true" ] && return 0 || return 1
    else
        grep -q "\"$extId\"" "$POLICY_FILE" 2>/dev/null && return 0 || return 1
    fi
}

updatePolicy() {
    local extId="$1"
    local action="$2"

    if [ ! -d "$POLICY_DIR" ]; then
        sudo mkdir -p "$POLICY_DIR" 2>/dev/null || {
            echo "Cannot create policy dir. Run with sudo or enter password."
            return 1
        }
    fi

    local currentPolicy=$(getCurrentPolicy)

    if command -v jq &> /dev/null; then
        if [ "$action" = "d" ]; then
            newPolicy=$(echo "$currentPolicy" | jq --arg id "$extId" \
                '.ExtensionSettings[$id] = {"update_url": "https://127.0.0.1/blocked", "override_update_url": true}')
        else
            newPolicy=$(echo "$currentPolicy" | jq --arg id "$extId" 'del(.ExtensionSettings[$id])')
        fi
        echo "$newPolicy" | sudo tee "$POLICY_FILE" > /dev/null
    else
        if [ "$action" = "d" ]; then
            if [ ! -f "$POLICY_FILE" ]; then
                sudo bash -c "cat > '$POLICY_FILE'" << EOF
{
  "ExtensionSettings": {
    "$extId": {
      "update_url": "https://127.0.0.1/blocked",
      "override_update_url": true
    }
  }
}
EOF
            else
                local tmp=$(mktemp)
                if grep -q '"ExtensionSettings"' "$POLICY_FILE"; then
                    sed 's/"ExtensionSettings": {/"ExtensionSettings": { "'"$extId"'": {"update_url": "https:\/\/127.0.0.1\/blocked", "override_update_url": true},/' "$POLICY_FILE" > "$tmp"
                    sudo mv "$tmp" "$POLICY_FILE"
                fi
            fi
        else
            if [ -f "$POLICY_FILE" ] && command -v jq &> /dev/null; then
                newPolicy=$(echo "$currentPolicy" | jq --arg id "$extId" 'del(.ExtensionSettings[$id])')
                echo "$newPolicy" | sudo tee "$POLICY_FILE" > /dev/null
            fi
        fi
    fi
}

bold=""
normal=""
if test -t 1; then
    nColors=$(tput colors 2>/dev/null || echo 0)
    if test -n "$nColors" && test "$nColors" -ge 8; then
        _bold="$(tput bold)"
        _normal="$(tput sgr0)"
        _red="$(tput setaf 1)"
        _green="$(tput setaf 2)"
        _yellow="$(tput setaf 3)"
        _cyan="$(tput setaf 6)"
    fi
fi

red() { printf "%s%s%s" "$_red" "$@" "$_normal"; }
green() { printf "%s%s%s" "$_green" "$@" "$_normal"; }
yellow() { printf "%s%s%s" "$_yellow" "$@" "$_normal"; }
cyan() { printf "%s%s%s" "$_cyan" "$@" "$_normal"; }

echo
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║           CHROME EXTENSION UPDATE BLOCKER (Policy-based)                  ║"
echo "╠═══════════════════════════════════════════════════════════════════════════╣"
echo "║  This script blocks extension updates using Chrome Enterprise Policies.   ║"
echo "║  It does NOT modify extension files, so no 'corrupted' warnings.          ║"
echo "║  Requires sudo for policy file in /etc/opt/chrome/policies/               ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo
echo "Scanning for browsers..."
echo

extensionInstallPaths=()
for dir in "${extensionInstallDirSearchBases[@]}"; do
    if [ -d "$dir" ]; then
        foundPaths=$(find "$dir" -mindepth 1 -maxdepth 7 \( -path "*/Default/Extensions" -o -path "*/Profile*/Extensions" \) 2>/dev/null || true)
        while IFS= read -r p; do
            [ -n "$p" ] && extensionInstallPaths+=("$p")
        done <<< "$foundPaths"
    fi
done

numExtensionInstallPaths=${#extensionInstallPaths[@]}
if [ "$numExtensionInstallPaths" -lt "1" ]; then
    red "No Chrome/Chromium browsers found."
    echo
    exit 1
elif [ "$numExtensionInstallPaths" -gt "1" ]; then
    echo "Found multiple browsers:"
    for i in "${!extensionInstallPaths[@]}"; do
        echo "  $i) ${extensionInstallPaths[$i]}"
    done
    echo
    printf "Select browser [0-%d]: " "$((numExtensionInstallPaths-1))"
    read -r selectedIndex
    if ! [[ "$selectedIndex" =~ ^[0-9]+$ ]] || [ "$selectedIndex" -ge "$numExtensionInstallPaths" ]; then
        red "Invalid selection."
        echo
        exit 1
    fi
    browserInstallationPath="${extensionInstallPaths[$selectedIndex]}"
else
    echo "Found: ${extensionInstallPaths[0]}"
    browserInstallationPath="${extensionInstallPaths[0]}"
fi

echo
echo "Extensions:"
echo "─────────────────────────────────────────────────────────────────────────────"

origDir=$(pwd)
cd "$browserInstallationPath"
extensionPathsStr=$(find . -maxdepth 2 -mindepth 2 -type d 2>/dev/null | sort -u)
cd "$origDir"

extensionIds=()
extensionNames=()
extensionVersions=()

idx=0
while IFS= read -r path; do
    [ -z "$path" ] && continue
    path="${path:2}"

    extId=$(echo "$path" | cut -d'/' -f1)

    [[ " ${extensionIds[*]} " =~ " ${extId} " ]] && continue

    latestVersion=$(ls -1 "$browserInstallationPath/$extId" 2>/dev/null | sort -V | tail -1)
    [ -z "$latestVersion" ] && continue

    manifest="$browserInstallationPath/$extId/$latestVersion/manifest.json"
    [ ! -f "$manifest" ] && continue

    extName=$(getJsonKeyVal "$manifest" name)
    version=$(getJsonKeyVal "$manifest" version)

    [ -z "$extName" ] && extName="$extId"

    extensionIds+=("$extId")
    extensionNames+=("$extName")
    extensionVersions+=("$version")

    if isExtensionBlocked "$extId"; then
        status=$(red "BLOCKED")
    else
        status=$(green "ALLOWED")
    fi

    printf "%s %-3s %-45s %s\n" "$status" "$idx)" "$extName" "v$version"
    idx=$((idx + 1))
done <<< "$extensionPathsStr"

echo "─────────────────────────────────────────────────────────────────────────────"
echo

numExtensions=${#extensionIds[@]}
if [ "$numExtensions" -eq 0 ]; then
    red "No extensions found."
    echo
    exit 1
fi

maxIdx=$((numExtensions - 1))

echo "Commands:"
echo "  $(cyan '5 d')       - block extension #5"
echo "  $(cyan '1,3,5 d')   - block extensions #1, #3, #5"
echo "  $(cyan 'all d')     - block ALL extensions"
echo "  $(cyan '5 e')       - allow extension #5 (enable updates)"
echo "  $(cyan 'all e')     - allow ALL extensions"
echo
printf "> "
read -r command

commandArgs=($command)
indexDescriptor="${commandArgs[0]}"
action="${commandArgs[1]}"

if [[ ! "$action" =~ ^[ed]$ ]]; then
    red "Invalid action. Use 'e' (enable) or 'd' (disable/block)."
    echo
    exit 1
fi

indexesToModify=()
if [ "$indexDescriptor" = "all" ]; then
    for i in $(seq 0 $maxIdx); do
        indexesToModify+=($i)
    done
else
    IFS=',' read -ra indexesToModify <<< "$indexDescriptor"
fi

echo
for idx in "${indexesToModify[@]}"; do
    if [ "$idx" -lt 0 ] || [ "$idx" -gt "$maxIdx" ]; then
        red "Index $idx out of range (0-$maxIdx)"
        echo
        continue
    fi

    extId="${extensionIds[$idx]}"
    extName="${extensionNames[$idx]}"

    if [ "$action" = "d" ]; then
        echo -n "Blocking $extName... "
        updatePolicy "$extId" "d"
        green "OK"
        echo
    else
        echo -n "Allowing $extName... "
        updatePolicy "$extId" "e"
        green "OK"
        echo
    fi
done

echo
echo "─────────────────────────────────────────────────────────────────────────────"
if [ "$action" = "d" ]; then
    echo "Extensions blocked via Chrome Policy."
    echo "Updates will fail silently (redirected to 127.0.0.1)."
else
    echo "Extensions allowed. Updates will work normally."
fi
echo
echo "Restart Chrome and check $(cyan 'chrome://policy/') to verify."
echo "─────────────────────────────────────────────────────────────────────────────"
echo
