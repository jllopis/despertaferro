#!/usr/bin/env bash

INSTALL_DIR=`pwd`
TIMESTAMP=`date -u +%Y%m%dT%H%M%SZ`
LOGFILE=$INSTALL_DIR/install-$TIMESTAMP.log
# This is the list of packages that should be in your system or installed
# Note that in OSX Homebrew will always be insalled if not present
PACKAGES=('git' 'ctags' 'vim' 'tmux' 'go')
FILES=`find despertaferro -maxdepth 1 -type f -exec basename {} \;`
DIRS=`find despertaferro -maxdepth 1 -type d -exec basename {} \;`
DOTDIRS=()
DIRS2BACK=()
DIRISLINK=()
DOTFILES=()
FILES2BACK=()
FILEISLINK=()

# Include files
if [[ -r "colors.sh" ]]; then source colors.sh; fi
if [[ -r "functions.sh" ]]; then source functions.sh; else log_error "functions.sh not found. Can't continue :("; exit 1; fi

# Start
sudo -v

# Select OS
case `uname` in
 'Darwin')
    THIS_OS="osx"
    ;;
  'Linux')
    THIS_OS="linux"
    ;;
  *)
    echo "${failure}Unrecognized OS. Aborting${text_reset}"
    exit 1
    ;;
esac

echo -e "${despertaferro} ${information}installation on ${package}$THIS_OS${text_reset}"
echo ""
log "Installation started at $TIMESTAMP"
echo ""

# TODO. Copy despertaferro to $HOME/.despertaferro

# Backup files and dirs
backup_dotfiles

# Delete files and directories
clean_old

# Configure OS
if [[ "$THIS_OS" == "osx" ]]; then configure_osx; fi

# Install packages
install_or_update

# Update submdules
vim_install_submodules

# Link files
link_dotfiles

echo ""
echo -e "${despertaferro} ${attention}uses the gem ${component}teamocil${attention} to manage"
echo -e "tmux sessions. Right now, it is not installed by default. If you want session support, "
echo -e "remember to install the gem:"
echo ""
echo -e "             ${bold_white}gem install teamocil${text_reset}"
echo ""

echo ""
log_ok "${despertaferro} ${success}is now installed."
