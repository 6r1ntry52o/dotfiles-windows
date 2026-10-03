# dotfiles-windows installer. Safe to re-run.
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   -SkipPackages : do not install anything with winget, only link the config
param([switch]$SkipPackages)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$marker = '-- managed by dotfiles-windows/install.ps1'

function Test-WingetPackage($id) {
    winget list --id $id -e --accept-source-agreements *> $null
    return ($LASTEXITCODE -eq 0)
}

# 1. Packages
if (-not $SkipPackages) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning 'winget not found. Install WezTerm and PowerShell 7 by hand, then re-run with -SkipPackages.'
    } else {
        foreach ($id in 'wez.wezterm', 'Microsoft.PowerShell') {
            if (Test-WingetPackage $id) {
                Write-Host "ok       $id"
            } else {
                Write-Host "install  $id"
                winget install --id $id -e --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -ne 0) { Write-Warning "winget install $id failed (exit $LASTEXITCODE)" }
            }
        }
    }
}

# 2. WezTerm: write a stub at ~/.wezterm.lua that loads the config from this clone.
#    A stub (not a symlink) needs no admin rights and works wherever the repo is cloned.
$wezDir = (Join-Path $repo 'wezterm') -replace '\\', '/'
$stubPath = Join-Path $HOME '.wezterm.lua'
$stub = @"
$marker
local dir = "$wezDir"
package.path = dir .. "/?.lua;" .. package.path
require("wezterm").add_to_config_reload_watch_list(dir .. "/wezterm.lua")
return dofile(dir .. "/wezterm.lua")
"@ -replace "`r`n", "`n"

if (Test-Path $stubPath) {
    $current = Get-Content $stubPath -Raw
    if ($current -notlike "$marker*") {
        $backup = "$stubPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item $stubPath $backup
        Write-Host "backup   $stubPath -> $backup"
    }
}
# UTF-8 without BOM (Lua does not accept a BOM)
[IO.File]::WriteAllText($stubPath, $stub + "`n", (New-Object Text.UTF8Encoding($false)))
Write-Host "linked   $stubPath -> $wezDir/wezterm.lua"

$other = Join-Path $HOME '.config\wezterm\wezterm.lua'
if (Test-Path $other) {
    Write-Warning "$other also exists. WezTerm reads ~/.wezterm.lua first, so that file is ignored."
}

Write-Host 'done. Restart WezTerm (or Ctrl+Shift+R to reload).'
