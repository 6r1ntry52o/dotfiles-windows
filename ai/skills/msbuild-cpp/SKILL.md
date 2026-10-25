---
name: msbuild-cpp
description: Read, change, build and debug C/C++ in a Visual Studio solution (.sln or .slnx, built with MSBuild) whose compile_commands.json is kept by lazymsbuild. Use for any C/C++ work in such a repository.
---

# Visual Studio C/C++ with clangd and lazymsbuild

You and the editor share one toolchain. lazymsbuild keeps `compile_commands.json` at the
repository root in step with the builds, and clangd (the C/C++ language server) analyses the code
with it.

## Find code through the language server

- Symbols (where something is defined, who calls it, what type it has): ask the language server
  (go to definition, find references, hover, call hierarchy). It returns that symbol only, not
  every word that looks the same, and its answers are much shorter than a text search.
- Search text only for strings, comments, and files clangd does not compile (resources, scripts,
  project files).
- If clangd seems to know nothing about the code, or answers as if for another configuration,
  check the database (below) before trusting it.

## After an edit

- Read the diagnostics clangd reports for the file and fix them before you build.
- Errors from inside the Windows SDK or the standard library (`no type named ... in 'std::...'`,
  "too many errors emitted") mean wrong compile flags, not wrong code. Run `lazymsbuild doctor`
  and report what it says instead of changing the code.

## Build and the database

- `lazymsbuild check --json`: whether the database is complete and current (`ok`, `stale`,
  `coverage`).
- `lazymsbuild sync`: refill the database without building.
- `lazymsbuild build --json`, optionally with `--target <project>` and `--profile "Debug|x64"`:
  build without the TUI. The errors are in the JSON, and the database follows the build.
- `lazymsbuild doctor`: check everything clangd needs.
- With several solutions in the repository, add `--solution <file>`.

Build through lazymsbuild rather than calling MSBuild yourself: it builds the `.sln` the way Visual
Studio does and keeps the database in step. Do not write `compile_commands.json` or `.clangd` by
hand. If `lazymsbuild` is not on `PATH`, say so; do not install anything.

## Encodings and line endings

- Keep every file's encoding and line endings. These projects often mix Shift_JIS (CP932) and
  UTF-8.
- Never convert a file to UTF-8 to make an edit possible. If your editing tool refuses a file that
  is not UTF-8, stop and ask the user how to make the change.
- To see the encodings in a tree (read-only), when `DOTFILES` is set:
  `pwsh -File "$env:DOTFILES\tools\Survey-Encoding.ps1" -Path <folder>`.

## Keep it local

- Do not send code, build logs, paths or project names from the repository to web searches, issue
  trackers or other online services.
