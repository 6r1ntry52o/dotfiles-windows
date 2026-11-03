<#
.SYNOPSIS
    obsidian\snippets\*.css を vault の .obsidian\snippets に置き、Obsidian で有効にする。

.DESCRIPTION
    正本はこのリポ。vault にあるのは写しで、中身が違えば上書きする（vault で直さない）。
    同じ名前でこのリポのものでない CSS（先頭に dotfiles-windows/obsidian/snippets と書いていない）は
    触らずに警告する。

    有効にするのは Obsidian が開いている時だけ、その CLI（snippet:enable）で行う。閉じている時に
    CLI を呼ぶと Obsidian が起動するので、その時は手順を出すだけにする（次に流せば有効になる）。
    何度流してもよい。

.PARAMETER Vault
    vault の場所。既定は ~/.dotfiles.json の vault。
#>
[CmdletBinding()]
param([string]$Vault)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$marker = 'dotfiles-windows/obsidian/snippets'

if (-not $Vault) {
    $cfgPath = Join-Path $HOME '.dotfiles.json'
    if (Test-Path $cfgPath) {
        try { $Vault = (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json).vault } catch { }
    }
}
if (-not $Vault -or -not (Test-Path (Join-Path $Vault '.obsidian') -PathType Container)) {
    Write-Host 'skip     Obsidian snippets (no vault in ~/.dotfiles.json)'
    return
}
$vaultPath = (Resolve-Path $Vault).Path.TrimEnd('\')
$dest = Join-Path $vaultPath '.obsidian\snippets'

$enabled = @()
$appearance = Join-Path $vaultPath '.obsidian\appearance.json'
if (Test-Path $appearance) {
    try { $enabled = @((Get-Content $appearance -Raw -Encoding UTF8 | ConvertFrom-Json).enabledCssSnippets) } catch { }
}
$obsidian = (Get-Command obsidian -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$running = [bool](Get-Process Obsidian -ErrorAction SilentlyContinue)

foreach ($src in @(Get-ChildItem (Join-Path $repo 'obsidian\snippets') -Filter *.css -ErrorAction SilentlyContinue)) {
    $target = Join-Path $dest $src.Name
    $body = [IO.File]::ReadAllText($src.FullName)
    if (Test-Path $target) {
        $current = [IO.File]::ReadAllText($target)
        if ($current -ceq $body) {
            Write-Host "ok       $target"
        } elseif ($current.Contains($marker)) {
            [IO.File]::WriteAllText($target, $body, (New-Object Text.UTF8Encoding($false)))
            Write-Host "updated  $target"
        } else {
            Write-Warning "$target is not from this repo; left as it is (rename one of them)"
            continue
        }
    } else {
        New-Item -ItemType Directory -Force $dest | Out-Null
        [IO.File]::WriteAllText($target, $body, (New-Object Text.UTF8Encoding($false)))
        Write-Host "copied   $target"
    }

    $name = $src.BaseName
    if ($enabled -contains $name) {
        Write-Host "ok       snippet $name (enabled)"
    } elseif ($obsidian -and $running) {
        $vaultName = Split-Path -Leaf $vaultPath
        $out = @(& $obsidian "vault=$vaultName" 'snippet:enable' "name=$name" 2>&1 | ForEach-Object { "$_" })
        if ($LASTEXITCODE -eq 0) {
            Write-Host "enabled  snippet $name"
        } else {
            Write-Warning "obsidian snippet:enable failed (exit $LASTEXITCODE): $($out -join ' '). Turn it on in Settings > Appearance > CSS snippets"
        }
    } else {
        Write-Host "note     turn on snippet $name in Obsidian (Settings > Appearance > CSS snippets), or run install.ps1 again while Obsidian is open"
    }
}
