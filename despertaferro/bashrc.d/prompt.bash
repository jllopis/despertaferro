function __git_dirty {
  git diff --quiet HEAD &>/dev/null
  [ $? == 1 ] && echo "+"
}

function __git_branch {
  __git_ps1 " :: %s"
}

echo -e "${information}Setting up shell prompt"
export PS1="${bold_cyan}(\`go version | awk '{print \$3};'\`) ${yellow}\u@\h:${bold_blue}\w ${bold_white}\`__git_branch\`${bold_red}\`__git_dirty\` ${text_reset}
$ "

