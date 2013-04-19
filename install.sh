#!/usr/bin/env bash

INSTALL_DIR=`pwd`
TIMESTAMP=`date -u +%Y%m%dT%H%M%SZ`
LOGFILE=$INSTALL_DIR/install-$TIMESTAMP.log
# This is the list of packages that should be in your system or installed
# Note that in OSX Homebrew will always be insalled if not present
PACKAGES=('git' 'ctags' 'vim' 'tmux' 'go')
FILES=`find despertaferro -type f -maxdepth 1 -exec basename {} \;`
DIRS=`find despertaferro -type d -maxdepth 1 -exec basename {} \;`
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
log_ok "${despertaferro} ${success}is now installed."
