# 今の Google 日本語入力の設定を、このリポジトリに取り込む（config1.db と keymap.txt）。
#   powershell -ExecutionPolicy Bypass -File .\google-ime\Export-GoogleIme.ps1
# 設定を GUI で変えた後にこれを走らせると、リポジトリ側が追いつく。
# 逆（リポジトリ → PC）は Restore-GoogleIme.ps1。

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# 設定の置き場所はバージョンで 2 系統ある。あるものを使う
$candidates = @(
    (Join-Path $env:USERPROFILE 'AppData\LocalLow\Google\Google Japanese Input'),
    (Join-Path $env:LOCALAPPDATA 'Google\Google Japanese Input')
)
$profileDir = $candidates | Where-Object { Test-Path (Join-Path $_ 'config1.db') } | Select-Object -First 1
if (-not $profileDir) {
    throw "config1.db が見つかりません。Google 日本語入力は入っていますか: $($candidates -join ' / ')"
}
$src = Join-Path $profileDir 'config1.db'
Write-Host "source   $src"

Copy-Item $src (Join-Path $here 'config1.db') -Force
Write-Host "export   config1.db"

# config1.db は protocol buffers。カスタムキーマップは field 42（bytes）に TSV がそのまま入っている。
# GUI の「キー設定の選択 → 編集 → エクスポート」で出るファイルと同じ形なので、インポートで戻せる。
$bytes = [IO.File]::ReadAllBytes($src)
$script:i = 0
function Read-Varint {
    $shift = 0
    $val = [long]0
    while ($true) {
        $b = $bytes[$script:i]; $script:i++
        $val = $val -bor ([long]($b -band 0x7f) -shl $shift)
        if (($b -band 0x80) -eq 0) { return $val }
        $shift += 7
    }
}

$keymap = $null
while ($script:i -lt $bytes.Length) {
    $key = Read-Varint
    $field = $key -shr 3
    $wire = $key -band 7
    switch ($wire) {
        0 { [void](Read-Varint) }
        1 { $script:i += 8 }
        5 { $script:i += 4 }
        2 {
            $len = Read-Varint
            if ($field -eq 42) { $keymap = [Text.Encoding]::UTF8.GetString($bytes, $script:i, $len) }
            $script:i += $len
        }
        default { throw "config1.db を読めません（wire type $wire）" }
    }
}

if ($keymap) {
    # 改行は LF に揃える（.gitattributes でこのファイルは LF 固定）
    $keymap = $keymap -replace "`r`n", "`n"
    [IO.File]::WriteAllText((Join-Path $here 'keymap.txt'), $keymap, (New-Object Text.UTF8Encoding($false)))
    Write-Host ("export   keymap.txt ({0} 行)" -f ($keymap.TrimEnd("`n").Split("`n").Count - 1))
} else {
    Write-Warning 'カスタムキーマップが入っていません（キー設定が「カスタム」以外）。keymap.txt は更新しません'
}

Write-Host 'done. git diff で中身を確かめてからコミットする。settings.md は手で直す（何が既定と違うかの説明）'
