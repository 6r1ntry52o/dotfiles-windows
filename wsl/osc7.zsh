# Sourced from ~/.zshrc inside WSL (the line is added by wsl/install.sh).
# Tell WezTerm the current directory on every prompt (OSC 7), so that new tabs
# and splits open where you are instead of going back to ~.
__wezterm_osc7() {
  printf '\033]7;file://%s%s\033\\' "$HOST" "$PWD"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd __wezterm_osc7

# Aliases shared with bash (this file is the one line ~/.zshrc loads)
[ -f "${0:A:h}/aliases.sh" ] && . "${0:A:h}/aliases.sh"
