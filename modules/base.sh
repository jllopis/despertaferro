DISTRO=`lsb_release -i | cut -f 2`
INSTALLER=""
case "${DISTRO}" in
    "Ubuntu" | "Debian")
        INSTALLER="apt"
        ;;
esac
BASE_PKGS=( 
    curl
    ${AG}
)

function install_base_pkgs() {
    local AG
    case "${DISTRO}" in
        "Ubuntu" | "Debian")
            AG="silversearcher-ag"
            ;;
    esac

    echo "INSTALLING Base Packages"
    for pkg in ${BASE_PKGS[*]}; do
        #${INSTALLER} install --only-upgrade $pkg
        ${INSTALLER} install $pkg
    done
}

function do_system_upgrade() {
    case "${DISTRO}" in
        "Ubuntu" | "Debian")
            ${INSTALLER} update --silent && ${INSTALLER} upgrade --silent
            ;;
        *)
            echo "Don't know how to upgrade system!"
            ;;
    esac
}

do_system_upgrade

