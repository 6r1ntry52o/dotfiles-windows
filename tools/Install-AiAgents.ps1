<#
.SYNOPSIS
    AI エージェント（Claude Code・GitHub Copilot CLI）に、エディタと同じ C/C++ の道具を使わせる。

.DESCRIPTION
    入っているエージェントの分だけ設定する（どちらも無い PC では何もしない）。
      - スキル: ai\skills\<名前>\ を、各エージェントのスキル置き場に junction で見せる。正本は
        このリポの 1 枚。エージェントが常に読むのは説明の 1 行だけで、本文はその作業の時に読む。
          Claude Code   ~/.claude/skills/<名前>    （CLAUDE_CONFIG_DIR があればその下）
          Copilot CLI   ~/.copilot/skills/<名前>   （COPILOT_HOME があればその下）
      - 言語サーバ（LSP）:
          Claude Code   公式プラグイン clangd-lsp（rustup がある PC では rust-analyzer-lsp も）
          Copilot CLI   ~/.copilot/lsp-config.json に、無いサーバの項目だけ足す（既存の項目は
                        変えない。書き換える前に .bak-日時 に退避する）
      - rust-analyzer: rustup がある PC で、そのコンポーネントを入れる（rust-analyzer-lsp が呼ぶ）

    clangd は Neovim の Mason が入れたものを使う（nvim を一度起動すると入る）。エディタと同じ版で、
    索引（.cache/clangd）も共有になる。エージェントからは、powershell/profile.ps1 が PATH の先頭に
    足す Mason の bin で見える（nvim の外のタブから起動しても同じ）。

    外から取り込む（プラグインと rust-analyzer を取得する）だけで、この PC の情報を外へ送る仕組みは
    足さない。何度流してもよい。

.PARAMETER SkipPackages
    取得を伴うもの（プラグイン・rust-analyzer）を飛ばし、スキルと設定だけ置く。

.EXAMPLE
    pwsh -File tools\Install-AiAgents.ps1
    入れたあと、新しいタブで claude か copilot を起動する（PATH が変わるため）
#>
[CmdletBinding()]
param([switch]$SkipPackages)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

