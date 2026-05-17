alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# Git
alias g='git'
alias gs='git status'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate -20'

# Tools
command -v eza &>/dev/null && alias ls='eza' && alias ll='eza -lah' && alias la='eza -A'
command -v bat &>/dev/null && alias cat='bat'
command -v rg  &>/dev/null && alias grep='rg'

# Directories
alias cfg='cd $XDG_CONFIG_HOME'
alias dot='cd ${DESPERTA_REPO:-$HOME/.local/share/despertaferro}'
