echo -e "${information}Loading Homebrew bash completion${text_reset}"
# Brew bash completion
if [ -f `brew --prefix`/etc/bash_completion.d/brew_bash_completion.sh ]; then
  . `brew --prefix`/etc/bash_completion.d/brew_bash_completion.sh
fi

