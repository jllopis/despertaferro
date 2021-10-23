despertaferro. My dot Files Repository
======================================

This scripts is an easy way of getting my dotfiles in order whenever I need to reinstall in a new computer.

It supports automatic installation (default) or interactive mode (asking for every package that should be installed).

It also works for OSX or Linux (Fedora based distro).

# Stuff #

By now, the script installs:

- Vim files: _.vimrc_, _.vim_ directory with bundles managed via **pathogen**.
- Git config: .gitconfig at user _$HOME_. It also set default ignores.
- Bash: _.bashrc_, _.bash_profile_, _bash\_completion, under OSX.
- Tmux: _.tmux.conf_.
More to come...

# How to use #

Easy. Just run

    curl https://raw.github.com/jllopis/despertaferro/master/install.sh | bash

it will install in your _$HOME_ directory.

Obviously this script only works under an Un*x brand of operating system. 
Has been tested with:
- Mac OS X v10.8.3 (Mountain Lion)
- Fedora core 18

# Notice #

This script is meant to manage **my** preferences so it is somewhat self-custom. Anyway, if somebody find it useful I'll be happy for it.
