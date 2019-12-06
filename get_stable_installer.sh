#!/bin/bash

if [ -d /Users ] ; then
    INSTALLSYSTEM=mac
fi
echo -e "Downloading latest openshift-install from https://mirror.openshift.com/pub/openshift-v4/clients/ocp in current directory"
VERSION=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/release.txt | grep 'Name:' | awk -F: '{print $2}' | xargs)
curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-${INSTALLSYSTEM:-linux}-$VERSION.tar.gz | tar zxvf - openshift-install
