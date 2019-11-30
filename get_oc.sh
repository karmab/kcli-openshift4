#!/bin/bash

source common.sh

echo -e "${BLUE}Downloading oc in current directory${NC}"
curl --silent https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/$SYSTEM/oc.tar.gz > oc.tar.gz
tar zxf oc.tar.gz
rm -rf oc.tar.gz
