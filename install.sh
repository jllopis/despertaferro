#!/usr/bin/env bash
set -e

# install.sh
#       Will install the deault environment in a computer with either OSX or Ubuntu Linux

# Global vars
TIMESTAMP=`date -u +%Y%m%dT%H%M%SZ`
LOGFILE=${PWD}/install-$TIMESTAMP.log
USERNAME=$USER

# This is the list of packages that should be in your system or installed
# Note that in OSX Homebrew will always be insalled if not present
PACKAGES=('git' 'ansible')
PACMAN=""

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

	if [[ ${THIS_OS} == "linux" ]]; then
		LOCATOR="which -s"
        case `lsb_release -is` in
            "Ubuntu")
                PACMAN="apt"
                ;;
            *)
                echo "[\033[31mERROR\033[0m] Cannot determine your Linux distro. lsb_release -is = ${`lsb_release -is`}"
                ;;
        esac
	else
		LOCATOR="type -p"
	fi

	printf "Installation started at %s\n" $TIMESTAMP
	printf "\tOS: %s\n" $THIS_OS
	printf "\tUSERNAME: %s\n" $USERNAME
	printf "\tHOME DIR: %s\n" $HOME
	
    # Prepare Ansible install
    sudo apt update
    sudo apt install software-properties-common
    sudo add-apt-repository --yes --update ppa:ansible/ansible

    # Install required packages
    for p in "${PACKAGES[@]}"
    do
        echo "[EXEC] sudo ${PACMAN} install -y ${p}"
        sudo $PACMAN install -y --no-install-recommends ${p}
    done

	echo ""
	printf "[\033[32mOK\033[0m] System requirements installed!"

    # Launch ansible-pull
    ansible-pull -U https://github.com/jllopis/despertaferro.git -C ansible-pull
}

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until `.osx` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Start
main "$@"
