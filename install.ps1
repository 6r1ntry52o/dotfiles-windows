# dotfiles-windows installer. Safe to re-run.
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   -SkipPackages : install nothing (no winget, no font download), only link the config
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

# 2. Font: HackGen Console NF, the Nerd Font flavour of HackGen (https://github.com/yuru7/HackGen).
#    wezterm/wezterm.lua asks for it first, so on a PC without it WezTerm falls back to the
#    bundled JetBrains Mono and the icons come from a second font. It is not on winget, so it
#    comes from the GitHub release. Everything stays inside the user profile
#    (%LOCALAPPDATA%\Microsoft\Windows\Fonts and HKCU), so no admin rights are needed.
#    The version is pinned, and release assets never change, so the hash keeps verifying the same
#    bytes. To update, bump both lines (Get-FileHash <zip> -Algorithm SHA256 prints the new one).
$fontVersion = 'v2.10.0'
$fontSha256 = 'F8ABD483D5EDFAD88A78ED511978F43C83B43C48E364AA29EBE4A68217474428'
# File -> the font's name in the TTF name table (family + style). The HKCU value name is that
# name plus ' (TrueType)'. Bold is installed too, or WezTerm has to synthesise it.
$fontFaces = [ordered]@{
    'HackGenConsoleNF-Regular.ttf' = 'HackGen Console NF Regular'
    'HackGenConsoleNF-Bold.ttf'    = 'HackGen Console NF Bold'
}

if (-not $SkipPackages) {
    $fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $fontMissing = @($fontFaces.Keys | Where-Object {
        -not (Test-Path (Join-Path $fontDir $_)) -or
        -not (Get-ItemProperty $fontKey -Name "$($fontFaces[$_]) (TrueType)" -ErrorAction SilentlyContinue)
    })
    if ($fontMissing.Count -eq 0) {
        Write-Host 'ok       HackGen Console NF'
    } else {
        $fontZip = Join-Path $env:TEMP "HackGen_NF_$fontVersion.zip"
        $fontTmp = Join-Path $env:TEMP "HackGen_NF_$fontVersion"
        try {
            Write-Host "download HackGen_NF_$fontVersion.zip"
            $url = "https://github.com/yuru7/HackGen/releases/download/$fontVersion/HackGen_NF_$fontVersion.zip"
            $progress = $ProgressPreference
            # Windows PowerShell 5.1 spends most of the download redrawing the progress bar
            $ProgressPreference = 'SilentlyContinue'
            try { Invoke-WebRequest -Uri $url -OutFile $fontZip -UseBasicParsing }
            finally { $ProgressPreference = $progress }

            $hash = (Get-FileHash $fontZip -Algorithm SHA256).Hash
            if ($hash -ne $fontSha256) { throw "sha256 mismatch: got $hash, expected $fontSha256" }
            Expand-Archive -Path $fontZip -DestinationPath $fontTmp -Force
            New-Item -ItemType Directory -Force $fontDir | Out-Null

            # Registering in HKCU alone makes the font appear at the next sign-in; AddFontResourceW
            # makes it usable right away.
            if (-not ('Dotfiles.Font' -as [type])) {
                Add-Type -Name Font -Namespace Dotfiles -MemberDefinition @"
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)] public static extern int AddFontResourceW(string file);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr w, IntPtr l);
"@
            }
            foreach ($file in $fontMissing) {
                $src = Get-ChildItem $fontTmp -Recurse -Filter $file | Select-Object -First 1
                if (-not $src) { Write-Warning "$file is not in the zip"; continue }
                $dst = Join-Path $fontDir $file
                Copy-Item $src.FullName $dst -Force
                New-ItemProperty -Path $fontKey -Name "$($fontFaces[$file]) (TrueType)" `
                    -Value $dst -PropertyType String -Force | Out-Null
                [void][Dotfiles.Font]::AddFontResourceW($dst)
                Write-Host "font     $($fontFaces[$file])"
            }
            # Tell every window the font list changed. Post, not Send: a broadcast Send waits for
            # each window's message loop and hangs the installer on a busy one.
            [void][Dotfiles.Font]::PostMessage([IntPtr]0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero)
        } catch {
            Write-Warning "HackGen Console NF not installed: $($_.Exception.Message)"
            Write-Warning 'WezTerm keeps using the fallback font. Re-run install.ps1 to try again.'
        } finally {
            Remove-Item $fontTmp -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $fontZip -Force -ErrorAction SilentlyContinue
        }
    }
}

# 3. WezTerm: write a stub at ~/.wezterm.lua that loads the config from this clone.
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

# 4. PowerShell: add one line to $PROFILE that dot-sources powershell/profile.ps1 from this clone.
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

# 5. WSL: add one line to ~/.bashrc of each distro that sources wsl/osc7.sh from this clone
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

# 6. Neovim: make %LOCALAPPDATA%\nvim a junction to nvim/ in this clone.
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

# 7. Tools: build ime.exe, which switches the IME off from outside the focused window.
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

# 8. Per-PC values: write ~/.dotfiles.json from the template when it is missing.
#    Everything that differs between machines (the Obsidian vault path, display
#    tweaks) lives there, so this repo stays machine-independent and can be cloned
#    anywhere. nvim, WezTerm and the PowerShell profile all read that one file.
$cfgPath = Join-Path $HOME '.dotfiles.json'
if (Test-Path $cfgPath) {
    Write-Host "ok       $cfgPath"
} else {
    $template = Get-Content (Join-Path $repo 'dotfiles.example.json') -Raw
    # Fill in the vault when an Obsidian vault (a directory with .obsidian) is in a usual place
    $vault = ''
    foreach ($c in @((Join-Path $HOME 'core'), (Join-Path $HOME 'vault'), (Join-Path $HOME 'Obsidian'))) {
        if (Test-Path (Join-Path $c '.obsidian')) { $vault = ($c -replace '\\', '/'); break }
    }
    $out = $template -replace '"vault": "[^"]*"', ('"vault": "' + $vault + '"')
    [IO.File]::WriteAllText($cfgPath, $out, (New-Object Text.UTF8Encoding($false)))
    if ($vault) {
        Write-Host "created  $cfgPath (vault = $vault)"
    } else {
        Write-Warning "$cfgPath created. Set 'vault' to this PC's Obsidian vault path (forward slashes)."
    }
}

Write-Host 'done. Restart WezTerm (or Ctrl+Shift+R to reload). Open a new tab to pick up the shell changes.'
Write-Host 'Start nvim once and wait: LazyVim installs its plugins on the first run.'
Write-Host 'On a new PC, run google-ime\Restore-GoogleIme.ps1 to get the Google IME key settings back.'
# Obsidian's Vim IM Select plugin only takes an absolute path, and this repo does not
# know where it was cloned until now, so print the value to paste into its settings.
if (Test-Path $imeOut) {
    Write-Host "Obsidian (Vim IM Select) commands for Windows: $imeOut  /  $imeOut {im}"
}
