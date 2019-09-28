#!/bin/bash

# set some printing colors
RED='\033[0;31m'
BLUE='\033[0;36m'
NC='\033[0m'

which kcli >/dev/null 2>&1
BIN="$?"
alias kcli >/dev/null 2>&1
ALIAS="$?"

if [ "$BIN" != "0" ] && [ "$ALIAS" != "0" ]; then
  engine="docker"
  which podman >/dev/null 2>&1 && engine="podman"
  VOLUMES=""
  [ -d /var/lib/libvirt/images ] && [ -d /var/run/libvirt ] && VOLUMES="-v /var/lib/libvirt/images:/var/lib/libvirt/images -v /var/run/libvirt:/var/run/libvirt"
  [ -d $HOME/.kcli ] || mkdir -p $HOME/.kcli
  alias kcli="$engine run --net host -it --rm --security-opt label=disable -v $HOME/.kcli:/root/.kcli $VOLUMES -v $PWD:/workdir -v /tmp:/ignitiondir karmab/kcli"
  echo -e "${BLUE}Using $(alias kcli)${NC}"
fi

shopt -s expand_aliases
kcli -v >/dev/null 2>&1
if [ "$?" != "0" ] ; then
  echo -e "${RED}kcli not found. Install it from copr karmab/kcli or pull container${NC}"
  exit 1
fi

client=$(kcli list --clients | grep X | awk -F'|' '{print $2}' | xargs)
echo -e "${BLUE}Scaling on client $client${NC}"
kcli="kcli -C $client"
alias kcli >/dev/null 2>&1 && kcli=$(alias kcli | awk -F "'" '{print $2}')" -C $client"

if [ "$#" -lt '1' ] || [ "$#" -gt '2' ] ; then
    echo -e "${RED}Usage: $0 [\$parameter_file] \$num_workers ${NC}"
    exit 1
elif [ "$#" == '2' ]; then
  envname="$1"
  paramfile="$1"
  workers="$2"
  if [ ! -f $paramfile ]; then
    echo -e "${RED}Specified parameter file $paramfile doesn't exist.Leaving...${NC}"
    exit 1
  elif [ "grep cluster: $paramfile" != "" ] ; then
    export cluster=$(grep cluster $paramfile | awk -F: '{print $2}')
  fi
  kcliplan="$kcli plan --paramfile=$paramfile"
else
  workers="$1"
  envname="testk"
  kcliplan="$kcli plan"
fi

export cluster="${cluster:-$envname}"
$kcliplan -f ocp.yml -P workers=$workers -P scale=true $cluster
