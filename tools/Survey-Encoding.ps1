<#
.SYNOPSIS
    ファイルの文字コードを棚卸しする（読み取り専用）。

.DESCRIPTION
    指定したフォルダ以下のテキストファイルを1件ずつバイト列から判定し、集計を出す。
    ファイルは一切変更しない。書き込むのは -DetailOut を指定した時の明細 CSV だけ。

    判定の順番（Neovim の fileencodings と同じ考え方）:
      1. BOM があればそれ（UTF-8 BOM / UTF-16LE / UTF-16BE）
      2. BOM なしで UTF-8 として厳密に読めれば UTF-8（ASCII のみなら Ascii）
      3. CP932（Shift_JIS）として読めれば Cp932
      4. どれでもなければ Undecidable（バイナリか、壊れたファイル）

    出力は2段に分かれている:
      集計  … 数字だけ。パスも中身も含まないので、そのまま相談に使える
      明細  … パスを含む。-DetailOut を付けた時だけローカルに書く（持ち出さない）

.PARAMETER Path
    調べるフォルダ（複数可）。既定は現在のフォルダ。

.PARAMETER DetailOut
    非 UTF-8 のファイル明細を書き出す CSV のパス。省略すると明細は出さない。

.PARAMETER Extension
    調べる拡張子。既定はソースと設定の主なもの。

.PARAMETER ExcludeDir
    名前が一致したフォルダを丸ごと飛ばす。既定はビルド成果物と VCS。

.EXAMPLE
    pwsh -File .\Survey-Encoding.ps1 -Path C:\work\src
    集計だけを画面に出す。

.EXAMPLE
    pwsh -File .\Survey-Encoding.ps1 -Path C:\work\src -DetailOut $env:TEMP\enc-detail.csv
    集計を画面に出し、非 UTF-8 の明細を CSV に書く。
#>
[CmdletBinding()]
param(
    [string[]]$Path = @('.'),
    [string]$DetailOut,
    [string[]]$Extension = @(
        '.c', '.cpp', '.cc', '.cxx', '.h', '.hpp', '.inl', '.rc', '.cs', '.vb',
        '.py', '.ps1', '.psm1', '.bat', '.cmd', '.sh', '.lua', '.js', '.ts',
        '.vcxproj', '.filters', '.sln', '.props', '.targets', '.csproj',
        '.txt', '.md', '.csv', '.ini', '.cfg', '.json', '.xml', '.yaml', '.yml', '.sql', '.def', '.log'
    ),
    [string[]]$ExcludeDir = @(
        '.git', '.svn', '.vs', '.vscode', 'node_modules', '__pycache__',
        'obj', 'bin', 'Debug', 'Release', 'x64', 'Win32', 'packages', 'ipch'
    )
)

$ErrorActionPreference = 'Stop'

# 画面・リダイレクト先への出力を UTF-8 にする。これを指定しないと、パイプや
# ファイルへ流した時に CP932 で書かれ、報告そのものが化ける
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

# .NET Core（PowerShell 7）は CP932 を既定で持たない。プロバイダを登録して使えるようにする
try { [System.Text.Encoding]::GetEncoding(932) | Out-Null }
catch {
    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
}
$cp932 = [System.Text.Encoding]::GetEncoding(932)
# 不正バイトで例外を投げる厳密なデコーダ（既定は黙って '?' に置き換えてしまう）
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

function Get-FileEncodingKind {
    param([byte[]]$Bytes)

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return 'Utf8Bom' }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return 'Utf16Le' }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) { return 'Utf16Be' }

    $nonAscii = $false
    foreach ($b in $Bytes) { if ($b -ge 0x80) { $nonAscii = $true; break } }

    try {
        $utf8Strict.GetString($Bytes) | Out-Null
        if ($nonAscii) { return 'Utf8' } else { return 'Ascii' }
    } catch {}

    try {
        $s = $cp932.GetString($Bytes)
        # CP932 デコーダは未定義バイトを U+FFFD にする。混ざっていたら CP932 ではない
        if ($s.IndexOf([char]0xFFFD) -lt 0) { return 'Cp932' }
    } catch {}

    return 'Undecidable'
}

$summary = [ordered]@{}
foreach ($k in 'Ascii', 'Utf8', 'Utf8Bom', 'Cp932', 'Utf16Le', 'Utf16Be', 'Undecidable') { $summary[$k] = 0 }
$byExt = @{}
$detail = New-Object System.Collections.Generic.List[object]
$crlfMixed = 0
$scanned = 0
$skippedBig = 0

