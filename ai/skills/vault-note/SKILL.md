---
name: vault-note
description: The user writes what they want, think and must do in note/ of their Obsidian vault, as linked notes and `- [ ]` TODOs. Use it to learn the purpose behind the current work, whenever the user mentions their notes, the vault, a note name or a TODO, and when you finish work a note asked for.
---

# The user's vault and `note/`

The vault is `vault` in `~/.dotfiles.json` (also `$env:DOTFILES_VAULT` in PowerShell). If it is not
set, this PC has no vault: say so and go on without it.

## What `note/` is

- `<vault>/note/` holds what the user wants, thinks and must do, written by the user alone. It is
  the source of truth for their intent. Work done elsewhere serves it.
- There are no folders by topic: a link is a relation. The entry point is `note/Brain_IF.md`; follow
  links from it (or from the note the user names) to the note behind the current work.
- Before planning work that comes from a note, read that note and the notes it links to, and keep
  the line you act on in view. If your plan drifts from what the note says, stop and ask.

## Read-only, with two exceptions

- Do not create, rewrite, reformat, move or delete anything under `note/`. Do not answer inside a
  note or add sections to it.
- On a plain list line the user wrote as `- ` you may insert a `[[link]]` to a related note. Do not
  turn it into a task.
- On a line the user wrote as `- [ ]` you may:
  - insert a `[[link]]` to a related note, and
  - when you have done that task, change `- [ ]` to `- [a]` and add the `[[link]]` to your
    write-up on the same line.
- Never set `[d]` or `[x]`: the user does, after checking. Never add or remove lines.
- A hook enforces this. When it asks, show the user the change you meant.

| Status | Meaning |
|---|---|
| `[ ]` | Not started |
| `[a]` | Done by an AI agent, not yet checked by the user. The line links the write-up |
| `[d]` | Done and checked; kept to look back on |
| `[x]` | Done and checked; nothing to look back on |

## Where you write

- Your write-ups and your own TODOs go under `vault_ai_dir` in `~/.dotfiles.json` (a folder
  relative to the vault), one file per field: `<vault>/<vault_ai_dir>/<field>.md`. Add a section
  per task, put your TODOs there as `- [ ]` lines, and link the section from the user's line
  (`[[<field>#<section>]]`). Do not gather everything in one file.
- If `vault_ai_dir` is not set, ask the user where to write before writing anything in the vault.
- Link instead of copying: point at the user's note with `[[name]]` rather than repeating its text,
  so each thing lives in one place. When you find your own older write-up out of date, fix it there.

## Follow links with `vault-links`

`scripts/vault-links.ps1` in this skill's folder (also
`$env:DOTFILES\ai\skills\vault-note\scripts\vault-links.ps1`) returns one note's links as JSON:

- `links`: each line of the note that holds links, the lines around it, and where the links go
  (vault paths; `name (unresolved)` when no note has that name; `!` before an embed)
- `backlinks`: each line in another note that links to it, with the lines around it

```powershell
& "<skill folder>\scripts\vault-links.ps1" Brain_IF                 # PowerShell
& "<skill folder>\scripts\vault-links.ps1" note/a.md -Direction in -Context 0 -Limit 20
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill folder>/scripts/vault-links.ps1" Brain_IF
```

- The note is a vault path, the path without `.md`, or a name as in `[[name]]`.
- Use it instead of searching for `[[name]]`: it resolves names, aliases and headings as Obsidian
  does and returns only the lines that link, so it is shorter and does not miss notes in other
  folders. Read a whole note only when the context lines are not enough.
- It asks the running Obsidian app (it starts the app when closed). If it fails, the error says
  why; then search the vault for `[[name` and `name.md` and say the result may miss aliases.
- Other read-only Obsidian commands: `obsidian vault=<folder name> search:context query=<text>`,
  `outline path=<path>`, `unresolved`. Do not use Obsidian commands that change the vault.

## Keep it local

- Do not send the contents of the vault to web searches or other online services.
