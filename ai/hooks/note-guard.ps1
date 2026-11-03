<#
.SYNOPSIS
    PreToolUse hook for Claude Code and GitHub Copilot CLI: keeps <vault>/note/ read-only.

.DESCRIPTION
    note/ is the user's own writing (see ai/skills/vault-note/SKILL.md). An agent may only change
    a "- [ ]" line by inserting [[links]] into it, or by turning it into "- [a]" (with the link to
    its write-up). Every other write to note/ is put to the user: a new file, a rewrite, added or
    removed lines, [d]/[x], and shell commands that write, move or delete there. Reading is free.

    The vault is "vault" in ~/.dotfiles.json, read on every call. Without it the hook does nothing.
    It reads the hook input (JSON) on stdin and prints a decision only when it has to ask; nothing
    printed means "carry on as usual". If the hook itself breaks it lets the call through (an
    error here must not stop the agent): this is a guard rail, not the only line of defence.

    Claude Code sends file_path / old_string / new_string. Copilot CLI (event "PreToolUse") sends
    Claude's tool names, but its argument names are not documented, so path / old_str / new_str
    are read too, and an edit whose arguments are not understood is asked about.

.PARAMETER Format
    claude (default) or copilot: the shape of the decision this hook prints.

.NOTES
    tools/Install-AiAgents.ps1 wires it up: Claude Code in ~/.claude/settings.json (shell commands
    only when they mention "note"), Copilot CLI in ~/.copilot/hooks/note-guard.json.
#>
[CmdletBinding()]
param([ValidateSet('claude', 'copilot')][string]$Format = 'claude')

$ErrorActionPreference = 'Stop'

