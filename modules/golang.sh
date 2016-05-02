# Default options for go
GO_INSTALLED=0
INSTALLED_GO_VERSION='Unk'
INSTALLED_GO_PLATFORM='Unk'
REQUIRED_GO_VERSION=${GO_VERSION:-go1.6}
REQUIRED_GO_ARCH=${GO_ARCH:-amd64}
REQUIRED_GO_OS=${GO_OS:-$THIS_OS}

function is_go_installed() {
	GO_PATH=$(${LOCATOR} go || echo "")
	if [ -z ${GO_PATH} ]; then
		INSTALLED_GO_VERSION=""
		GO_INSTALLED=0
	fi
	INSTALLED_GO_VERSION=$(${GO_PATH} version | cut -d ' ' -f 3)
	INSTALLED_GO_PLATFORM=$(${GO_PATH} version |cut -d ' ' -f 4 |tr '/' '-')
	GO_INSTALLED=1
}

function install_golang() {
	local promote
	if [ ${THIS_OS} == "linux" ]; then promote=sudo; fi
	
	# Check if go is already installed
	is_go_installed
	if [[ $GO_INSTALLED -eq 1 ]]; then
		log_warn "${notice}Go ${INSTALLED_GO_VERSION}.${INSTALLED_GO_PLATFORM} already installed.${text_reset}"
		if [ "$1" == "-u" ]; then
			log_warn "Updating additional go packages. Go will not be reinstalled"
			golang_additional
			exit 0
		fi
		# ask for reinstall (all version will be removed)
		read -r -p "${attention}Remove and install ${REQUIRED_GO_VERSION}? (y/n) ${text_reset}" resp
		if [[ $resp =~ ^(s|S|y|Y)$ ]]
		then
			echo -e "${bold_red}Removing installed version...${text_reset}"
			if [ -d ${GO_ROOT} ]; then ${promote} rm -rf ${GOROOT}; fi
			echo -e "${bold_red}Installing ${REQUIRED_GO_VERSION}.${REQUIRED_GO_OS}-${REQUIRED_GO_ARCH}${text_reset}"
		else
			echo -e "${attention}Aborting!${text_reset}"
			exit
		fi
	else
		if [[ -d /usr/local/go ]]; then
			echo -e "${attention}Go executable not found but directory /usr/local/go exists. If you continue, it will be removed!${text_reset}"
			read -r -p "${attention}Continue? (y/n) ${text_reset}" resp
			if [[ $resp =~ ^(s|S|y|Y)$ ]]; then
				echo -ne "${notice}Deleting /usr/local/go}..."
				${promote} rm -rf /usr/local/go
				echo -ne "${notice}/usr/local/go deleted${text_reset}"
			else
				exit
			fi
		else
			echo -e "${notice}Go not installed. Installing ${REQUIRED_GO_VERSION}${text_reset}"
		fi
	fi

	# install from https://golang.org/dl/ either osx pkg or linux tgz
	curl -sL https://golang.org/dl/${REQUIRED_GO_VERSION}.${REQUIRED_GO_OS}-${REQUIRED_GO_ARCH}.tar.gz | gunzip | ${promote} tar -C /usr/local -xf -
	echo -e "${attention}${REQUIRED_GO_VERSION}.${REQUIRED_GO_OS}-${REQUIRED_GO_ARCH} installed!${text_reset}"

	golang_additional
}

function golang_additional() {
	local packages
	packages=(
		github.com/golang/lint/golint
		golang.org/x/tools/cmd/cover
		golang.org/x/tools/cmd/goimports
		github.com/tools/godep
)

	(
	#set -x
	#set +e
	for p in ${packages[@]}; do
		log "Installing go package ${p}"
		go get -u ${p}
	done
	)
}

function golang_help() {
	echo "Install golang version ${REQUIRED_GO_VERSION} and additional packages. -u update additional packages"
}
