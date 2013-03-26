# Color definition for the shell

######################################################################################
# ANSI COLORS - To be used in every script
#
# echoed using escape and [, then color and attr combination followed by letter 'm'
# then the text.
# Reset by usign \033[0m
#Color	Foreground	Background
#Black 	   30 	            40
#Red 	   31 	            41
#Green 	   32 	            42
#Yellow    33 	            43
#Blue 	   34 	            44
#Magenta   35 	            45
#Cyan 	   36 	            46
#white 	   37 	            47

# Attributes
#ANSI CODE	Meaning
#   0           Normal Characters
#   1           Bold Characters
#   4           Underlined Characters
#   5           Blinking Characters
#   7           Reverse video Characters

# Summary
#Bold off	color           Bold on    color
#0;30           Black           1;30       Dark Gray
#0;31           Red             1;31       Dark Red
#0;32           Green           1;32       Dark Green
#0;33           Brown           1;33       Yellow
#0;34           Blue            1;34       Dark Blue
#0;35           Magenta         1;35       Dark Magenta
#0;36           Cyan            1;30       Dark Cyan
#0;37           Light Gray      1;30       White


# And the tput variant...
if tput setaf 1 &> /dev/null; then
  text_reset=$(tput sgr0)
  underline=$(tput sgr 0 1)
  bold=$(tput bold)
  if [[ $(tput colors) -ge 256 ]] 2>/dev/null; then
    red=$(tput setaf 160)
    green=$(tput setaf 76)
    yellow=$(tput setaf 178)
    blue=$(tput setaf 23)
    magenta=$(tput setaf 5)
    cyan=$(tput setaf 60)
    white=$(tput setaf 7)
    orange=$(tput setaf 172)
    purple=$(tput setaf 141)
    grey=$(tput setaf 238)
  else
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    yellow=$(tput setaf 3)
    blue=$(tput setaf 4)
    magenta=$(tput setaf 5)
    cyan=$(tput setaf 6)
    white=$(tput setaf 7)
    orange=$(tput setaf 3)
    purple=$(tput setaf 1)
    grey=$(tput setaf 7)
  fi
else
  text_reset="\033[0m"
  underline="\033[4m"
  bold="\033[1m"
  red="\033[31m"
  green="\033[32m"
  yellow="\033[33m"
  blue="\033[34m"
  magenta="\033[35m"
  cyan="\033[36m"
  white="\033[37m"
  orange="\033[33m"
  purple="\033[31m"
  grey="\033[37m"
fi

bold_magenta=${bold}${magenta}
bold_red=${bold}${red}
bold_green=${bold}${green}
bold_orange=${bold}${orange}
bold_blue=${bold}${blue}
bold_yellow=${bold}${yellow}
bold_white=${bold}${white}
bold_grey=$bold${grey}

notice=$text_reset$bold_blue
success=$text_reset$bold_green
failure=$text_reset$bold_red
attention=$text_reset$bold_orange
information=$text_reset$bold_grey

package=$text_reset$bold_orange
component=$text_reset$bold_yellow
filename=$text_reset$underline$white
despertaferro="$text_reset$bold$(tput setaf 203)Desperta Ferro$text_reset"

