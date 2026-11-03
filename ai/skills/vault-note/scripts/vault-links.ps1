<#
.SYNOPSIS
    Links of one note in the Obsidian vault, as JSON: what it links to, what links to it, and the
    lines around each link.

.DESCRIPTION
    Asks the running Obsidian app through its command line interface (Obsidian 1.12 or later,
    Settings > General > Command line interface). The answer comes from Obsidian's own link index,
    so it is current and resolves [[name]], aliases, headings and embeds exactly as the app does.
    If Obsidian is closed, the first call starts it. Nothing is written to the vault.

      links       each line of the note that holds a link, the lines around it, and where the
                  links go (vault paths; "name (unresolved)" when no note has that name;
                  "!" before an embed)
      backlinks   each line in another note that links here, with the lines around it

    Context is keyed by 1-based line number. Lines longer than 300 characters are cut.

.PARAMETER Note
    A vault path (note/a.md), the same without .md, or a name as written in [[name]].

.PARAMETER Context
    Lines to show before and after each link (default 1).

.PARAMETER Direction
    both (default), out (links only) or in (backlinks only).

.PARAMETER Limit
    Most backlink lines to return (default 50). The rest are counted in backlinks_omitted.

.PARAMETER Vault
    The vault folder. Default: "vault" in ~/.dotfiles.json.

.EXAMPLE
    pwsh -File vault-links.ps1 Brain_IF
    pwsh -File vault-links.ps1 note/Obsidian_Vault.md -Direction in -Context 0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Note,
    [ValidateRange(0, 20)][int]$Context = 1,
    [ValidateSet('both', 'out', 'in')][string]$Direction = 'both',
    [ValidateRange(1, 10000)][int]$Limit = 50,
    [string]$Vault
)

$ErrorActionPreference = 'Stop'

function Fail($message) {
    [Console]::Error.WriteLine("vault-links: $message")
    exit 1
}

if (-not $Vault) {
    $cfgPath = Join-Path $HOME '.dotfiles.json'
    if (Test-Path $cfgPath) {
        try { $Vault = (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json).vault } catch { }
    }
    if (-not $Vault) { Fail "no vault: set ""vault"" in $cfgPath or pass -Vault" }
}
if (-not (Test-Path $Vault -PathType Container)) { Fail "vault folder not found: $Vault" }

# Obsidian names a vault after its folder. The CLI must be switched on in Obsidian.
$vaultFull = (Resolve-Path $Vault).Path.TrimEnd('\')
$obsidianJson = Join-Path $env:APPDATA 'obsidian\obsidian.json'
if (Test-Path $obsidianJson) {
    $known = Get-Content $obsidianJson -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $known.cli) { Fail 'turn on Settings > General > Command line interface in Obsidian' }
    $registered = @($known.vaults.PSObject.Properties | ForEach-Object { $_.Value.path.TrimEnd('\') })
    if ($registered -notcontains $vaultFull) { Fail "Obsidian does not know this vault yet (open it once in Obsidian): $vaultFull" }
}
$vaultName = Split-Path -Leaf $vaultFull

$exe = (Get-Command obsidian -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $exe) {
    $exe = Join-Path $env:LOCALAPPDATA 'Programs\Obsidian\Obsidian.exe'
    if (-not (Test-Path $exe)) { Fail 'Obsidian is not installed (obsidian is not on PATH)' }
}

function ConvertTo-Base64([string]$text) {
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
}

# The request and the script both travel base64-encoded: the command line then carries only
# letters, digits and a few symbols, the same under Windows PowerShell 5.1 and PowerShell 7.
$request = [ordered]@{ note = $Note; context = $Context; limit = $Limit; direction = $Direction } | ConvertTo-Json -Compress
$js = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'vault-links.js'), [Text.Encoding]::UTF8)
$js = $js.Replace('__REQ__', (ConvertTo-Base64 $request))
$loader = "(0,eval)(new TextDecoder().decode(Uint8Array.from(atob('$(ConvertTo-Base64 $js)'),c=>c.charCodeAt(0))))"

# Obsidian.exe is a GUI program: PowerShell captures its output only through a pipeline. It
# writes UTF-8, and its startup notices come first on the same stream; the answer is the line
# that starts with "=> ". Output stays UTF-8 so a caller reading the bytes (Git Bash, another
# shell) gets the same text.
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$lines = @(& $exe "vault=$vaultName" eval "code=$loader" 2>$null | ForEach-Object { "$_" })
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith('=> ')) { $start = $i; break }
}
if ($start -lt 0) {
    Fail ("no answer from Obsidian (is the app running and the CLI on?)`n" + ($lines -join "`n"))
}
$answer = (@($lines[$start].Substring(3)) + @($lines | Select-Object -Skip ($start + 1))) -join "`n"
if ($answer -match '^\{"error":') {
    [Console]::Error.WriteLine("vault-links: $answer")
    exit 1
}
$answer
