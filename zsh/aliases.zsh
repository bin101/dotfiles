# ALIAS {{{
    # AUTOCOLOR {{{
        alias dir='dir --color=auto'
        alias vdir='vdir --color=auto'
        alias grep='grep --color=auto'
        alias fgrep='fgrep --color=auto'
        alias egrep='egrep --color=auto'
    #}}}
    # MODIFIED COMMANDS {{{
        alias ..='cd ..'
        alias df='df -h'
        alias diff='colordiff'              # requires colordiff package
        alias du='du -c -h'
        alias free='free -m'                # show sizes in MB
        alias grep='grep --color=auto'
        alias grep='grep --color=tty -d skip'
        alias mkdir='mkdir -p -v'
        alias more='less'
        alias nano='nano -w'
        alias ssh="TERM=xterm-256color ssh"
    #}}}
    # GIT ALIASES {{{
        alias add="git add"
        alias commit="git commit"
        alias pull="git pull"
        alias stat="git status"
        alias gdiff="git diff HEAD"
        alias vdiff="git difftool HEAD"
        alias log="git log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
        alias push="git push"
    #}}}
    # HOMEBREW ALIASES {{{
        alias bb="brew upgrade && brew cu --include-mas && brew cleanup"
        alias brewfile='brew bundle dump --file=~/.dotfiles/Brewfile --force'
    #}}}
    # LS {{{
        alias ls='eza -hg --git -o --icons'
        alias lr='ls -TR'                    # recursive ls
        alias ll='ls -l'
        alias la='ll -a'
        alias lm='la | less'
    #}}}
    # YABAI {{{
        alias showappnames='yabai -m query --windows | jq ".[].app"'
    #}}}
    # MISC {{{
        alias enter_matrix='echo -e "\e[32m"; while :; do for i in {1..16}; do r="$(($RANDOM % 2))"; if [[ $(($RANDOM % 5)) == 1 ]]; then if [[ $(($RANDOM % 4)) == 1 ]]; then v+="\e[1m $r   "; else v+="\e[2m $r   "; fi; else v+="     "; fi; done; echo -e "$v"; v=""; done'
        alias server-update="ansible-playbook -i ~/Repos/ansible/host.yml ~/Repos/ansible/playbooks/updateall.yml"
        alias server-init="ansible-playbook -i ~/Repos/ansible/host.yml ~/Repos/ansible/playbooks/setup.yml"
        alias server-migrate-history="ansible-playbook -i ~/Repos/ansible/host.yml ~/Repos/ansible/playbooks/migrateHistory.yml"
        alias switchgpgkey="gpg-connect-agent 'scd serialno' 'learn --force' /bye"
        alias pacdiff="sudo DIFFPROG=meld pacdiff"
        alias ranger=". ranger"
    #}}}
#}}}



