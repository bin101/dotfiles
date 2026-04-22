# path
typeset -U path
path=(
  "$HOME/.bin"
  "$HOME/.local/bin"
  "$HOME/tizen-studio/tools/ide/bin"
  "$HOME/tizen-studio/tools"
  $path
)
export PATH

# zsh base dir
export ZSH_BASE=$HOME/.zsh

# Optional startup profiling: run `ZSH_PROFILE=1 zsh -i -c exit`
if [[ "${ZSH_PROFILE:-0}" == "1" ]]; then
  zmodload zsh/zprof
fi

# brew completions
if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then
  FPATH="${HOMEBREW_PREFIX}/share/zsh/site-functions:${FPATH}"
fi
export HOMEBREW_NO_ENV_HINTS=TRUE
export HOMEBREW_DOWNLOAD_CONCURRENCY=auto

# antidote
# Clone antidote if necessary.
[[ -e ${ZDOTDIR:-~}/.antidote ]] ||
  command git clone https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
# Source antidote.
source ${ZDOTDIR:-~}/.antidote/antidote.zsh
# Build and source a static plugin bundle for faster startup.
_zsh_plugins_file=${ZDOTDIR:-$HOME}/.zsh_plugins.txt
_zsh_plugins_bundle=${ZDOTDIR:-$HOME}/.zsh_plugins.zsh
if [[ -f "$_zsh_plugins_file" ]]; then
  if [[ ! -f "$_zsh_plugins_bundle" || "$_zsh_plugins_bundle" -ot "$_zsh_plugins_file" ]]; then
    antidote bundle <"$_zsh_plugins_file" >|"$_zsh_plugins_bundle"
  fi
  source "$_zsh_plugins_bundle"
else
  antidote load
fi
unset _zsh_plugins_file _zsh_plugins_bundle

# Load the theme.
#source $ZSH_BASE/jens.zsh-theme
# Defer Starship init until after first prompt (lazy load via precmd hook)
_init_starship() {
  if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
  fi
  [ -f ~/.starship.zsh ] && source ~/.starship.zsh
  # Remove hook after first run
  precmd_functions=("${(@)precmd_functions:#_init_starship}")
}
precmd_functions+=(_init_starship)

# Source additional config
source "$ZSH_BASE/aliases.zsh"
source "$ZSH_BASE/functions.zsh"

# GPG config
if command -v gpgconf >/dev/null 2>&1; then
  export GPG_TTY="$(tty)"
  export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
  gpgconf --launch gpg-agent >/dev/null 2>&1
fi

# fuzzy search
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# set config dir for i.e. lazygit
export XDG_CONFIG_HOME="$HOME/.config"
if command -v vim >/dev/null 2>&1; then
  export EDITOR="vim"
  export VISUAL="vim"
  export MANPAGER="vim -c ASMANPAGER -"
else
  export EDITOR="vi"
  export VISUAL="vi"
fi

# history optimize
export HISTSIZE=1000000
export SAVEHIST=$HISTSIZE
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_FIND_NO_DUPS

# completions: use cache to speed up cold starts
autoload -Uz compinit
if [[ -f ~/.zcompdump ]]; then
  compinit -C
else
  compinit
fi

# pipx completion (lazy: only load on first pipx invocation)
if command -v register-python-argcomplete >/dev/null 2>&1; then
  _pipx_completion() {
    eval "$(register-python-argcomplete pipx 2>/dev/null)" || true
    unfunction _pipx_completion
  }
  # Hook into pipx command: initialize completion on first use
  pipx() {
    _pipx_completion
    command pipx "$@"
  }
fi

# QMK
export QMK_CONFIG="$HOME/.config/qmk/qmk.ini"


[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

if [[ "${ZSH_PROFILE:-0}" == "1" ]]; then
  zprof
fi
