# Browser Extension Freezer

PowerShell script to freeze Chrome/Edge/Brave/Vivaldi extension versions by disabling auto-updates.

## What it does

Adds `+` before `update_url` in extension's `manifest.json` → breaks update URL → extension can't auto-update.

## Usage

```powershell
# Close browser first!
.\Freeze-Browser-Extensions.ps1
```

You'll see:
```
E 0) uBlock Origin v1.52.0
D 1) Dark Reader v4.9.67      # already frozen
E 2) Bitwarden v2024.1.0

> 0,2 d    # freeze extensions 0 and 2
> 1 e      # unfreeze extension 1
> all d    # freeze all
> q        # quit
```

## Supported browsers

Chrome, Edge, Brave, Vivaldi, and other Chromium-based browsers.

## Credits

Inspired by [rehfeldchris/disable-chrome-extension-auto-update](https://github.com/rehfeldchris/disable-chrome-extension-auto-update) (Bash version).

This is a native PowerShell rewrite for Windows.

## License

MIT