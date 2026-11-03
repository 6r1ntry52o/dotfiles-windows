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
      - vault（~/.dotfiles.json の vault がある PC）: どのリポで起動しても vault を読めるようにし、
        note/ を守るフック（ai\hooks\note-guard.ps1）をつなぐ
          Claude Code   ~/.claude/settings.json の permissions.additionalDirectories に vault、
                        hooks.PreToolUse に note-guard、fileSuggestion に tools\bin\file-suggest.exe
                        （@ の候補に note/ のノートも出す。ここで csc.exe がビルドする）。
                        書き換える前に .bak-日時 に退避する
          Copilot CLI   ~/.copilot/hooks/note-guard.json。vault を読む許可は設定で与えられないので、
                        powershell/profile.ps1 の copilot 関数が起動のたびに --add-dir で渡す

    clangd は Neovim の Mason が入れたものを使う（nvim を一度起動すると入る）。エディタと同じ版で、
    索引（.cache/clangd）も共有になる。エージェントからは、powershell/profile.ps1 が PATH の先頭に
    足す Mason の bin で見える（nvim の外のタブから起動しても同じ）。

    外から取り込む（プラグインと rust-analyzer を取得する）だけで、この PC の情報を外へ送る仕組みは
    足さない。何度流してもよい。

.PARAMETER SkipPackages
    取得を伴うもの（プラグイン・rust-analyzer）を飛ばし、スキルと設定だけ置く。

.PARAMETER Vault
    vault の場所。既定は ~/.dotfiles.json の vault（試す時に別の場所を渡す）。

.EXAMPLE
    pwsh -File tools\Install-AiAgents.ps1
    入れたあと、新しいタブで claude か copilot を起動する（PATH が変わるため）
#>
[CmdletBinding()]
param([switch]$SkipPackages, [string]$Vault)

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

