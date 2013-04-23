case `uname` in
  'Darwin')
    # Brew git completion
    if [ -f `brew --prefix`/etc/bash_completion.d/git-completion.bash ]; then
      . `brew --prefix`/etc/bash_completion.d/git-completion.bash
    fi
    if [ -f `brew --prefix`/etc/bash_completion.d/git-prompt.sh ]; then
      . `brew --prefix`/etc/bash_completion.d/git-prompt.sh
    fi
    
    # Brew git-flow completion
    if [ -f `brew --prefix`/etc/bash_completion.d/git-flow-completion.bash ]; then
      . `brew --prefix`/etc/bash_completion.d/git-flow-completion.bash
    fi
  ;;
  'Linux')
    # git completion
    if [ -f /etc/bash_completion.d/git ]; then
      . /etc/bash_completion.d/git
    fi
    if [ -f /etc/bash_completion.d/git-prompt.sh ]; then
      . /etc/bash_completion.d/git-prompt.sh
    elif [ -f /usr/share/git-core/contrib/completion/git-prompt.sh ]; then
      . /usr/share/git-core/contrib/completion/git-prompt.sh
    fi
    
    # git-flow completion
    if [ -f /etc/bash_completion.d/git-flow-completion.bash ]; then
      . /etc/bash_completion.d/git-flow-completion.bash
    fi
  ;;
esac

