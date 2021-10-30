despertaferro. My dot Files Repository
======================================

This repo contains my dot files as I use them. DO NOT USE WITHOUTH REVIEW THEM FIRST! You've been warned.

The installation uses `ansible-pull` so it gets installed if you run the `install.sh` script.

*****Achtung!**

The installation procedure takes no prisoners. If you have the files in your computer they **will be overwritten** and
the process can not be reverted.

Use with care.

# Stuff

There are a couple things that I use every day and gets installed and configured:

- NeoVim and its config files: installed in `~/.config/nvim`
- Git config: .gitconfig at user _$HOME_. It also set default global ignore file.
- ZSH: _.zshrc_, and the config files and plugins in `~/.config/zsh`. It also installs and config `powerlevel10k` theme.
- Tmux: _.tmux.conf_.
- Some util and development packages

More to come...

# How to use

Easy. Just run

    curl https://raw.githubusercontent.com/jllopis/despertaferro/master/install.sh | DESPERTA_GIT_NAME="Joan Llopis" \
        DESPERTA_GIT_EMAIL="jllopis@mail.cat"\
        bash

and it will install the config in the _$HOME_ directory of the running user.

The two environment variables are used to set you user and email in git global config.

# Supported OSs

The configuration and setup procedure Has been tested with:

- Ubuntu 20.04 LTS

# Notice

This dot files and configuration are **my** preferences so it is both, customized and heavily opinionated. Anyway, if somebody find it useful I'll be happy for it.
