# このリポジトリの Google 日本語入力の設定を、このPCに入れる（新しいPCのセットアップ用）。
#   powershell -ExecutionPolicy Bypass -File .\google-ime\Restore-GoogleIme.ps1
#   -Force : 確認を出さない
# 今の設定は config1.db.bak-<日時> に退避してから上書きするので、戻せる。
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here 'config1.db'
if (-not (Test-Path $src)) { throw "$src が無い" }

$candidates = @(
    (Join-Path $env:USERPROFILE 'AppData\LocalLow\Google\Google Japanese Input'),
    (Join-Path $env:LOCALAPPDATA 'Google\Google Japanese Input')
)
# 既にプロファイルがある方を優先。初回起動前でどちらも無ければ LocalLow 側に作る
$profileDir = ($candidates | Where-Object { Test-Path $_ } | Select-Object -First 1)
if (-not $profileDir) { $profileDir = $candidates[0]; New-Item -ItemType Directory -Force $profileDir | Out-Null }
$dst = Join-Path $profileDir 'config1.db'

if (-not $Force) {
    Write-Host "上書き先: $dst"
    Write-Host '今の設定は .bak-<日時> に退避してから入れ替えます。'
    if ((Read-Host '進めますか [y/N]') -notin 'y', 'Y') { Write-Host 'やめました'; return }
}

if (Test-Path $dst) {
    $backup = "$dst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $dst $backup
    Write-Host "backup   $backup"
}

# 変換エンジンは設定を起動時に読み、終了時に書き戻す。動いているままコピーしても
# 上書きで消える（＝効かない）ので、先に止める。次の入力で自動的に起動し直す。
foreach ($name in 'GoogleIMEJaConverter', 'GoogleIMEJaRenderer') {
    $p = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($p) { $p | Stop-Process -Force; Write-Host "stop     $name" }
}
Start-Sleep -Milliseconds 500

Copy-Item $src $dst -Force
Write-Host "restore  $dst"
Write-Host 'done. キー設定が「カスタム」になり、F13=IME OFF / F14=IME ON が入ります（詳細は settings.md）。'
Write-Host '反映されない時は一度サインアウトして入り直す。'
