# PowerShell profile, dot-sourced from $PROFILE by install.ps1.
# Keep this file ASCII: Windows PowerShell 5.1 reads BOM-less files as ANSI.

# Tell WezTerm the current directory on every prompt (OSC 7), so that new tabs
# and splits open where you are. PowerShell's cd does not change the process
# working directory, so WezTerm cannot see it otherwise.
if ($env:TERM_PROGRAM -eq 'WezTerm') {
    function prompt {
        $p = $executionContext.SessionState.Path.CurrentLocation
        $osc7 = ''
        if ($p.Provider.Name -eq 'FileSystem') {
            $esc = [char]27
            $path = $p.ProviderPath -replace '\\', '/'
            $osc7 = "$esc]7;file://${env:COMPUTERNAME}/$path$esc\"
        }
        "${osc7}PS $p$('>' * ($nestedPromptLevel + 1)) "
    }
}

# vi / vim / view open Neovim (only when nvim is installed).
# view is a function because a PowerShell alias cannot carry an argument.
if (Get-Command nvim -CommandType Application -ErrorAction SilentlyContinue) {
    Set-Alias -Name vi -Value nvim
    Set-Alias -Name vim -Value nvim
    function view { nvim -R @args }
}

# Per-PC values (the Obsidian vault path and so on) live in ~/.dotfiles.json,
# outside this repo, so the repo works on any PC from any clone location.
# Template: dotfiles.example.json. install.ps1 writes the file when it is missing.
$dotfilesConfig = Join-Path $HOME '.dotfiles.json'
if (Test-Path $dotfilesConfig) {
    try {
        $cfg = Get-Content $dotfilesConfig -Raw | ConvertFrom-Json
        if ($cfg.vault) {
            $env:DOTFILES_VAULT = $cfg.vault
            # vault : go to this PC's Obsidian vault
            function vault { Set-Location $env:DOTFILES_VAULT }
        }
    } catch {
        Write-Warning "cannot read ${dotfilesConfig}: $($_.Exception.Message)"
    }
}

# Where this clone lives, for instructions that point at its tools
# (ai/skills/msbuild-cpp: tools\Survey-Encoding.ps1).
$env:DOTFILES = Split-Path -Parent $PSScriptRoot

# AI agents started from this shell (claude, copilot) use the language servers that
# Neovim's Mason installed (clangd): the editor's own version, sharing its index.
# Neovim puts Mason's bin first on its own PATH; do the same here, once.
$masonBin = Join-Path $env:LOCALAPPDATA 'nvim-data\mason\bin'
if (Test-Path $masonBin) {
    $onPath = @($env:Path -split ';' | ForEach-Object { $_.Replace('/', '\').TrimEnd('\') })
    if ($onPath -notcontains $masonBin) { $env:Path = "$masonBin;$env:Path" }
}
