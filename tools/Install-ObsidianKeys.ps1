<#
.SYNOPSIS
    Obsidian のキーを LazyVim に揃える: Vim モード・Ctrl+h/j/k/l で分割を移る・Shift+h/l で前後のタブ・
    INSERT 以外では IME を OFF。

.DESCRIPTION
    正本はこのリポの obsidian\hotkeys.json・obsidian\vimrc・obsidian\plugins\dotfiles-ime-off。
    vault には次の 5 つをする。何度流してもよい。

    1. hotkeys.json を vault の .obsidian\hotkeys.json に混ぜる。まだキーを付けていないコマンドだけ足し、
       Obsidian で別のキーを付けたコマンドは触らずに警告する（設定 → ホットキーで既定に戻して流し直すと入る）。
       置換・リンクの挿入・チェックボックスの切り替えは、Ctrl+H/K/L を空けるため Ctrl+Shift+H/K/L に移す。
    2. vimrc を vault 直下の .obsidian.vimrc（Vimrc Support が読む名前）に写す。写しは上書きする。
       このリポのものでない同じ名前のファイル（dotfiles-windows/obsidian/vimrc と書いていない）は触らない。
    3. .obsidian\app.json の vimMode を true にする。スマホは Vim モードを app.json から読まないので乗らない。
       開いている Obsidian はこの書き換えを読み直さないことがあるので、CLI の eval で同じ設定を入れる。
    4. コミュニティプラグイン Vimrc Support を入れて有効にする。Obsidian でその vault が開いている時だけ、
       その CLI（plugin:install）で行う。閉じている時・-SkipPackages の時・インストーラが 1.11.7 より古い時は
       手順を出すだけ。
    5. INSERT 以外で IME を切るプラグイン dotfiles-ime-off を、それが呼ぶ tools\bin\ime.exe と一緒に
       .obsidian\plugins\ に写して有効にする。開いている Obsidian では eval で読み込む（再起動は要らない）。
       ストアから取らないので -SkipPackages でも行う。

    開いている Obsidian は hotkeys.json の書き換えを読み直すので、1 はすぐ効く。vimrc は Vimrc Support が
    ウィンドウごとに 1 回だけ読むので、写しを入れ替えた時は Obsidian を開き直す。

.PARAMETER Vault
    vault の場所。既定は ~/.dotfiles.json の vault。

.PARAMETER SkipPackages
    プラグインを取りに行かない（install.ps1 の -SkipPackages）。
#>
[CmdletBinding()]
param([string]$Vault, [switch]$SkipPackages)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$pluginId = 'obsidian-vimrc-support'
$vimrcMarker = 'dotfiles-windows/obsidian/vimrc'
$utf8 = New-Object Text.UTF8Encoding($false)

