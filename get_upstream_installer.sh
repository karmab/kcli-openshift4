#!/bin/bash 

source common.sh

echo -e "${BLUE}Downloading latest openshift-install from registry.svc.ci.openshift.org in current directory${NC}"
VERSION=$(curl -s https://api.github.com/repos/openshift/okd/releases| grep tag_name | sed 's/.*: "\(.*\)",/\1/' | sort | tail -1)
curl -Ls https://github.com/openshift/okd/releases/download/$VERSION/openshift-install-$INSTALLSYSTEM-$VERSION.tar.gz | tar zxf - openshift-install -C . 
