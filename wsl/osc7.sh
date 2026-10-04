# Sourced from ~/.bashrc inside WSL (the line is added by wsl/install.sh).
# Tell WezTerm the current directory on every prompt (OSC 7), so that new tabs
# and splits open where you are instead of going back to ~.
__wezterm_osc7() {
  printf '\033]7;file://%s%s\033\\' "$HOSTNAME" "$PWD"
}

case ";${PROMPT_COMMAND:-};" in
  *";__wezterm_osc7;"*) ;;
  *) PROMPT_COMMAND="__wezterm_osc7${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac

# Aliases shared with zsh (this file is the one line ~/.bashrc loads)
[ -f "${BASH_SOURCE[0]%/*}/aliases.sh" ] && . "${BASH_SOURCE[0]%/*}/aliases.sh"
