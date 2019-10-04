#!/bin/bash

source common.sh

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
