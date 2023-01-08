# path
export PATH=$PATH:$HOME/.bin

# zsh base dir
export ZSH_BASE=$HOME/.zsh

# brew completions
FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
export HOMEBREW_NO_ENV_HINTS=TRUE

# antidote
# Clone antidote if necessary.
[[ -e ${ZDOTDIR:-~}/.antidote ]] ||
  git clone https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
# Source antidote.
source ${ZDOTDIR:-~}/.antidote/antidote.zsh
# Load plugins
antidote load

# Load the theme.
#source $ZSH_BASE/jens.zsh-theme
eval "$(starship init zsh)"
[ -f ~/.starship.zsh ] && source ~/.starship.zsh

# Source additional config
source $ZSH_BASE/aliases.zsh
source $ZSH_BASE/functions.zsh

# GPG config
export GPG_TTY="$(tty)"
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
gpgconf --launch gpg-agent

# fuzzy search
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# set config dir for i.e. lazygit
export XDG_CONFIG_HOME="$HOME/.config"
export EDITOR="$(which vim)"
export VISUAL="$(which vim)"
export MANPAGER="$(which vim) -c ASMANPAGER -"

# history optimize
export HISTSIZE=1000000
export SAVEHIST=$HISTSIZE
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_FIND_NO_DUPS
