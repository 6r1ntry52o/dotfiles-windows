#!/usr/bin/env bash
# Run inside WSL by install.ps1. Safe to re-run.
# Adds one line to ~/.bashrc (and to ~/.zshrc when zsh is installed) that
# sources osc7.sh / osc7.zsh from this clone.
set -eu

dir=$(cd "$(dirname "$0")" && pwd)
marker='# managed by dotfiles-windows/install.ps1'

link() {
  rc=$1
  src=$2
  line="[ -f \"$src\" ] && . \"$src\" $marker"

  touch "$rc"
  if grep -qxF "$line" "$rc"; then
    echo "ok       $rc"
    return
  fi

  # Drop a stale line (the repo was moved), then append the current one
  tmp=$(mktemp)
  grep -vF "$marker" "$rc" > "$tmp" || true
  printf '%s\n' "$line" >> "$tmp"
  cat "$tmp" > "$rc"
  rm -f "$tmp"
  echo "linked   $rc -> $src"
}

link "$HOME/.bashrc" "$dir/osc7.sh"
if command -v zsh > /dev/null; then
  link "$HOME/.zshrc" "$dir/osc7.zsh"
fi