# vault: どのリポから起動しても読めるようにし、note/ を守るフックをつなぐ
if (-not $Vault) {
    $dotfilesJson = Join-Path $HOME '.dotfiles.json'
    if (Test-Path $dotfilesJson) {
        try { $Vault = (Get-Content $dotfilesJson -Raw -Encoding UTF8 | ConvertFrom-Json).vault } catch { }
    }
}
$guard = (Join-Path $repo 'ai\hooks\note-guard.ps1') -replace '\\', '/'
if (-not $Vault -or -not (Test-Path $Vault -PathType Container)) {
    Write-Host 'skip     vault access and note-guard (no vault in ~/.dotfiles.json)'
} else {
    $vaultPath = (Resolve-Path $Vault).Path.TrimEnd('\')

    # 読めない JSON は触らずに $null を返す（手で直してもらう）
    function Read-JsonFile($path) {
        if (-not (Test-Path $path)) { return [pscustomobject]@{} }
        $raw = Get-Content $path -Raw -Encoding UTF8
        if (-not $raw -or -not $raw.Trim()) { return [pscustomobject]@{} }
        try { return ($raw | ConvertFrom-Json) } catch { return $null }
    }
    function Write-JsonFile($path, $obj) {
        if (Test-Path $path) {
            $backup = "$path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item $path $backup
            Write-Host "backup   $path -> $backup"
        }
        New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
        $json = ($obj | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
        [IO.File]::WriteAllText($path, $json + "`n", (New-Object Text.UTF8Encoding($false)))
    }
    function Set-Property($obj, $name, $value) {
        if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
        else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
    }

    # Claude Code: additionalDirectories は読むだけ許可なしで通す（書くのは権限モードのまま）。
    # 書いたものだけ置き換えられるよう、note-guard.ps1 を呼ぶ項目を自分のものとみなす。
    if ($hasClaude) {
        $cfgPath = Join-Path $claudeHome 'settings.json'
        $cfg = Read-JsonFile $cfgPath
        if (-not $cfg) {
            Write-Warning "cannot read $cfgPath as JSON; add the vault and note-guard by hand (see README.md)"
        } else {
            $before = $cfg | ConvertTo-Json -Depth 20 -Compress
            if (-not $cfg.PSObject.Properties['permissions']) { Set-Property $cfg 'permissions' ([pscustomobject]@{}) }
            $dirs = @($cfg.permissions.additionalDirectories | Where-Object { $_ })
            if (-not ($dirs | Where-Object { $_.TrimEnd('\', '/').Replace('/', '\') -eq $vaultPath })) { $dirs += $vaultPath }
            Set-Property $cfg.permissions 'additionalDirectories' $dirs

            if (-not $cfg.PSObject.Properties['hooks']) { Set-Property $cfg 'hooks' ([pscustomobject]@{}) }
            $mine = { param($entry) @($entry.hooks | Where-Object { "$($_.command) $($_.args -join ' ')" -match 'note-guard\.ps1' }).Count -gt 0 }
            $pre = @($cfg.hooks.PreToolUse | Where-Object { $_ -and -not (& $mine $_) })
            $hookArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $guard, '-Format', 'claude')
            $handler = { param($if) $h = [ordered]@{ type = 'command' }; if ($if) { $h['if'] = $if }; $h['command'] = 'powershell.exe'; $h['args'] = $hookArgs; $h['timeout'] = 15; [pscustomobject]$h }
            # シェルは note を含むコマンドの時だけ呼ぶ（毎回 PowerShell を起こすと遅い）
            $pre += [pscustomobject]@{ matcher = 'Edit|Write|MultiEdit|NotebookEdit'; hooks = @(& $handler $null) }
            $pre += [pscustomobject]@{ matcher = 'Bash'; hooks = @(& $handler 'Bash(*note*)') }
            $pre += [pscustomobject]@{ matcher = 'PowerShell'; hooks = @(& $handler 'PowerShell(*note*)') }
            Set-Property $cfg.hooks 'PreToolUse' $pre

            # @ の候補に note/ のノートも出す（組み込みの候補は起動した場所の中だけ）。
            # file-suggest.exe は組み込みの代わりにプロジェクトのファイルも出す。自分で決めた
            # fileSuggestion があれば触らない。
            $fsSrc = Join-Path $repo 'tools\file-suggest\FileSuggest.cs'
            $fsOut = Join-Path $repo 'tools\bin\file-suggest.exe'
            $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
            if ((Test-Path $csc) -and -not ((Test-Path $fsOut) -and ((Get-Item $fsOut).LastWriteTime -ge (Get-Item $fsSrc).LastWriteTime))) {
                New-Item -ItemType Directory -Force (Split-Path -Parent $fsOut) | Out-Null
                $r = Invoke-Tool $csc /nologo /optimize "/out:$fsOut" $fsSrc
                if ($r.Code -ne 0) { Write-Warning "csc failed for file-suggest.exe (exit $($r.Code)): $($r.Output -join ' ')" }
                else { Write-Host "built    $fsOut" }
            }
            $fsCommand = $fsOut -replace '\\', '/'
            if ($fsCommand -match ' ') { $fsCommand = '"' + $fsCommand + '"' }
            $fs = $cfg.PSObject.Properties['fileSuggestion']
            if (-not (Test-Path $fsOut)) {
                Write-Warning "file-suggest.exe is missing (csc.exe not found?): @ will not list the notes"
            } elseif ($fs -and "$($fs.Value.command)" -notmatch 'file-suggest\.exe') {
                Write-Host "skip     fileSuggestion (your own is set: $($fs.Value.command))"
            } else {
                Set-Property $cfg 'fileSuggestion' ([pscustomobject][ordered]@{ type = 'command'; command = $fsCommand })
            }

            if (($cfg | ConvertTo-Json -Depth 20 -Compress) -eq $before) {
                Write-Host "ok       $cfgPath (vault, note-guard, fileSuggestion)"
            } else {
                Write-JsonFile $cfgPath $cfg
                Write-Host "set      $cfgPath (additionalDirectories += $vaultPath, PreToolUse note-guard, fileSuggestion)"
            }
        }
    }

    # Copilot CLI: ユーザーのフックは ~/.copilot/hooks/*.json。このファイルは丸ごと install.ps1 のもの。
    # PreToolUse（Claude 互換の形）で受けると、PowerShell の呼び出しも Bash の名前で届く。
    # clone を移して note-guard.ps1 が無くなっても、Copilot の操作を止めない（フックの失敗は拒否になるため）。
    if ($hasCopilot) {
        $hookPath = Join-Path $copilotHome 'hooks\note-guard.json'
        $quoted = $guard -replace "'", "''"
        $body = [ordered]@{
            version = 1
            hooks   = [ordered]@{
                PreToolUse = @([ordered]@{
                        type       = 'command'
                        matcher    = 'Bash|Edit|Write'
                        powershell = "if (Test-Path -LiteralPath '$quoted') { & '$quoted' -Format copilot }"
                        timeoutSec = 15
                    })
            }
        }
        $json = (($body | ConvertTo-Json -Depth 10) -replace "`r`n", "`n") + "`n"
        # 中身で比べる（5.1 と 7 で ConvertTo-Json の字面が違う）
        $current = $null
        if (Test-Path $hookPath) { try { $current = Get-Content $hookPath -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress } catch { } }
        if ($current -eq ($body | ConvertTo-Json -Depth 10 -Compress)) {
            Write-Host "ok       $hookPath"
        } else {
            New-Item -ItemType Directory -Force (Split-Path -Parent $hookPath) | Out-Null
            [IO.File]::WriteAllText($hookPath, $json, (New-Object Text.UTF8Encoding($false)))
            Write-Host "set      $hookPath"
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
