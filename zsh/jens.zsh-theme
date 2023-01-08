# 25 Oct 2017 - bin101

# VCSq
YS_VCS_PROMPT_PREFIX1="%{$fg_bold[white]%}on%{$reset_color%} "
YS_VCS_PROMPT_PREFIX2=":%{$fg_bold[cyan]%}"
YS_VCS_PROMPT_SUFFIX="%{$reset_color%}%{$FX[bold]%} "
YS_VCS_PROMPT_DIRTY=" %{$fg_bold[red]%}✗"
YS_VCS_PROMPT_CLEAN=" %{$fg_bold[green]%}✔︎"

# Git info.
local git_info='$(git_prompt_info)'
local git_last_commit='$(git log --pretty=format:"%h \"%s\"" -1 2> /dev/null)'
ZSH_THEME_GIT_PROMPT_PREFIX="${YS_VCS_PROMPT_PREFIX1}%{$FX[bold]%}git${YS_VCS_PROMPT_PREFIX2}"
ZSH_THEME_GIT_PROMPT_SUFFIX="$YS_VCS_PROMPT_SUFFIX"
ZSH_THEME_GIT_PROMPT_DIRTY="$YS_VCS_PROMPT_DIRTY"
ZSH_THEME_GIT_PROMPT_CLEAN="$YS_VCS_PROMPT_CLEAN"

# Custom Colors
local BLUE="%{$FG[033]%}"
local LIGHTBLUE="%{$FG[081]%}"
local GREY="%{$FG[242]%}"
local PURPLE="%{$FG[161]%}"
local RED="%{$FG[196]%}"
local YELLOW="%{$FG[214]%}"

# Prompt format:
# TIME [USER@MACHINE:DIRECTORY] on git:BRANCH STATE
# PRIVILEGES> COMMAND

#%B${RED}%T \

PROMPT="\
%B${GREY}[\
%(!.%{$BG[196]%}.)${YELLOW}%n%{$reset_color%}%B\
${GREY}@\
${PURPLE}%m\
${GREY}:\
${BLUE}%~\
${GREY}] %{$reset_color%}\
${git_info}\
${git_last_commit}
%{$terminfo[bold]$fg_bold[white]%}%#› %{$reset_color%}"
