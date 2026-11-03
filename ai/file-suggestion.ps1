<#
.SYNOPSIS
    Claude Code's @ autocomplete (setting "fileSuggestion"): the files of the project, plus the
    notes in <vault>/note/ wherever the session started.

.DESCRIPTION
    Claude Code replaces its own @ suggestions with what this prints, so it lists the project too:
    the files and folders under CLAUDE_PROJECT_DIR that ripgrep lists (it skips what .gitignore
    leaves out, as the built-in does), then the notes. Notes are printed as absolute paths, so
    picking one attaches that note from any repository. Without ripgrep, the project files come
    from git ls-files (or nothing outside a repository).

    Input: JSON on stdin, {"query": "<what follows @>"}. Output: up to 15 paths, best first.
    Matching ignores case: a name that starts with the query first, then a name or path that
    contains it, then a path that has its letters in order. A query that starts with "note/"
    looks at the notes only. The vault is "vault" in ~/.dotfiles.json; without it, only the
    project is listed.
#>
$ErrorActionPreference = 'Stop'

function Get-Score([string]$path, [string]$q) {
    if (-not $q) { return 2 }
    $p = $path.ToLowerInvariant()
    $name = $p.TrimEnd('/')
    $name = $name.Substring($name.LastIndexOf('/') + 1)
    if ($name.StartsWith($q)) { return 0 }
    if ($name.Contains($q)) { return 1 }
    if ($p.Contains($q)) { return 2 }
    $i = 0
    foreach ($c in $p.ToCharArray()) {
        if ($i -lt $q.Length -and $c -eq $q[$i]) { $i++ }
    }
    if ($i -eq $q.Length) { return 3 }
    return -1
}

try {
    $ms = New-Object IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($ms)
    $raw = [Text.Encoding]::UTF8.GetString($ms.ToArray())
    $query = ''
    if ($raw.Trim()) { $query = [string]($raw | ConvertFrom-Json).query }
    $q = $query.Replace('\', '/').ToLowerInvariant()

    $notesOnly = $q.StartsWith('note/')
    $candidates = New-Object System.Collections.Generic.List[object]

    # The project: files and the folders that hold them, relative to the project root
    $project = $env:CLAUDE_PROJECT_DIR
    if (-not $notesOnly -and $project -and (Test-Path $project)) {
        $files = @()
        if (Get-Command rg -ErrorAction SilentlyContinue) {
            $files = @(& rg --files --hidden --glob '!.git/' $project 2>$null)
        } elseif (Get-Command git -ErrorAction SilentlyContinue) {
            $files = @(& git -C $project ls-files 2>$null | ForEach-Object { Join-Path $project $_ })
        }
        $root = $project.Replace('\', '/').TrimEnd('/') + '/'
        $dirs = @{}
        foreach ($f in $files) {
            $rel = $f.Replace('\', '/')
            if ($rel.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($root.Length) }
            $candidates.Add(@($rel, 0))
            $k = $rel.LastIndexOf('/')
            while ($k -gt 0) {
                $d = $rel.Substring(0, $k + 1)
                if ($dirs.ContainsKey($d)) { break }
                $dirs[$d] = $true
                $k = $rel.LastIndexOf('/', $k - 1)
            }
        }
        foreach ($d in $dirs.Keys) { $candidates.Add(@($d, 0)) }
    }

    # The notes, as absolute paths (the session may have started anywhere)
    $cfgPath = Join-Path $HOME '.dotfiles.json'
    if (Test-Path $cfgPath) {
        $vault = (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json).vault
        $noteDir = if ($vault) { Join-Path $vault 'note' } else { $null }
        if ($noteDir -and (Test-Path $noteDir)) {
            $noteRoot = (Resolve-Path $noteDir).Path.Replace('\', '/').TrimEnd('/') + '/'
            foreach ($n in Get-ChildItem $noteDir -Recurse -File -Filter *.md) {
                $candidates.Add(@($n.FullName.Replace('\', '/'), 1, $n.FullName.Replace('\', '/').Substring($noteRoot.Length)))
            }
        }
    }

    $match = if ($notesOnly) { $q.Substring(5) } else { $q }
    $ranked = foreach ($c in $candidates) {
        # A note is matched by its path inside note/, not by the folders above the vault
        $key = if ($c[1] -eq 1) { $c[2] } else { $c[0] }
        $s = Get-Score $key $match
        if ($s -ge 0) { [pscustomobject]@{ Path = $c[0]; Score = $s; Kind = $c[1]; Len = $key.Length } }
    }
    $out = @($ranked | Sort-Object Score, Kind, Len, Path | Select-Object -First 15 | ForEach-Object { $_.Path })
    $bytes = [Text.Encoding]::UTF8.GetBytes(($out -join "`n") + "`n")
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
} catch {
    [Console]::Error.WriteLine("file-suggestion: $($_.Exception.Message)")
    exit 1
}