function Get-Norm([string]$s) {
    if ($null -eq $s) { return '' }
    return $s.Replace('\', '/').Trim()
}

# A path as an absolute, forward-slash, lower-case string.
function Get-AbsPath([string]$p, [string]$cwd) {
    $s = (Get-Norm $p).Trim('"', "'")
    if (-not $s) { return '' }
    $s = [regex]::Replace($s, '^/([a-zA-Z])(?=/|$)', { param($m) $m.Groups[1].Value.ToUpper() + ':' })   # Git Bash /c/...
    $s = [regex]::Replace($s, '^(~|\$HOME|\$env:USERPROFILE)(?=/|$)', (Get-Norm $HOME), 'IgnoreCase')
    try {
        if (-not [IO.Path]::IsPathRooted($s)) {
            $base = if ($cwd) { $cwd } else { (Get-Location).Path }
            $s = [IO.Path]::Combine($base, $s)
        }
        $s = [IO.Path]::GetFullPath($s)
    } catch { }
    return (Get-Norm $s).TrimEnd('/').ToLowerInvariant()
}

function Test-InNote([string]$p, [string]$cwd) {
    if (-not $p) { return $false }
    $a = Get-AbsPath $p $cwd
    return ($a -eq $script:NoteDir) -or $a.StartsWith($script:NoteDir + '/')
}

# --- What an agent may do to one line of a note ---
$TaskLine = '^(\s*[-*+] \[)(.)(\] ?)(.*)$'
$WikiLink = '\[\[[^\]\n]+\]\]'

# true when the new line only adds [[links]] to a "- [ ]" line, or turns it into "- [a]" (and adds
# links). Removing a link, changing the text or setting [d]/[x] is not allowed.
function Test-AllowedTaskLine([string]$o, [string]$n) {
    if ($o -ceq $n) { return $true }
    $mo = [regex]::Match($o, $TaskLine)
    $mn = [regex]::Match($n, $TaskLine)
    if (-not $mo.Success -or -not $mn.Success) { return $false }
    if ($mo.Groups[1].Value -cne $mn.Groups[1].Value -or $mo.Groups[3].Value -cne $mn.Groups[3].Value) { return $false }
    $so = $mo.Groups[2].Value
    $sn = $mn.Groups[2].Value
    if (-not ((($so -ceq $sn) -and ($so -ceq ' ' -or $so -ceq 'a')) -or ($so -ceq ' ' -and $sn -ceq 'a'))) { return $false }
    $left = @{}
    foreach ($m in [regex]::Matches($mo.Groups[4].Value, $WikiLink)) { $left[$m.Value] = 1 + [int]$left[$m.Value] }
    $rest = [regex]::Replace($mn.Groups[4].Value, $WikiLink, {
            param($m)
            if ([int]$left[$m.Value] -gt 0) { $left[$m.Value] = [int]$left[$m.Value] - 1; return $m.Value }
            return ' '
        })
    foreach ($v in $left.Values) { if ($v -gt 0) { return $false } }
    $squash = { param($s) ([regex]::Replace($s, '\s+', ' ')).Trim() }
    return (& $squash $rest) -ceq (& $squash $mo.Groups[4].Value)
}

function Test-AllowedNoteEdit($old, $new) {
    if (-not ($old -is [string]) -or -not ($new -is [string]) -or -not $old) { return $false }
    $a = $old -split '\r?\n'
    $b = $new -split '\r?\n'
    if ($a.Count -ne $b.Count) { return $false }   # no lines added or removed
    for ($i = 0; $i -lt $a.Count; $i++) {
        if (-not (Test-AllowedTaskLine $a[$i] $b[$i])) { return $false }
    }
    return $true
}

# --- Shell commands that write to note/ (the same rules as the core vault's own guard) ---
$WriteVerb = '(^|[\s(])(rm|rmdir|unlink|shred|mv|tee|truncate|touch|del|erase|ren|rename|Remove-Item|ri|Move-Item|mi|Rename-Item|rni|Set-Content|sc|Add-Content|ac|Out-File|New-Item|ni|Clear-Content|clc)(?=\s|$)'
$CopyVerb = '(^|[\s(])(cp|Copy-Item|cpi|copy|robocopy|xcopy)(?=\s|$)'
$InPlace = '(^|[\s(])(sed|perl)\b[^\n]*\s-[a-zA-Z]*i'
$GitWrite = '\bgit\b[^\n]*\s(checkout|restore|rm|mv|stash|apply|am|clean)\b'

function Get-ShellWrite([string]$cmd, [string]$cwd) {
    foreach ($seg in [regex]::Split($cmd, '&&|\|\||[;\n|]')) {
        foreach ($m in [regex]::Matches($seg, '(?:\d|&)?>{1,2}\s*([''"]?)([^\s''";|&]+)\1')) {
            if (Test-InNote $m.Groups[2].Value $cwd) { return 'writes to note/ through a redirect' }
        }
        $toks = @([regex]::Split((Get-Norm $seg), '[\s;|&><()''"`]+') | Where-Object { $_ -and -not $_.StartsWith('-') })
        if (-not @($toks | Where-Object { Test-InNote $_ $cwd }).Count) { continue }
        if ($seg -match $WriteVerb) { return 'deletes, moves or writes a file in note/' }
        if ($seg -match $InPlace) { return 'edits a file in note/ in place (sed/perl -i)' }
        if ($seg -match $GitWrite) { return 'rewrites or removes note/ with git' }
        if (($seg -match $CopyVerb) -and (Test-InNote $toks[-1] $cwd)) { return 'copies into note/' }
    }
    return $null
}

function Get-Field($obj, [string[]]$names) {
    foreach ($n in $names) {
        $p = $obj.PSObject.Properties[$n]
        if ($p -and $null -ne $p.Value) { return $p.Value }
    }
    return $null
}

# Every string inside the tool input (for argument shapes this hook does not know).
function Get-Strings($v) {
    if ($v -is [string]) { return @($v) }
    if ($v -is [System.Collections.IEnumerable]) { return @($v | ForEach-Object { Get-Strings $_ }) }
    if ($v -is [pscustomobject]) { return @($v.PSObject.Properties | ForEach-Object { Get-Strings $_.Value }) }
    return @()
}

function Get-Decision($payload) {
    $tool = [string]$payload.tool_name
    $in = $payload.tool_input
    if ($in -is [string]) { try { $in = $in | ConvertFrom-Json } catch { } }
    $cwd = [string]$payload.cwd
    if ($null -eq $in) { return $null }

    if ($tool -eq 'Bash' -or $tool -eq 'PowerShell') {
        $cmd = [string](Get-Field $in @('command'))
        if (-not $cmd) { return $null }
        return (Get-ShellWrite $cmd $cwd)
    }

    if (@('Edit', 'MultiEdit', 'Write', 'NotebookEdit') -notcontains $tool) { return $null }
    $path = [string](Get-Field $in @('file_path', 'path', 'filePath', 'notebook_path'))
    if (-not $path) {
        # An edit we cannot read the target of: ask if anything in it points into note/.
        foreach ($s in (Get-Strings $in)) {
            foreach ($t in [regex]::Split((Get-Norm $s), '[\s''"`]+')) {
                if ($t -and (Test-InNote $t $cwd)) { return 'changes note/ in a way this hook cannot check' }
            }
        }
        return $null
    }
    if (-not (Test-InNote $path $cwd)) { return $null }
    if ($tool -eq 'Write' -or $tool -eq 'NotebookEdit') { return "writes a whole file in note/: $path" }

    $command = [string](Get-Field $in @('command'))   # Copilot's str_replace_editor
    if ($command -eq 'view') { return $null }
    if ($command -and $command -ne 'str_replace') { return "changes note/ ($command): $path" }

    $edits = if ($tool -eq 'MultiEdit') { @($in.edits) } else { @($in) }
    if ($edits.Count -eq 0) { return "changes note/: $path" }
    foreach ($e in $edits) {
        $old = Get-Field $e @('old_string', 'old_str', 'oldString')
        $new = Get-Field $e @('new_string', 'new_str', 'newString')
        if (-not (Test-AllowedNoteEdit $old $new)) {
            return "changes note/ beyond adding [[links]] to a - [ ] line or marking it - [a]: $path"
        }
    }
    return $null
}

try {
    $cfgPath = Join-Path $HOME '.dotfiles.json'
    if (-not (Test-Path $cfgPath)) { exit 0 }
    $vault = (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json).vault
    if (-not $vault) { exit 0 }
    $script:NoteDir = (Get-AbsPath (Join-Path $vault 'note') '')

    # stdin as UTF-8 bytes (the console code page would garble non-ASCII paths)
    $ms = New-Object IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($ms)
    $raw = [Text.Encoding]::UTF8.GetString($ms.ToArray())
    # To see what an agent really sends (Copilot's argument names are not documented):
    # set NOTE_GUARD_LOG to a file before starting the agent.
    if ($env:NOTE_GUARD_LOG) { [IO.File]::AppendAllText($env:NOTE_GUARD_LOG, $raw + "`n", [Text.Encoding]::UTF8) }
    if (-not $raw.Trim()) { exit 0 }
    $why = Get-Decision ($raw | ConvertFrom-Json)
    if (-not $why) { exit 0 }

    $reason = "note/ is the user's own writing; agents may only add [[links]] to a - [ ] line or mark it - [a] (vault-note skill). This call $why"
    $out = if ($Format -eq 'copilot') {
        [ordered]@{ permissionDecision = 'ask'; permissionDecisionReason = $reason }
    } else {
        [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'PreToolUse'; permissionDecision = 'ask'; permissionDecisionReason = $reason } }
    }
    $json = $out | ConvertTo-Json -Compress -Depth 5
    $stdout = [Console]::OpenStandardOutput()
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
    exit 0
} catch {
    [Console]::Error.WriteLine("note-guard: $($_.Exception.Message)")
    exit 0
}
