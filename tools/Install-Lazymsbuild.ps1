<#
.SYNOPSIS
    lazymsbuild（Visual Studio のソリューションの compile_commands.json を保つ TUI）を入れる。

.DESCRIPTION
    clangd に Visual Studio のソリューションを読ませる道具。Neovim の :CompileCommands はこれの
    sync を呼ぶ。ビルドのたびに実際のコマンドラインで DB を更新するので、DB がビルドに追従する。

    正本: https://github.com/6r1ntry52o/lazymsbuild

    GitHub Releases から固定した版の zip を取り、SHA256 を確かめて
    %LOCALAPPDATA%\Programs\lazymsbuild\ に置き、そこをユーザーの PATH に足す（管理者権限は要らない）。
    自動更新はしない。版を上げる時は -Version と -Sha256 の既定値を直す。

    確かめ方は 2 段。固定した -Sha256 で SHA256SUMS（x64 と ARM64 の zip のハッシュの一覧）を確かめ、
    その一覧で、この PC のアーキテクチャの zip を確かめる。入れたファイルのハッシュは
    install.sha256 に残し、次からはそれが合えば何もしない（ネットワークにも出ない）。

    sync が使う msbuild-extractor-sample は別に入れる（tools\Install-MsbuildExtractor.ps1）。

.PARAMETER Version
    入れるリリースのタグ（v0.1.0 など）。空なら何もしない（リリースを固定するまで）。

.PARAMETER Sha256
    そのリリースの SHA256SUMS の SHA256。上げる時は、リリースのページから SHA256SUMS を落として
    Get-FileHash SHA256SUMS で取る（https://api.github.com/repos/6r1ntry52o/lazymsbuild/releases の
    assets[].digest にも出る）。

.PARAMETER Destination
    置き場所。既定は %LOCALAPPDATA%\Programs\lazymsbuild。

.PARAMETER BaseUrl
    リリースの置き場所。既定は GitHub Releases。ミラーから入れる時に変える。

.PARAMETER SkipPath
    PATH を触らない（自分で通す時）。

.EXAMPLE
    pwsh -File tools\Install-Lazymsbuild.ps1
    入れたあと、新しいタブで lazymsbuild doctor
#>
[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$Sha256 = '',
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'Programs\lazymsbuild'),
    [string]$BaseUrl = 'https://github.com/6r1ntry52o/lazymsbuild/releases/download',
    [switch]$SkipPath,
    # テスト用: PATH を書き込むレジストリキー
    [Parameter(DontShow)] [string]$EnvironmentKey = 'HKCU:\Environment'
)

$ErrorActionPreference = 'Stop'

if (-not $Version -or -not $Sha256) {
    Write-Host 'lazymsbuild: 入れる版がまだ固定されていない（-Version と -Sha256）。何もしない'
    return
}