if (-not $Vault) {
    $cfgPath = Join-Path $HOME '.dotfiles.json'
    if (Test-Path $cfgPath) {
        try { $Vault = (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json).vault } catch { }
    }
}
if (-not $Vault -or -not (Test-Path (Join-Path $Vault '.obsidian') -PathType Container)) {
    Write-Host 'skip     Obsidian keys (no vault in ~/.dotfiles.json)'
    return
}
$vaultPath = (Resolve-Path $Vault).Path.TrimEnd('\')
$configDir = Join-Path $vaultPath '.obsidian'

# Obsidian と同じ字面（JSON.stringify(v, null, 2)）で書く。hotkeys.json は vault の git が追うので、
# Obsidian が書き直すたびに全部の行が変わって見えないようにする。
function ConvertTo-ObsidianJson($value, [string]$indent = '') {
    if ($null -eq $value) { return 'null' }
    if ($value -is [bool]) { if ($value) { return 'true' } else { return 'false' } }
    if ($value -is [string]) {
        $escaped = [regex]::Replace($value, '["\\\x00-\x1f]', {
            param($m)
            # 文字コードで分ける（7 の文字列の比較は制御文字を無視するので、"`b" が \u0001 にも当たる）
            switch ([int][char]$m.Value) {
                0x22 { '\"' } 0x5c { '\\' } 0x0a { '\n' } 0x0d { '\r' } 0x09 { '\t' } 0x08 { '\b' } 0x0c { '\f' }
                default { '\u{0:x4}' -f $_ }
            }
        })
        return '"' + $escaped + '"'
    }
    if ($value -is [ValueType]) { return [Convert]::ToString($value, [Globalization.CultureInfo]::InvariantCulture) }
    $inner = $indent + '  '
    $parts = New-Object Collections.Generic.List[string]
    if ($value -is [Management.Automation.PSCustomObject]) {
        foreach ($p in $value.PSObject.Properties) { $parts.Add((ConvertTo-ObsidianJson $p.Name) + ': ' + (ConvertTo-ObsidianJson $p.Value $inner)) }
        $open, $close = '{', '}'
    } else {
        foreach ($item in $value) { $parts.Add((ConvertTo-ObsidianJson $item $inner)) }
        $open, $close = '[', ']'
    }
    if ($parts.Count -eq 0) { return $open + $close }
    return $open + "`n" + $inner + ($parts -join (",`n" + $inner)) + "`n" + $indent + $close
}

# 無いファイルは空のオブジェクト、読めない JSON は $null（触らずに手で直してもらう）
function Read-ConfigJson($path) {
    if (-not (Test-Path $path)) { return [pscustomobject]@{} }
    $raw = [IO.File]::ReadAllText($path)
    if (-not $raw.Trim()) { return [pscustomobject]@{} }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

function Write-ConfigJson($path, $obj) {
    [IO.File]::WriteAllText($path, (ConvertTo-ObsidianJson $obj), $utf8)
}

# 同じ押し方かを比べる形（修飾キーの順と英字の大小は Obsidian も区別しない）
function Get-HotkeySignature($hotkey) {
    $key = if ($hotkey.key) { "$($hotkey.key)" } else { "$($hotkey.code)" -replace '^Key', '' }
    return ((@($hotkey.modifiers) | Sort-Object) -join '+') + '+' + $key.ToUpperInvariant()
}

# 1. ホットキー
$hotkeysPath = Join-Path $configDir 'hotkeys.json'
$ours = [IO.File]::ReadAllText((Join-Path $repo 'obsidian\hotkeys.json')) | ConvertFrom-Json
$current = Read-ConfigJson $hotkeysPath
if ($null -eq $current) {
    Write-Warning "cannot read $hotkeysPath as JSON; left as it is (fix it, then run again)"
} else {
    $added = @()
    foreach ($p in $ours.PSObject.Properties) {
        $theirs = $current.PSObject.Properties[$p.Name]
        if (-not $theirs) {
            $current | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
            $added += $p.Name
        } elseif (-not [string]::Equals((ConvertTo-ObsidianJson $theirs.Value), (ConvertTo-ObsidianJson $p.Value), [StringComparison]::Ordinal)) {
            Write-Warning "$hotkeysPath has its own hotkey for $($p.Name); left as it is (to take this repo's, restore the default in Obsidian's Settings > Hotkeys and run again)"
        }
    }
    # 同じキーを別のコマンドにも付けていると、どちらが動くかは Obsidian 次第になる
    foreach ($p in $ours.PSObject.Properties) {
        foreach ($hk in @($p.Value)) {
            $sig = Get-HotkeySignature $hk
            foreach ($other in $current.PSObject.Properties) {
                if ($ours.PSObject.Properties[$other.Name]) { continue }
                if (@($other.Value | Where-Object { $_ -and (Get-HotkeySignature $_) -eq $sig }).Count) {
                    Write-Warning "$sig is also on $($other.Name) in $hotkeysPath; remove one of them in Obsidian's Settings > Hotkeys"
                }
            }
        }
    }
    if ($added) {
        Write-ConfigJson $hotkeysPath $current
        Write-Host "set      $hotkeysPath ($($added -join ', '))"
    } else {
        Write-Host "ok       $hotkeysPath"
    }
}

# 2. vimrc（プラグインは \n で行に分けるので LF で書く）
$vimrcPath = Join-Path $vaultPath '.obsidian.vimrc'
$vimrc = [IO.File]::ReadAllText((Join-Path $repo 'obsidian\vimrc')) -replace "`r`n", "`n"
$vimrcChanged = $false
if (Test-Path $vimrcPath) {
    $now = [IO.File]::ReadAllText($vimrcPath)
    if ([string]::Equals($now, $vimrc, [StringComparison]::Ordinal)) {
        Write-Host "ok       $vimrcPath"
    } elseif ($now.Contains($vimrcMarker)) {
        [IO.File]::WriteAllText($vimrcPath, $vimrc, $utf8)
        Write-Host "updated  $vimrcPath"
        $vimrcChanged = $true
    } else {
        Write-Warning "$vimrcPath is not from this repo; left as it is (Shift+H/L need the lines in obsidian\vimrc)"
    }
} else {
    [IO.File]::WriteAllText($vimrcPath, $vimrc, $utf8)
    Write-Host "copied   $vimrcPath"
    $vimrcChanged = $true
}

# 開いている Obsidian に CLI で頼む。その vault が開いている時だけ使う（閉じていると起動してしまう）。
# CLI は失敗しても終了コード 0 を返すので、結果は別の問い合わせで確かめる。
$obsidian = (Get-Command obsidian -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$vaultOpen = $false
$registry = Join-Path $env:APPDATA 'obsidian\obsidian.json'
if ($obsidian -and (Get-Process Obsidian -ErrorAction SilentlyContinue) -and (Test-Path $registry)) {
    try {
        $known = (Get-Content $registry -Raw -Encoding UTF8 | ConvertFrom-Json).vaults
        $vaultOpen = [bool]@($known.PSObject.Properties.Value | Where-Object { $_.open -and "$($_.path)".TrimEnd('\') -eq $vaultPath }).Count
    } catch { }
}
function Invoke-ObsidianCli {
    $ErrorActionPreference = 'Continue'
    @(& $obsidian "vault=$(Split-Path -Leaf $vaultPath)" @args 2>&1 | ForEach-Object { "$_" } |
        Where-Object { $_.Trim() -and $_ -notmatch 'Loading updated app package|installer is out of date' })
}
function Get-EnabledPlugins {
    if ($vaultOpen) { return @(Invoke-ObsidianCli 'plugins:enabled' | ForEach-Object { $_.Trim() }) }
    $list = Read-ConfigJson (Join-Path $configDir 'community-plugins.json')
    # ForEach-Object を挟むのは、5.1 の ConvertFrom-Json が配列を 1 個の値として流すため
    return @($list | ForEach-Object { $_ } | Where-Object { $_ -is [string] })
}
function Test-EvalTrue($lines) {
    foreach ($line in @($lines)) { if ("$line".Trim() -eq '=> true') { return $true } }
    return $false
}

# 3. Vim モード。開いている Obsidian は app.json の書き換えを読み直さないことがある（hotkeys.json は
#    読み直す）ので、設定画面のトグルと同じ setConfig を eval で呼び、効いたかを別の eval で確かめる。
#    JS に " を入れないのは 5.1 が引数で渡し損ねるため。eval は待つ Promise の結果を返さないので待たない。
$appPath = Join-Path $configDir 'app.json'
$app = Read-ConfigJson $appPath
if ($null -eq $app) {
    Write-Warning "cannot read $appPath as JSON; turn on Vim key bindings in Obsidian's Settings > Editor"
} else {
    if ($app.PSObject.Properties['vimMode'] -and $app.vimMode -eq $true) {
        Write-Host "ok       $appPath (vimMode)"
    } else {
        if ($app.PSObject.Properties['vimMode']) { $app.vimMode = $true }
        else { $app | Add-Member -NotePropertyName vimMode -NotePropertyValue $true }
        Write-ConfigJson $appPath $app
        Write-Host "set      $appPath (vimMode = true)"
    }
    $isOn = "code=app.vault.getConfig('vimMode')"
    if ($vaultOpen -and -not (Test-EvalTrue (Invoke-ObsidianCli 'eval' $isOn))) {
        $out = Invoke-ObsidianCli 'eval' "code=app.vault.setConfig('vimMode',true)"
        if (Test-EvalTrue (Invoke-ObsidianCli 'eval' $isOn)) { Write-Host 'set      Vim mode in the open Obsidian' }
        else { Write-Host "note     restart Obsidian to turn Vim mode on (the CLI said: $($out -join ' '))" }
    }
}

# 4. Vimrc Support（CLI の plugin:install）。1.11.7 より古いインストーラの CLI は、: を含む引数の後ろに
#    別の引数があるとすぐ終わる（1.9.14 で実測）ので、その時は試さずに手順を出す。
$installer = $null
if ($vaultOpen -and "$(Invoke-ObsidianCli 'version')" -match 'installer (\d+(\.\d+)+)') { $installer = [version]$Matches[1] }
$installed = Test-Path (Join-Path $configDir "plugins\$pluginId\manifest.json")
$enabledBefore = $installed -and ((Get-EnabledPlugins) -contains $pluginId)
if ($enabledBefore) {
    Write-Host "ok       plugin $pluginId (enabled)"
    if ($vimrcChanged -and $vaultOpen) { Write-Host 'note     restart Obsidian to load the new .obsidian.vimrc (Vimrc Support reads it once per window)' }
} elseif (-not $installed -and $SkipPackages) {
    Write-Host "skip     plugin $pluginId (-SkipPackages). Run again without it, or install Vimrc Support from Obsidian's Community plugins"
} elseif (-not $vaultOpen) {
    Write-Host "note     open the vault in Obsidian and run again to install and enable Vimrc Support ($pluginId), or do it in Obsidian's Community plugins"
} elseif ($installer -and $installer -lt [version]'1.11.7') {
    $what = if ($installed) { 'turn on' } else { 'install and turn on' }
    Write-Host "note     $what Vimrc Support ($pluginId) in Obsidian's Community plugins: the CLI of this Obsidian installer ($installer) cannot do it (or update the installer from https://obsidian.md/download and run again)"
} else {
    $out = if ($installed) { Invoke-ObsidianCli 'plugin:enable' "id=$pluginId" 'filter=community' } else { Invoke-ObsidianCli 'plugin:install' "id=$pluginId" 'enable' }
    if ((Get-EnabledPlugins) -contains $pluginId) {
        Write-Host "enabled  plugin $pluginId (Shift+H/L work after you switch tabs once)"
    } else {
        Write-Warning "could not install or enable $pluginId through the Obsidian CLI: $($out -join ' '). Install Vimrc Support from Obsidian's Community plugins"
    }
}

# 5. INSERT 以外で IME を切るプラグイン（このリポの obsidian\plugins\dotfiles-ime-off）。main.js と
#    manifest.json に、それが呼ぶ tools\bin\ime.exe（install.ps1 の 7 が作る）を添えて写し、有効にする。
#    開いている Obsidian では、写しを入れ替えた時にプラグインを読み直す。plugin:enable を使わず
#    Obsidian の関数を eval で呼ぶのは、古いインストーラの CLI では通らないため（4 と同じ）。
$imePluginId = 'dotfiles-ime-off'
$imeExe = Join-Path $repo 'tools\bin\ime.exe'
$imePluginDir = Join-Path $configDir "plugins\$imePluginId"
if (-not (Test-Path $imeExe)) {
    Write-Warning "$imeExe is missing (install.ps1 builds it in step 7); the IME stays on in Obsidian's normal mode"
} else {
    New-Item -ItemType Directory -Force $imePluginDir | Out-Null
    $imeChanged = $false
    foreach ($src in @(Get-ChildItem (Join-Path $repo "obsidian\plugins\$imePluginId") -File) + @(Get-Item $imeExe)) {
        $dest = Join-Path $imePluginDir $src.Name
        # 中身で比べる（Get-FileHash は 7 から起こした 5.1 では見つからないことがあるので使わない）
        if ((Test-Path $dest) -and [string]::Equals([Convert]::ToBase64String([IO.File]::ReadAllBytes($dest)),
                [Convert]::ToBase64String([IO.File]::ReadAllBytes($src.FullName)), [StringComparison]::Ordinal)) { continue }
        Copy-Item $src.FullName $dest -Force
        $imeChanged = $true
    }
    if ($imeChanged) { Write-Host "copied   $imePluginDir" } else { Write-Host "ok       $imePluginDir" }
    $imeEnabled = (Get-EnabledPlugins) -contains $imePluginId
    if ($vaultOpen) {
        # 動いているか＝ime.exe を見つけて待ち受けを始めたか（無いと hooked を作らない）
        $isRunning = "code=app.plugins.plugins['$imePluginId']?.hooked instanceof Map"
        # eval の結果は Promise なので何も出ないことが多い。効いたかは $isRunning で確かめる
        $load = $null
        if (-not $imeEnabled) {
            $load = "code=app.plugins.loadManifests().then(()=>app.plugins.enablePluginAndSave('$imePluginId'))"
        } elseif ($imeChanged -or -not (Test-EvalTrue (Invoke-ObsidianCli 'eval' $isRunning))) {
            $load = "code=app.plugins.disablePlugin('$imePluginId').then(()=>app.plugins.loadManifests()).then(()=>app.plugins.enablePlugin('$imePluginId'))"
        }
        if (-not $load) {
            Write-Host "ok       plugin $imePluginId (enabled)"
        } else {
            $out = Invoke-ObsidianCli 'eval' $load
            if (Test-EvalTrue (Invoke-ObsidianCli 'eval' $isRunning)) { Write-Host "enabled  plugin $imePluginId in the open Obsidian (the IME goes off when you leave Insert mode)" }
            else { Write-Warning "could not load $imePluginId in the open Obsidian: $($out -join ' '). Turn it on in Obsidian's Settings > Community plugins" }
        }
    } elseif ($imeEnabled) {
        Write-Host "ok       plugin $imePluginId (enabled)"
    } else {
        # 閉じている時は有効なプラグインの一覧に足す（次に開いた時に読まれる）
        $listPath = Join-Path $configDir 'community-plugins.json'
        $list = Read-ConfigJson $listPath
        if ($null -eq $list) {
            Write-Warning "cannot read $listPath as JSON; turn on $imePluginId in Obsidian's Settings > Community plugins"
        } else {
            $ids = @($list | ForEach-Object { $_ } | Where-Object { $_ -is [string] }) + $imePluginId
            Write-ConfigJson $listPath $ids
            Write-Host "set      $listPath ($imePluginId; loaded when Obsidian opens the vault)"
        }
    }
}
