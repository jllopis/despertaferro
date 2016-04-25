#!/usr/bin/env bash
set -e

# install.sh
#       Will install the deault environment in a computer with either OSX or Ubuntu Linux

# Global vars
TIMESTAMP=`date -u +%Y%m%dT%H%M%SZ`
LOGFILE=${PWD}/install-$TIMESTAMP.log
USERNAME=$USER
MODULES=()

# Include files
if [[ -r "envars.sh" ]]; then source envars.sh; fi
if [[ -r "colors.sh" ]]; then source colors.sh; fi
if [[ -r "functions.sh" ]]; then source functions.sh; else log_error "functions.sh not found. Can't continue :("; exit 1; fi

# This is the list of packages that should be in your system or installed
# Note that in OSX Homebrew will always be insalled if not present
PACKAGES=('git' 'ctags' 'tmux')
FILES=`find despertaferro -maxdepth 1 -type f -exec basename {} \;`
DIRS=`find despertaferro -maxdepth 1 -type d -exec basename {} \;`
DOTDIRS=()
DIRS2BACK=()
DIRISLINK=()
DOTFILES=()
FILES2BACK=()
FILEISLINK=()

function main() {
	# Select OS
	case `uname` in
	'Darwin')
		THIS_OS="darwin"
	;;
	'Linux')
		THIS_OS="linux"
	;;
	*)
		echo "${failure}Unrecognized OS. Aborting${text_reset}"
		exit 1
	;;
	esac

	if [[ ${THIS_OS} == "osx" ]]; then
		LOCATOR="which -s"
	else
		LOCATOR="type -p"
	fi

	# Load modules
	for mod in $(ls -A1 modules/*.sh); do
		if [[ -r ${mod} ]]; then
			log "Loading module ${mod}"
			source ${mod}
			mod=$(basename ${mod})
			mod=${mod%.*}
			MODULES+=(mod)
		fi
	done
	
	local cmd=$1

	if [[ -z "$cmd" ]]; then
		cmd="new"
	fi

	log "Installation started at $TIMESTAMP"
	log "${information}OS: ${package}$THIS_OS${text_reset}"
	log "${information}USERNAME: ${package}$USERNAME${text_reset}"
	log "${information}HOME DIR: ${package}$HOME${text_reset}"
	log "${information}INSTALL DIR: ${package}$INSTALL_DIR${text_reset}"
	
	if [[ -r "modules/${cmd}.sh" ]]; then
		source modules/${cmd}.sh;
		install_${cmd} "${@:2}"
	else
		log_err "command \"$cmd\" not recognized"
		show_help
		exit 1
	fi

	# TODO. Copy despertaferro to $HOME/.despertaferro
	
#	# Backup files and dirs
#	backup_dotfiles
#	
#	# Delete files and directories
#	clean_old
#	
#	# Configure OS
#	if [[ "$THIS_OS" == "osx" ]]; then configure_osx; fi
#	
#	# Install packages
#	install_or_update
#	
#	# Update submdules
#	vim_install_submodules
#	
#	# Link files
#	link_dotfiles
	
	echo ""
	log_ok "${despertaferro} ${success}is now installed."
}

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until `.osx` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Start
main "$@"
