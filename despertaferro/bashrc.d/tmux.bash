# Set this alias for the colors to work ok
#alias tmux="TERM=screen-256color-bce tmux"
alias tmux="TERM=xterm-256color tmux"

# Couple functions to better work with development sessions
# Works because bash automatically trims by assigning to variables and by 
# passing arguments
# From: https://mutelight.org/practical-tmux
trim() { echo $1; }

function mux_session_exist() {
  tmux has-session -t $1 2>/dev/null
  if [ "$?" -eq 1 ] ; then
    # No session
    return 0
  fi
  return 1
}

function mux_kill() {
  if [[ -z $TMUX ]]; then
    # We are not in a tmux session
    tmux kill-session -t $1
  else
    sess_name=$(tmux display-message -p '#S')
    tmux kill-session -t $sess_name
  fi
}

function mux() {
  echo -e "${information}Running session $1${text_reset}"
  if ( tmux has-session -t $1 2>/dev/null )
  then
    echo -e "${attention}$1 session exists. Attaching to it${text_reset}"
    tmux attach-session -t $1
    echo -e "${success}Done!${text_reset}"
  else
    # session does not exits. Create ...
    echo -e "${attention}Runnig tmux in a new session $1${text_reset}"
    tmux new-session -s $1
    echo -e "${success}Done!${text_reset}"
  fi
}

