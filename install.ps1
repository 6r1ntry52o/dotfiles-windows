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
        Write-Warning 'winget not found. Install the packages listed in README by hand, then re-run with -SkipPackages.'
    } else {
        # Neovim, plus what LazyVim needs: ripgrep / fd / fzf (search), lazygit,
        # zig (C compiler) and tree-sitter-cli (both build the treesitter parsers).
        $packages = 'wez.wezterm', 'Microsoft.PowerShell', 'Neovim.Neovim',
            'BurntSushi.ripgrep.MSVC', 'sharkdp.fd', 'junegunn.fzf',
            'JesseDuffield.lazygit', 'zig.zig', 'tree-sitter.tree-sitter-cli'
        foreach ($id in $packages) {
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

# 3. PowerShell: add one line to $PROFILE that dot-sources powershell/profile.ps1 from this clone.
#    The rest of an existing profile is left as it is.
$psMarker = '# managed by dotfiles-windows/install.ps1'
$psLine = ". '$(Join-Path $repo 'powershell\profile.ps1')' $psMarker"
$docs = [Environment]::GetFolderPath('MyDocuments')

function Add-ProfileLine($path) {
    $lines = @()
    if (Test-Path $path) { $lines = @(Get-Content $path) }
    if ($lines -contains $psLine) {
        Write-Host "ok       $path"
        return
    }
    $lines = @($lines | Where-Object { $_ -notlike "*$psMarker" }) + $psLine
    New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
    # UTF-8 with BOM, so that Windows PowerShell 5.1 reads a non-ASCII path correctly
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding($true)))
    Write-Host "linked   $path -> powershell\profile.ps1"
}

Add-ProfileLine (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')

# Windows PowerShell 5.1 refuses to load a profile under its default policy (Restricted)
# and would print an error on every start, so link it only when scripts are allowed.
$policy = Get-ExecutionPolicy -List |
    Where-Object { $_.Scope -ne 'Process' -and $_.ExecutionPolicy -ne 'Undefined' } |
    Select-Object -First 1
if ($PSVersionTable.PSVersion.Major -ge 6) {
    Write-Host 'skip     Windows PowerShell 5.1 profile (run this script with powershell.exe to link it)'
} elseif ($policy -and $policy.ExecutionPolicy -in 'RemoteSigned', 'Unrestricted', 'Bypass') {
    Add-ProfileLine (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
} else {
    Write-Host 'skip     Windows PowerShell 5.1 profile (execution policy does not allow scripts)'
}

# 4. WSL: add one line to ~/.bashrc of each distro that sources wsl/osc7.sh from this clone
#    (and to ~/.zshrc for wsl/osc7.zsh, when the distro has zsh).
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $env:WSL_UTF8 = '1'
    $distros = @(wsl.exe -l -q 2>$null | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -notlike 'docker-desktop*' })
    if ($LASTEXITCODE -ne 0) { $distros = @() }
    $winPath = (Join-Path $repo 'wsl\install.sh') -replace '\\', '/'
    foreach ($d in $distros) {
        Write-Host "wsl      $d"
        $linuxPath = wsl.exe -d $d -e wslpath -a $winPath
        wsl.exe -d $d -e bash $linuxPath
        if ($LASTEXITCODE -ne 0) { Write-Warning "wsl/install.sh failed in $d (exit $LASTEXITCODE)" }
    }
}

# 5. Neovim: make %LOCALAPPDATA%\nvim a junction to nvim/ in this clone.
#    lazy.nvim writes lazy-lock.json into the config directory, so the whole
#    directory has to live in the repo for the plugin versions to be tracked.
#    A junction (not a symlink) needs no admin rights.
$nvimSrc = Join-Path $repo 'nvim'
$nvimDst = Join-Path $env:LOCALAPPDATA 'nvim'
$item = Get-Item $nvimDst -Force -ErrorAction SilentlyContinue
$target = if ($item -and $item.LinkType) { @($item.Target)[0] -replace '^\\\?\?\\', '' } else { $null }

if ($target -and ($target.TrimEnd('\') -eq $nvimSrc.TrimEnd('\'))) {
    Write-Host "ok       $nvimDst"
} else {
    if ($item -and $item.LinkType) {
        # A link left from an older clone location: remove the link only, not its target
        cmd /c rmdir "$nvimDst"
    } elseif ($item) {
        $backup = "$nvimDst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Rename-Item $nvimDst $backup
        Write-Host "backup   $nvimDst -> $backup"
    }
    New-Item -ItemType Junction -Path $nvimDst -Target $nvimSrc | Out-Null
    Write-Host "linked   $nvimDst -> $nvimSrc"
}

# 6. Tools: build ime.exe, which switches the IME off from outside the focused window.
#    The Obsidian Vim plugin calls it; Neovim does the same thing in Lua (nvim/lua/config/ime.lua).
#    Built with the csc.exe that ships with Windows (.NET Framework), so no SDK is needed.
#    /target:winexe keeps a console window from flashing on every Esc.
$imeSrc = Join-Path $repo 'tools\ime\Ime.cs'
$imeOut = Join-Path $repo 'tools\bin\ime.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) {
    Write-Warning "csc.exe not found at $csc. Skipping ime.exe."
} elseif ((Test-Path $imeOut) -and ((Get-Item $imeOut).LastWriteTime -ge (Get-Item $imeSrc).LastWriteTime)) {
    Write-Host "ok       $imeOut"
} else {
    New-Item -ItemType Directory -Force (Split-Path -Parent $imeOut) | Out-Null
    & $csc /nologo /optimize /target:winexe "/out:$imeOut" $imeSrc
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "csc failed (exit $LASTEXITCODE)"
    } else {
        Write-Host "built    $imeOut"
    }
}

Write-Host 'done. Restart WezTerm (or Ctrl+Shift+R to reload). Open a new tab to pick up the shell changes.'
Write-Host 'Start nvim once and wait: LazyVim installs its plugins on the first run.'
Write-Host 'On a new PC, run google-ime\Restore-GoogleIme.ps1 to get the Google IME key settings back.'
