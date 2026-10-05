<#
.SYNOPSIS
    Visual Studio のソリューションから compile_commands.json を作る抽出ツールを入れる。

.DESCRIPTION
    clangd は compile_commands.json が無いと「今開いているファイルの翻訳単位」しか解析できない
    （別の .cpp にある定義が参照検索に出ない・プロジェクト固有の /I と /D が効かない）。
    MSBuild は compile_commands.json を出さないので、Microsoft の抽出ツールで作る。
    ビルドは要らない（design-time 評価）。

    正本: https://github.com/microsoft/msbuild-extractor-sample

    入れ先は %LOCALAPPDATA%\msbuild-extractor\。Neovim の :CompileCommands が
    PATH → <プロジェクト>\.tools → この場所、の順に探す（会社PCでは .tools\ に置く運用でも動く）。

    罠（2026-10-05 実測）: 配布物は self-contained の exe で、VS 側の MSBuild を見つけられないと
    .NET SDK 探索にフォールバックし、hostfxr.dll を解決できず DllNotFoundException で落ちる
    （--vs-path も --msbuild-path も効かない。RegisterMSBuild が引数より前に走るため）。
    dotnet の hostfxr.dll を exe の隣に置くと通る。本スクリプトがそれも行う。

.PARAMETER Version
    入れるリリースのタグ。

.PARAMETER Sha256
    その版の exe の SHA256。上げる時は
    https://api.github.com/repos/microsoft/msbuild-extractor-sample/releases/latest の
    assets[].digest から取る。

.PARAMETER Destination
    置き場所。既定は %LOCALAPPDATA%\msbuild-extractor。

.EXAMPLE
    pwsh -File tools\Install-MsbuildExtractor.ps1
    入れたあと、Neovim で C++ のファイルを開いて :CompileCommands
#>
[CmdletBinding()]
param(
    [string]$Version = 'v0.3.0',
    [string]$Sha256 = '543c5cc6b57a1b3eb46b11e56b8f35a9ca8676106426bde6041ca2dc2e06f13c',
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'msbuild-extractor')
)

$ErrorActionPreference = 'Stop'
$expected = $Sha256.ToUpper()
$exe = Join-Path $Destination 'msbuild-extractor-sample.exe'

New-Item -ItemType Directory -Path $Destination -Force | Out-Null

if ((Test-Path $exe) -and (Get-FileHash $exe -Algorithm SHA256).Hash -eq $expected) {
    Write-Host "既に入っている: $exe"
}
else {
    $url = "https://github.com/microsoft/msbuild-extractor-sample/releases/download/$Version/msbuild-extractor-sample.exe"
    $tmp = "$exe.download"
    Write-Host "取得する: $url"
    # 進捗バーを出すと 76MB の取得が極端に遅くなる（Invoke-WebRequest の既知の挙動）
    $prev = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
    }
    finally {
        $ProgressPreference = $prev
    }

    $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        Remove-Item $tmp -Force
        throw "SHA256 が合わない`n  expected: $expected`n  actual:   $actual"
    }
    Move-Item $tmp $exe -Force
    Write-Host "入れた: $exe"
}

# hostfxr.dll（.DESCRIPTION の罠）。無いと実行時に DllNotFoundException で落ちる。
$hostfxr = Join-Path $Destination 'hostfxr.dll'
if (Test-Path $hostfxr) {
    Write-Host "hostfxr.dll は既にある: $hostfxr"
}
else {
    $src = Get-ChildItem (Join-Path $env:ProgramFiles 'dotnet\host\fxr\*\hostfxr.dll') -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Directory.Name } | Select-Object -Last 1
    if ($null -eq $src) {
        Write-Warning 'dotnet の hostfxr.dll が見つからない。.NET SDK か .NET ランタイムを入れてから再実行する（無いと抽出ツールが落ちる）'
    }
    else {
        Copy-Item $src.FullName $hostfxr -Force
        Write-Host "hostfxr.dll を隣に置いた: $($src.FullName)"
    }
}

Write-Host ''
Write-Host '--- 動作確認 (--version) ---'
& $exe --version
