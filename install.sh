#!/usr/bin/env bash
set -e

# install.sh
#       Will install the deault environment in a computer with either OSX or Debian Linux

# Global vars
TIMESTAMP=`date -u +%Y%m%dT%H%M%SZ`
LOGFILE=${PWD}/install-$TIMESTAMP.log
USERNAME=$USER

# This is the list of packages that should be in your system or installed
# Note that in OSX Homebrew will always be insalled if not present
PACKAGES=('git' 'ansible')
PACMAN=""
PACMAN_OPTS=""

LOCATOR="which"

function check_install_brew () {
    ${LOCATOR} brew 2>&1 > /dev/null
    if [[ $? -ne 0 ]]; then
        printf "brew no está instalado. Se instalará..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        printf "\t%s %s\n" `brew -v`
    fi
}

install_packages () {
    ${PACMAN} update
    for p in "${PACKAGES[@]}"
    do
        printf "[EXEC] %s install %s %s\n" ${PACMAN} ${PACMAN_OPTS} ${p}
        ${PACMAN} install ${PACMAN_OPTS} ${p}
    done

    printf "\n[\033[32mOK\033[0m] System requirements installed!\n"
}

function main() {
	# Select OS
	case `uname` in
	'Darwin')
		THIS_OS="darwin"
        THIS_ARQ=`uname -m`
	;;
	'Linux')
		THIS_OS="linux"
        THIS_ARQ=`uname -m`
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
                PACMAN_OPTS="-y --no-install-recommends"
                ${PACMAN} update
                ${PACMAN} install ${PACMAN_OPTS} software-properties-common
                add-apt-repository --yes --update ppa:ansible/ansible
                ;;
            "Debian")
                PACMAN="apt"
                PACMAN_OPTS="-y --no-install-recommends"
                # https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html#installing-ansible-on-debian
                UBUNTU_CODENAME="jammy"
                wget -O- "https://keyserver.ubuntu.com/pks/lookup?fingerprint=on&op=get&search=0x6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367" | sudo gpg --dearmour -o /usr/share/keyrings/ansible-archive-keyring.gpg
                echo "deb [signed-by=/usr/share/keyrings/ansible-archive-keyring.gpg] http://ppa.launchpad.net/ansible/ansible/ubuntu $UBUNTU_CODENAME main" | sudo tee /etc/apt/sources.list.d/ansible.list
                ;;
            *)
                echo "[\033[31mERROR\033[0m] Cannot determine your Linux distro. lsb_release -is = ${`lsb_release -is`}"
                ;;
        esac
    elif [[ ${THIS_OS} == "darwin" ]]; then
        PACMAN="brew"
    else
        echo "[\033[31mERROR\033[0m] Unknown Operating System. Aborting!"
        exit 1
	fi

	printf "Installation started at %s\n" $TIMESTAMP
	printf "\tOS: %s %s\n" $THIS_OS $THIS_ARQ
	printf "\tUSERNAME: %s\n" $USERNAME
	printf "\tHOME DIR: %s\n" $HOME
	
    # Prepare Ansible install
    check_install_brew || exit 1
    install_packages || exit 1

    # Launch ansible-pull
    ansible-pull -U https://github.com/jllopis/despertaferro.git
}

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until script has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Start
main "$@"
