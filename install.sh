#!/usr/bin/env bash
set -e

# install.sh
#       Will install the deault environment in a computer with either OSX or Ubuntu Linux
USERNAME=$USER
REQUIRED_GO_VERSION="go1.6"
REQUIRED_GO_ARCH="amd64"
REQUIRED_GO_OS="darwin"

TIMESTAMP=`date -u +%Y%m%dT%H%M%SZ`
LOGFILE=${PWD}/install-$TIMESTAMP.log
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

# 

# Include files
if [[ -r "envars.sh" ]]; then source envars.sh; fi
if [[ -r "colors.sh" ]]; then source colors.sh; fi
if [[ -r "functions.sh" ]]; then source functions.sh; else log_error "functions.sh not found. Can't continue :("; exit 1; fi

function is_go_installed() {
	GO_INSTALLED=$(which -s go; echo $?)
	if [ ${GO_INSTALLED} -eq 1 ]; then
		GO_VERSION=""
		return
	fi
	GO_PATH=`which go`
	GO_VERSION=`${GO_PATH} version | cut -d ' ' -f 3`
	GO_PLATFORM=`${GO_PATH} version |cut -d ' ' -f 4 |tr '/' '-'`
}

function install_golang() {
	# Check if go is already installed
	is_go_installed
	if [[ $GO_INSTALLED -eq 1 ]]; then
		if [[ -d /usr/local/go ]]; then
			echo -e "${attention}A directory /usr/local/go exist. If you continue, it will be removed!${reset}"
			read -r -p "${attention}Continue? (y/n) ${reset}" resp
			if [[ $resp =~ ^(s|S|y|Y)$ ]]
			then
				echo -ne "${notice}Deleting /usr/local/go}..."
				rm -rf /usr/local/go
				echo -ne "${notice}/usr/local/go deleted${reset}"
			else
				exit
			fi
		else
			echo -e "${notice}Go not installed. Installing ${REQUIRED_GO_VERSION}${reset}"
		fi
	else
		echo -e "${notice}Go ${GO_VERSION}.${GO_PLATFORM} already installed.${reset}"
		# ask for reinstall (all version will be removed
		read -r -p "${attention}Remove and reinstall? (y/n) ${reset}" resp
		if [[ $resp =~ ^(s|S|y|Y)$ ]]
		then
			echo -e "${bold_red}Removing installed version...${reset}"
			if [ -d ${GO_ROOT} ]; then rm -rf ${GOROOT}; fi
			echo -e "${bold_red}Reinstalling ${GO_VERSION}.${GO_PLATFORM}${reset}"
		else
			echo -e "${attention}Aborting!${reset}"
			exit
		fi
	fi

	# install from https://golang.org/dl/ either osx pkg or linux tgz
	curl -sL https://golang.org/dl/${REQUIRED_GO_VERSION}.${REQUIRED_GO_OS}-${REQUIRED_GO_ARCH}.tar.gz | gunzip | tar -C /usr/local -xf -
	echo -e "${attention}${REQUIRED_GO_VERSION}.${REQUIRED_GO_OS}-${REQUIRED_GO_ARCH} installed!${reset}"
}

function main() {
	# Select OS
	case `uname` in
	'Darwin')
		THIS_OS="osx"
		REQUIRED_GO_ARCH="amd64"
		REQUIRED_GO_OS="darwin"
	;;
	'Linux')
		THIS_OS="linux"
		REQUIRED_GO_ARCH="amd64"
		REQUIRED_GO_OS="linux"
	;;
	*)
		echo "${failure}Unrecognized OS. Aborting${text_reset}"
		exit 1
	;;
	esac
	
	local cmd=$1

	if [[ -z "$cmd" ]]; then
		cmd="new"
	fi

	echo -e "${despertaferro} ${information}Installation Variables:${text_reset}"
	echo -e "${information}OS:\t${package}$THIS_OS${text_reset}"
	echo -e "${information}USERNAME:\t${package}$USERNAME${text_reset}"
	echo -e "${information}HOME DIR:\t${package}$HOME${text_reset}"
	echo -e "${information}INSTALL DIR:\t${package}$INSTALL_DIR${text_reset}"
	echo ""
	log "Installation started at $TIMESTAMP"
	echo ""
	
	case $cmd in
	"golang")
		log "Installing Go"
		install_golang
		;;
	"new")
		log "Setting up a new computer"
		;;
	*)
		log_err "command \"$cmd\" not recognized"
		exit 1
		;;
	esac

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

# Start
#sudo -v
main "$@"