function Test-Command($name) {
    [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

# 外部コマンドを呼ぶ。Windows PowerShell 5.1 は $ErrorActionPreference = 'Stop' の時に
# stderr への出力を例外にするので、この中だけ Continue にする。
function Invoke-Tool {
    $ErrorActionPreference = 'Continue'
    $exe = $args[0]
    $rest = @($args | Select-Object -Skip 1)
    $out = @(& $exe @rest 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}

# $link を $target への junction にする。別の場所を指す link（clone を移した時）は link だけ外す。
# 実体のディレクトリは $backupDir に退避する（スキル置き場の中に残すと、同じ名前のスキルが
# 2 つ読まれるため）。
function Set-Junction($link, $target, $backupDir) {
    $item = Get-Item $link -Force -ErrorAction SilentlyContinue
    $current = if ($item -and $item.LinkType) { @($item.Target)[0] -replace '^\\\?\?\\', '' } else { $null }
    if ($current -and ($current.TrimEnd('\') -eq $target.TrimEnd('\'))) {
        Write-Host "ok       $link"
        return
    }
    if ($item -and $item.LinkType) {
        cmd /c rmdir "$link"
    } elseif ($item) {
        $backup = Join-Path $backupDir ('{0}.bak-{1}' -f (Split-Path -Leaf $link), (Get-Date -Format yyyyMMdd-HHmmss))
        Move-Item $link $backup
        Write-Host "backup   $link -> $backup"
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent $link) | Out-Null
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Write-Host "linked   $link -> $target"
}

$claudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
$hasClaude = (Test-Command claude) -or (Test-Path $claudeHome)
$hasCopilot = (Test-Command copilot) -or (Test-Path $copilotHome)
if (-not $hasClaude -and -not $hasCopilot) {
    Write-Host 'skip     AI agents (neither claude nor copilot is installed)'
    return
}

# rust-analyzer（rustup のコンポーネント。rustup の proxy は、入っていないと起動で落ちる）
$hasRustup = Test-Command rustup
if ($hasRustup -and -not $SkipPackages) {
    $r = Invoke-Tool rustup component add rust-analyzer
    if ($r.Code -ne 0) {
        Write-Warning "rustup component add rust-analyzer failed (exit $($r.Code)): $($r.Output -join ' ')"
    } elseif (($r.Output -join ' ') -match 'up to date') {
        Write-Host 'ok       rustup component rust-analyzer'
    } else {
        Write-Host 'install  rustup component rust-analyzer'
    }
}
$hasRustAnalyzer = (Test-Command rust-analyzer) -and ((Invoke-Tool rust-analyzer --version).Code -eq 0)

# スキル
$skills = @(Get-ChildItem (Join-Path $repo 'ai\skills') -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') })
$agentHomes = @()
if ($hasClaude) { $agentHomes += $claudeHome }
if ($hasCopilot) { $agentHomes += $copilotHome }
foreach ($agentHome in $agentHomes) {
    foreach ($s in $skills) {
        Set-Junction (Join-Path $agentHome "skills\$($s.Name)") $s.FullName $agentHome
    }
}

# Claude Code: 言語サーバは公式プラグインで（.lsp.json を自前で持たない）
if ($hasClaude -and (Test-Command claude)) {
    $wanted = @('clangd-lsp@claude-plugins-official')
    if ($hasRustup) { $wanted += 'rust-analyzer-lsp@claude-plugins-official' }
    if ($SkipPackages) {
        Write-Host "skip     Claude Code plugins (-SkipPackages): $($wanted -join ', ')"
    } else {
        $list = Invoke-Tool claude plugin list --json
        $installed = @()
        if ($list.Code -eq 0) {
            # ForEach-Object を挟むのは、5.1 の ConvertFrom-Json が配列を 1 個の値として流すため
            try { $installed = @(($list.Output -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }) } catch { }
        }
        $markets = (Invoke-Tool claude plugin marketplace list).Output -join "`n"
        if ($markets -notmatch 'claude-plugins-official') {
            $m = Invoke-Tool claude plugin marketplace add anthropics/claude-plugins-official
            if ($m.Code -ne 0) { Write-Warning "claude plugin marketplace add failed (exit $($m.Code)): $($m.Output -join ' ')" }
        }
        foreach ($id in $wanted) {
            $found = @($installed | Where-Object { $_.id -eq $id })
            if ($found.Count -gt 0) {
                if (@($found | Where-Object { $_.enabled }).Count -gt 0) {
                    Write-Host "ok       $id"
                } else {
                    # 自分で切ったものは戻さない
                    Write-Host "skip     $id (installed but disabled; to use it: claude plugin enable $id)"
                }
                continue
            }
            $r = Invoke-Tool claude plugin install $id --scope user
            if ($r.Code -eq 0) {
                Write-Host "install  $id"
            } else {
                Write-Warning "claude plugin install $id failed (exit $($r.Code)): $($r.Output -join ' ')"
            }
        }
    }
}

# Copilot CLI: ~/.copilot/lsp-config.json（.github/lsp.json はリポ側なので触らない）
if ($hasCopilot) {
    $servers = [ordered]@{
        clangd = [ordered]@{
            command        = 'clangd'
            args           = @('--background-index')
            fileExtensions = [ordered]@{ '.c' = 'c'; '.h' = 'cpp'; '.cpp' = 'cpp'; '.cc' = 'cpp'; '.cxx' = 'cpp'; '.hpp' = 'cpp'; '.hxx' = 'cpp' }
        }
    }
    if ($hasRustAnalyzer) {
        $servers['rust-analyzer'] = [ordered]@{ command = 'rust-analyzer'; fileExtensions = [ordered]@{ '.rs' = 'rust' } }
    }
    $cfgPath = Join-Path $copilotHome 'lsp-config.json'
    $raw = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw -Encoding UTF8 } else { '' }
    $cfg = $null
    if ($raw -and $raw.Trim()) {
        try { $cfg = $raw | ConvertFrom-Json } catch { $cfg = $null }
        if (-not $cfg) { Write-Warning "cannot read $cfgPath as JSON; add the servers by hand (see README.md)" }
    } else {
        $cfg = [pscustomobject]@{ lspServers = [pscustomobject]@{} }
    }
    if ($cfg) {
        if (-not $cfg.PSObject.Properties['lspServers']) {
            $cfg | Add-Member -NotePropertyName lspServers -NotePropertyValue ([pscustomobject]@{})
        }
        $added = @()
        foreach ($name in $servers.Keys) {
            if ($cfg.lspServers.PSObject.Properties[$name]) {
                Write-Host "ok       $cfgPath ($name)"
                continue
            }
            $cfg.lspServers | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]$servers[$name])
            $added += $name
        }
        if ($added.Count -gt 0) {
            if (Test-Path $cfgPath) {
                $backup = "$cfgPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
                Copy-Item $cfgPath $backup
                Write-Host "backup   $cfgPath -> $backup"
            }
            New-Item -ItemType Directory -Force $copilotHome | Out-Null
            $json = ($cfg | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
            [IO.File]::WriteAllText($cfgPath, $json + "`n", (New-Object Text.UTF8Encoding($false)))
            Write-Host "set      $cfgPath (+ $($added -join ', '))"
        }
    }
}

# clangd の実体（Mason）。無ければ、nvim の初回起動で入る
$masonBin = Join-Path $env:LOCALAPPDATA 'nvim-data\mason\bin'
if ((Test-Command clangd) -or (Test-Path (Join-Path $masonBin 'clangd.cmd')) -or (Test-Path (Join-Path $masonBin 'clangd.exe'))) {
    Write-Host 'ok       clangd'
} else {
    Write-Host 'note     clangd is not installed yet: start nvim once (Mason installs it), then open a new tab'
}
