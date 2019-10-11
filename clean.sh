#!/bin/bash

source common.sh

client=$(kcli list host | grep X | awk -F'|' '{print $2}' | xargs)
echo -e "${BLUE}Cleaning on client $client${NC}"
kcli="kcli -C $client"
alias kcli >/dev/null 2>&1 && kcli=$(alias kcli | awk -F "'" '{print $2}')" -C $client"

if [ "$#" == '1' ]; then
  envname="$1"
  paramfile="$1"
  if [ ! -f $paramfile ]; then
    echo -e "${RED}Specified parameter file $paramfile doesn't exist.Leaving...${NC}"
    exit 1
  elif [ "grep cluster: $paramfile" != "" ] ; then
    export cluster=$(grep cluster $paramfile | awk -F: '{print $2}' | xargs)
  fi
else
  envname="testk"
fi

export cluster="${cluster:-$envname}"
kcli delete plan $cluster --yes
rm -rf clusters/${cluster}