# プロセスのではなく OS のアーキテクチャ（ARM64 の PC でも x64 の PowerShell なら
# $env:PROCESSOR_ARCHITECTURE は AMD64 になる）。
$arch = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').PROCESSOR_ARCHITECTURE
$target = if ($arch -eq 'ARM64') { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
$name = "lazymsbuild-$Version-$target"
$sumsHash = $Sha256.ToUpperInvariant()
$record = Join-Path $Destination 'install.sha256'
$header = "# lazymsbuild $Version $target (SHA256SUMS $sumsHash)"

# 前回このスクリプトが入れたものが、そのまま残っているか
function Test-Installed {
    if (-not (Test-Path $record)) { return $false }
    $lines = @(Get-Content $record)
    if ($lines.Count -lt 2 -or $lines[0] -ne $header) { return $false }
    foreach ($line in $lines | Select-Object -Skip 1) {
        if ($line -notmatch '^([0-9A-F]{64})  (.+)$') { return $false }
        $file = Join-Path $Destination $Matches[2]
        $hash = $Matches[1]
        if (-not (Test-Path $file) -or (Get-FileHash $file -Algorithm SHA256).Hash -ne $hash) { return $false }
    }
    return $true
}

if (Test-Path $Destination) {
    # 前回、使用中だったので退避したファイル（下の catch）。もう使われていなければ消える
    Get-ChildItem $Destination -Filter '*.old-*' -File | Remove-Item -Force -ErrorAction SilentlyContinue
}

if (Test-Installed) {
    Write-Host "既に入っている: $Destination ($Version)"
}
else {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('lazymsbuild-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $sums = Join-Path $tmp 'SHA256SUMS'
        $zip = Join-Path $tmp "$name.zip"
        # 進捗バーを出すと取得が極端に遅くなる（Invoke-WebRequest の既知の挙動）
        $prev = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Write-Host "取得する: $BaseUrl/$Version/SHA256SUMS"
            Invoke-WebRequest -Uri "$BaseUrl/$Version/SHA256SUMS" -OutFile $sums -UseBasicParsing
            $actual = (Get-FileHash $sums -Algorithm SHA256).Hash
            if ($actual -ne $sumsHash) {
                throw "SHA256SUMS の SHA256 が合わない`n  expected: $sumsHash`n  actual:   $actual"
            }
            $zipHash = $null
            foreach ($line in Get-Content $sums) {
                if ($line -match '^([0-9a-fA-F]{64}) [ *](\S+)\s*$' -and $Matches[2] -eq "$name.zip") {
                    $zipHash = $Matches[1].ToUpperInvariant()
                }
            }
            if (-not $zipHash) { throw "SHA256SUMS に $name.zip が無い（この版には $target 向けが無い）" }
            Write-Host "取得する: $BaseUrl/$Version/$name.zip"
            Invoke-WebRequest -Uri "$BaseUrl/$Version/$name.zip" -OutFile $zip -UseBasicParsing
        }
        finally {
            $ProgressPreference = $prev
        }
        $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
        if ($actual -ne $zipHash) {
            throw "$name.zip の SHA256 が合わない`n  expected: $zipHash`n  actual:   $actual"
        }
        Expand-Archive -Path $zip -DestinationPath $tmp
        $src = Join-Path $tmp $name
        if (-not (Test-Path (Join-Path $src 'lazymsbuild.exe'))) { throw "$name.zip に $name\lazymsbuild.exe が無い" }

        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        $hashes = @()
        foreach ($file in Get-ChildItem $src -File) {
            $dst = Join-Path $Destination $file.Name
            try {
                Copy-Item $file.FullName $dst -Force
            }
            catch {
                # 動いている exe（開いたままの TUI）は上書きできないが、名前は変えられる
                Rename-Item $dst ('{0}.old-{1}' -f $file.Name, (Get-Date -Format yyyyMMddHHmmss))
                Copy-Item $file.FullName $dst -Force
            }
            $hashes += '{0}  {1}' -f (Get-FileHash $dst -Algorithm SHA256).Hash, $file.Name
        }
        [IO.File]::WriteAllLines($record, [string[]](@($header) + $hashes))
        Write-Host "入れた: $Destination ($Version, $target)"
    }
    finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# PATH（ユーザー環境変数）。今の値は %USERPROFILE% などを展開せずに読み書きする
# （[Environment]::SetEnvironmentVariable は展開した値を REG_SZ で書き戻してしまう）。
$dir = $Destination.TrimEnd('\')
if ($SkipPath) {
    Write-Host 'PATH は触らない（-SkipPath）'
}
else {
    $key = Get-Item $EnvironmentKey
    $raw = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $kind = if ($key.GetValueNames() -contains 'Path') { $key.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
    $parts = @($raw -split ';' | Where-Object { $_ -ne '' })
    $present = @($parts | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -eq $dir })
    if ($present.Count -gt 0) {
        Write-Host "PATH は通っている: $dir"
    }
    elseif ($kind -ne 'String' -and $kind -ne 'ExpandString') {
        Write-Warning "ユーザーの PATH の型が想定外（$kind）。PATH に $dir を手で足す"
    }
    else {
        $entry = $dir
        $local = $env:LOCALAPPDATA.TrimEnd('\')
        if ($kind -eq 'ExpandString' -and $dir.StartsWith($local + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $entry = '%LOCALAPPDATA%' + $dir.Substring($local.Length)
        }
        Set-ItemProperty -Path $EnvironmentKey -Name Path -Value (($parts + $entry) -join ';') -Type $kind
        # 変わったことを Explorer などに知らせる（以後に起動するアプリが新しい PATH を受け取る）。
        # 応答しないウィンドウで止まらないよう、SMTO_ABORTIFHUNG で 5 秒まで。
        if (-not ('Dotfiles.SettingChange' -as [type])) {
            Add-Type -Name SettingChange -Namespace Dotfiles -MemberDefinition @"
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
"@
        }
        $result = [UIntPtr]::Zero
        [void][Dotfiles.SettingChange]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
        $env:Path = "$env:Path;$dir"
        Write-Host "PATH に足した: $entry（開いているターミナルには効かない。新しいタブから使う）"
    }
}

Write-Host ''
Write-Host '--- 動作確認 (--version) ---'
& (Join-Path $Destination 'lazymsbuild.exe') --version
