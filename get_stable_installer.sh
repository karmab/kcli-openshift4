#!/bin/bash

source common.sh
echo -e "${BLUE}Downloading latest openshift-install from https://mirror.openshift.com/pub/openshift-v4/clients/ocp in current directory${NC}"
VERSION=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/release.txt | grep 'Name:' | awk -F: '{print $2}' | xargs)
curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-$INSTALLSYSTEM-$VERSION.tar.gz | tar zxvf - openshift-install
