# 日本語版 Windows に US（ANSI）配列のキーボードを繋いだとき、物理配列を US 101 として
# 解釈させる。これをやらないと記号の位置が JIS 配列として読まれて全部ずれる。
#   管理者の PowerShell で:
#   powershell -ExecutionPolicy Bypass -File .\keychron\Set-UsPhysicalLayout.ps1
#   -Show   : 今の値を見るだけ（管理者権限は不要）
#   -Revert : 日本語版の既定（JIS 106）に戻す
#   -Force  : 確認を出さない
# 変更前の値は %LOCALAPPDATA%\dotfiles-windows\ に .reg で退避する。反映には再起動が要る。
# 何が決まる設定なのかは settings.md。
param([switch]$Show, [switch]$Revert, [switch]$Force)

$ErrorActionPreference = 'Stop'

$keyPs  = 'HKLM:\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters'
$keyReg = 'HKLM\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters'

# 名前 / 型 / US のときの値 / 日本語版の既定
$values = @(
    @{ Name = 'LayerDriver JPN';            Type = 'String'; Us = 'kbd101.dll';  Jis = 'kbd106.dll' }
    @{ Name = 'OverrideKeyboardIdentifier'; Type = 'String'; Us = 'PCAT_101KEY'; Jis = 'PCAT_106KEY' }
    @{ Name = 'OverrideKeyboardSubtype';    Type = 'DWord';  Us = 0;             Jis = 2 }
    @{ Name = 'OverrideKeyboardType';       Type = 'DWord';  Us = 7;             Jis = 7 }
)

function Get-Current {
    $cur = @{}
    foreach ($v in $values) {
        $cur[$v.Name] = (Get-ItemProperty -Path $keyPs -Name $v.Name -ErrorAction SilentlyContinue).$($v.Name)
    }
    return $cur
}

function Show-Current {
    $cur = Get-Current
    $values | ForEach-Object {
        [pscustomobject]@{
            '設定'    = $_.Name
            '現在'    = if ($null -eq $cur[$_.Name]) { '(無し)' } else { $cur[$_.Name] }
            'US'      = $_.Us
            '日本語'  = $_.Jis
        }
    } | Format-Table -AutoSize | Out-Host  # 呼び出し側が戻り値を受けても表は画面に出す

    $isUs  = -not ($values | Where-Object { $cur[$_.Name] -ne $_.Us })
    $isJis = -not ($values | Where-Object { $cur[$_.Name] -ne $_.Jis })
    if     ($isUs)  { Write-Host '判定: US 101 配列として扱う設定になっています' -ForegroundColor Green }
    elseif ($isJis) { Write-Host '判定: 日本語版の既定（JIS 106）です' -ForegroundColor Yellow }
    else            { Write-Host '判定: どちらでもない中間の状態です' -ForegroundColor Yellow }

    $preload = (Get-ItemProperty -Path 'HKCU:\Keyboard Layout\Preload' -ErrorAction SilentlyContinue).'1'
    Write-Host "入力言語 (HKCU\Keyboard Layout\Preload\1): $preload  # 00000411 = 日本語（この設定では変えない）"

    $map = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -ErrorAction SilentlyContinue).'Scancode Map'
    Write-Host ("Scancode Map: {0}  # このリポでは使わない（キーの入れ替えはキーボード側）" -f $(if ($map) { '有り' } else { '無し' }))
    return $cur
}

$cur = Show-Current
if ($Show) { return }

$target = if ($Revert) { 'Jis' } else { 'Us' }
$label  = if ($Revert) { '日本語版の既定（JIS 106）' } else { 'US 101 配列' }

$changes = $values | Where-Object { $cur[$_.Name] -ne $_.$target }
if (-not $changes) { Write-Host "`n既に $label です。変更はありません" -ForegroundColor Green; return }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'HKLM を書くので管理者権限が要ります。PowerShell を「管理者として実行」で開き直してください（読むだけなら -Show）' }

Write-Host "`n$label にします。変える値:"
$changes | ForEach-Object { Write-Host ("  {0}: {1} -> {2}" -f $_.Name, $(if ($null -eq $cur[$_.Name]) { '(無し)' } else { $cur[$_.Name] }), $_.$target) }
Write-Host '全ユーザー共通の設定です。反映には再起動が要ります。'

if (-not $Force) {
    if ((Read-Host '進めますか [y/N]') -notin 'y', 'Y') { Write-Host 'やめました'; return }
}

$backupDir = Join-Path $env:LOCALAPPDATA 'dotfiles-windows'
New-Item -ItemType Directory -Force $backupDir | Out-Null
$backup = Join-Path $backupDir ("i8042prt-Parameters-{0}.reg" -f (Get-Date -Format yyyyMMdd-HHmmss))
& reg.exe export $keyReg $backup /y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "レジストリの退避に失敗しました: $backup" }
Write-Host "backup   $backup"

foreach ($v in $changes) {
    New-ItemProperty -Path $keyPs -Name $v.Name -Value $v.$target -PropertyType $v.Type -Force | Out-Null
    Write-Host ("set      {0} = {1}" -f $v.Name, $v.$target)
}

Write-Host "`ndone. 再起動すると効きます（元に戻すなら -Revert、または退避した .reg をダブルクリック）"