foreach ($root in $Path) {
    $rootFull = (Resolve-Path -LiteralPath $root).Path
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $f = $_
        # 除外フォルダの判定（パスの要素名で見る）
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/')
        $segs = $rel -split '[\\/]'
        for ($i = 0; $i -lt $segs.Length - 1; $i++) {
            if ($ExcludeDir -contains $segs[$i]) { return }
        }
        if ($Extension -notcontains $f.Extension.ToLowerInvariant()) { return }
        if ($f.Length -eq 0) { return }
        if ($f.Length -gt 8MB) { $script:skippedBig++; return }

        try { $bytes = [System.IO.File]::ReadAllBytes($f.FullName) } catch { return }

        $kind = Get-FileEncodingKind -Bytes $bytes
        $script:scanned++
        $summary[$kind]++

        $ext = $f.Extension.ToLowerInvariant()
        if (-not $byExt.ContainsKey($ext)) { $byExt[$ext] = @{} }
        if (-not $byExt[$ext].ContainsKey($kind)) { $byExt[$ext][$kind] = 0 }
        $byExt[$ext][$kind]++

        # 改行の混在（同じファイルに LF と CRLF）。検索ではなく diff が荒れる原因
        if ($kind -in 'Ascii', 'Utf8', 'Utf8Bom', 'Cp932') {
            $text = if ($kind -eq 'Cp932') { $cp932.GetString($bytes) } else { [System.Text.Encoding]::UTF8.GetString($bytes) }
            $crlf = ([regex]::Matches($text, "`r`n")).Count
            $lf = ([regex]::Matches($text, "(?<!`r)`n")).Count
            if ($crlf -gt 0 -and $lf -gt 0) { $script:crlfMixed++ }
        }

        if ($kind -notin 'Ascii', 'Utf8') {
            $detail.Add([pscustomobject]@{
                    Kind      = $kind
                    Bytes     = $f.Length
                    Modified  = $f.LastWriteTime.ToString('yyyy-MM-dd')
                    FullName  = $f.FullName
                })
        }
    }
}

# ---- 集計（数字だけ・パスを含まない） ----
Write-Host ''
Write-Host '== 文字コードの集計 ==' -ForegroundColor Cyan
Write-Host ("調べたファイル: {0}" -f $scanned)
if ($skippedBig -gt 0) { Write-Host ("8MB 超で飛ばした: {0}" -f $skippedBig) }
Write-Host ''
foreach ($k in $summary.Keys) {
    if ($summary[$k] -gt 0) {
        $pct = if ($scanned -gt 0) { [math]::Round(100 * $summary[$k] / $scanned, 1) } else { 0 }
        Write-Host ("  {0,-12} {1,6}  ({2}%)" -f $k, $summary[$k], $pct)
    }
}
Write-Host ''
Write-Host ("改行が混在しているファイル: {0}" -f $crlfMixed)

Write-Host ''
Write-Host '== 拡張子ごとの内訳（非 UTF-8 があるものだけ） ==' -ForegroundColor Cyan
foreach ($ext in ($byExt.Keys | Sort-Object)) {
    $kinds = $byExt[$ext]
    $bad = ($kinds.Keys | Where-Object { $_ -notin 'Ascii', 'Utf8' })
    if (-not $bad) { continue }
    $total = ($kinds.Values | Measure-Object -Sum).Sum
    $parts = ($kinds.Keys | Sort-Object | ForEach-Object { "{0}={1}" -f $_, $kinds[$_] }) -join ' '
    Write-Host ("  {0,-12} 計{1,5}  {2}" -f $ext, $total, $parts)
}

# ---- MSVC の /utf-8 の有無（BOM なし UTF-8 に変換できるかの判定材料） ----
Write-Host ''
Write-Host '== MSVC の /utf-8 指定 ==' -ForegroundColor Cyan
$projs = @()
foreach ($root in $Path) {
    $rootFull = (Resolve-Path -LiteralPath $root).Path
    $projs += Get-ChildItem -LiteralPath $rootFull -Recurse -File -Include '*.vcxproj', '*.props' -ErrorAction SilentlyContinue
}
if ($projs.Count -eq 0) {
    Write-Host '  .vcxproj / .props が見つからない（C++ プロジェクトなし、または別の場所）'
} else {
    $withUtf8 = @($projs | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -match '/utf-8' })
    Write-Host ("  プロジェクト/props: {0} 件、そのうち /utf-8 あり: {1} 件" -f $projs.Count, $withUtf8.Count)
    if ($withUtf8.Count -lt $projs.Count) {
        Write-Host '  → /utf-8 が無いものは、BOM なし UTF-8 に変換すると文字列リテラルが壊れる' -ForegroundColor Yellow
        Write-Host '    （変換先は UTF-8 BOM 付きにするか、先に /utf-8 を足す）' -ForegroundColor Yellow
    }
}

# ---- git の状況（巻き戻せるか・working-tree-encoding が使えるか） ----
Write-Host ''
Write-Host '== git ==' -ForegroundColor Cyan
foreach ($root in $Path) {
    $rootFull = (Resolve-Path -LiteralPath $root).Path
    Push-Location $rootFull
    try {
        $top = & git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $top) {
            $ver = (& git --version 2>$null) -replace 'git version ', ''
            $dirty = @(& git status --porcelain 2>$null).Count
            $wte = & git check-attr working-tree-encoding -- . 2>$null
            Write-Host ("  {0}: git 管理下（version {1}・未コミット {2} 件）" -f $rootFull, $ver, $dirty)
            Write-Host ("    working-tree-encoding: {0}" -f ($wte -replace '^.*working-tree-encoding: ', ''))
        } else {
            Write-Host ("  {0}: git 管理下ではない（変換前に手でバックアップが必要）" -f $rootFull)
        }
    } finally { Pop-Location }
}

# ---- 明細（パスを含む・指定した時だけ） ----
if ($DetailOut) {
    $detail | Sort-Object Kind, FullName | Export-Csv -LiteralPath $DetailOut -NoTypeInformation -Encoding UTF8
    Write-Host ''
    Write-Host ("明細を書いた: {0}（{1} 件・パスを含むので持ち出さない）" -f $DetailOut, $detail.Count) -ForegroundColor Green
} elseif ($detail.Count -gt 0) {
    Write-Host ''
    Write-Host ("非 UTF-8 が {0} 件。パス付きの明細が要るなら -DetailOut <csv> を付けて再実行する" -f $detail.Count)
}
Write-Host ''
