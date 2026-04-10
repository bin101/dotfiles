alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

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

alias bb="brew upgrade && brew cu --include-mas && brew cleanup"
alias brewfile='brew bundle dump --file=~/.dotfiles/Brewfile --force'

alias ls='eza -hg --git -o --icons'
alias lr='ls -TR'                    # recursive ls
alias ll='ls -l'
alias la='ll -a'
alias lm='la | less'

alias server-update="(cd ~/Repos/ansible && ansible-playbook playbooks/updateall.yml)"
alias server-setup="(cd ~/Repos/ansible && ansible-playbook playbooks/setup.yml)"
alias server-migrate="(cd ~/Repos/ansible && ansible-playbook playbooks/migrateHistory.yml)"

alias apiDump="./gradlew updateLegacyAbi"
alias testDebug="./gradlew testDebugUnitTest"
alias kd="./gradlew detekt --auto-correct ktlint"

alias switchgpgkey="gpg-connect-agent 'scd serialno' 'learn --force' /bye"
alias ranger=". ranger"
alias restartaudio="sudo launchctl kickstart -k system/com.apple.audio.coreaudiod"
alias disable-autoboot="sudo nvram BootPreference=%00"
