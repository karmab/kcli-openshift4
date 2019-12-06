#!/bin/bash

if [ -d /Users ] ; then
 export SYSTEM=macosx
fi
echo -e "Downloading oc in current directory"
curl --silent https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/${SYSTEM:-linux}/oc.tar.gz > oc.tar.gz
tar zxf oc.tar.gz
rm -rf oc.tar.gz
