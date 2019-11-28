#!/bin/bash

# set some printing colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;36m'
NC='\033[0m'

shell=$(basename $SHELL)
engine="docker"
packagemanager="dnf"
local=false
which podman >/dev/null 2>&1 && engine="podman"
which $engine >/dev/null 2>&1
if [ "$?" != "0" ] ; then
  echo -e "${BLUE}No container engine found. Leaving${NC}"
fi
which kcli-openshift4 >/dev/null 2>&1
BIN="$?"
alias kcli-openshift4 >/dev/null 2>&1
ALIAS="$?"

if [ "$BIN" != "0" ] && [ "$ALIAS" != "0" ]; then
  echo -e "${BLUE}Installing as alias for $engine${NC}"
  $engine pull docker.io/karmab/kcli-openshift4:latest
  SSHVOLUME="-v $(realpath $HOME/.ssh):/root/.ssh"
  if [ -d /var/lib/libvirt/images ] && [ -d /var/run/libvirt ]; then
      echo -e """${BLUE}Make sure you have libvirt access from your user by running:
sudo usermod -aG qemu,libvirt $(id -un)
newgrp qemu
newgrp libvirt${NC}"""
      VOLUMES="-v /var/lib/libvirt/images:/var/lib/libvirt/images -v /var/run/libvirt:/var/run/libvirt"
  fi
  [ -d $HOME/.kcli ] || mkdir -p $HOME/.kcli
  [ -d $HOME/.ssh  ] || ssh-keygen -t rsa -N '' -f $HOME/.ssh/id_rsa
case $shell in
bash|zsh)
  shellfile="$HOME/.bashrc"
  [ "$shell" == zsh ] && shellfile="$HOME/.zshrc" 
  grep -q kcli-openshift4= $shellfile || echo alias kcli-openshift4=\'$engine run --net host -it --rm --security-opt label=disable -v $HOME/.kcli:/root/.kcli $SSHVOLUME $VOLUMES '-v $PWD:/workdir -v /var/tmp:/ignitiondir karmab/kcli-openshift4'\' >> $shellfile
  alias kcli-openshift4="$engine run --net host -it --rm --security-opt label=disable -v $HOME/.kcli:/root/.kcli $SSHVOLUME $VOLUMES -v $PWD:/workdir -v /var/tmp:/ignitiondir karmab/kcli-openshift4"
  ;;
fish)
  shellfile="$HOME/.config/fish/config.fish"
  [ ! -d ~/.config/fish ] && mkdir -p ~/.config/fish
  grep -q 'kcli-openshift4 ' $shellfile || echo alias kcli-openshift4 $engine run --net host -it --rm --security-opt label=disable -v $HOME/.kcli:/root/.kcli $SSHVOLUME $VOLUMES '-v $PWD:/workdir -v /var/tmp:/ignitiondir karmab/kcli-openshift4' >> $shellfile
  alias kcli-openshift4 $engine run --net host -it --rm --security-opt label=disable -v $HOME/.kcli:/root/.kcli $SSHVOLUME $VOLUMES -v $PWD:/workdir -v /var/tmp:/ignitiondir karmab/kcli-openshift4
  ;;
*)
  echo -e "${RED}Installing aliases for $shell is not supported :(${NC}"
  ;;
esac
  shopt -s expand_aliases
  echo -e """${GREEN}Installed kcli-openshift4
Launch a new shell for alias kcli-openshift4 to work${NC}"""
else
  echo -e "${BLUE}Skipping already installed kcli-openshift4${NC}"
fi
