# Keychron Launcher で書き出したキーマップを、このリポジトリに取り込む。
#   powershell -ExecutionPolicy Bypass -File .\keychron\Export-KeychronKeymap.ps1
#   -Path <file> : 取り込むファイルを指定する（既定: ダウンロードフォルダの最新の Keymap-Keychron*.json）
# Launcher（WebHID のブラウザアプリ）は外から叩けないので、書き出しは手作業:
#   launcher.keychron.com を開く → 右上のメニュー → キーマップを保存（Save/Export）
# その後このスクリプトを流すとリポジトリ側が追いつく。逆（リポ → キーボード）も Launcher の読み込みで手作業。
param([string]$Path)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $here 'keymap\B1-Pro-ANSI.json'

# 0x3434071A = VID 0x3434（Keychron） / PID 0x071A（B1 Pro ANSI）
$expectedId = 0x3434071A

if (-not $Path) {
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    $src = Get-ChildItem -Path $downloads -Filter 'Keymap-Keychron*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $src) { throw "$downloads に Keymap-Keychron*.json が見つかりません。Launcher で書き出してから流してください（-Path で指定もできます）" }
    $Path = $src.FullName
}
if (-not (Test-Path $Path)) { throw "$Path が無い" }
Write-Host ("source   {0}  ({1:yyyy-MM-dd HH:mm})" -f $Path, (Get-Item $Path).LastWriteTime)

$json = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $json.id -or $null -eq $json.keymap) { throw 'Launcher の書き出しファイルに見えません（id / keymap が無い）' }
if ($json.id -ne $expectedId) {
    Write-Warning ("機種が違います: id=0x{0:X8}（想定は 0x{1:X8} = B1 Pro ANSI）。別のキーボードなら settings.md とファイル名を分けてください" -f $json.id, $expectedId)
    if ((Read-Host 'それでも上書きしますか [y/N]') -notin 'y', 'Y') { Write-Host 'やめました'; return }
}

$layers = $json.keymap.Count
$keys   = $json.keymap[0].Count
Write-Host ("keymap   id=0x{0:X8}  {1} レイヤー × {2} キー" -f $json.id, $layers, $keys)

# 改行は LF（.gitattributes で *.json は LF 固定）
$text = (Get-Content -Path $Path -Raw -Encoding UTF8) -replace "`r`n", "`n"
[IO.File]::WriteAllText($dest, $text, (New-Object Text.UTF8Encoding($false)))
Write-Host "export   keymap\B1-Pro-ANSI.json"
Write-Host 'done. git diff で中身を確かめてからコミットする。settings.md は手で直す（何を変えたかの説明）'
