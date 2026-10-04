# Sourced from osc7.sh (bash) and osc7.zsh (zsh). Keep it POSIX so both can read it.
# vi / vim / view open Neovim (only when nvim is installed in this distro).
if command -v nvim > /dev/null 2>&1; then
  alias vi='nvim'
  alias vim='nvim'
  alias view='nvim -R'
fi
