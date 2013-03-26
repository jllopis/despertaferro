#!/usr/bin/env bash

INSTALL_DIR=`pwd`
TIMESTAMP=`date +%Y%m%d%H%M%S`

# Include files
if [[ -r "colors.sh" ]]; then source colors.sh; fi


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
echo -e "${yellow}\tStarted at `date +%Y-%m-%dT%H:%M:%S`${text_reset}"
echo ""


