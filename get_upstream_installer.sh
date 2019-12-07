#!/bin/bash 

if [ -d /Users ] ; then
    INSTALLSYSTEM=mac
fi
echo -e "Downloading latest openshift-install from registry.svc.ci.openshift.org in current directory"
VERSION=$(curl -s https://api.github.com/repos/openshift/okd/releases| grep tag_name | sed 's/.*: "\(.*\)",/\1/' | sort | tail -1)
curl -Ls https://github.com/openshift/okd/releases/download/$VERSION/openshift-install-${INSTALLSYSTEM:-linux}-$VERSION.tar.gz | tar zxf - openshift-install -C . 
