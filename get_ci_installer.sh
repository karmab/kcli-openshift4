#!/bin/bash 

echo -e "Downloading latest openshift-install from registry.svc.ci.openshift.org in current directory"
export PULL_SECRET="openshift_pull.json"
export VERSION=$(curl -s 'https://openshift-release.svc.ci.openshift.org/graph?format=dot' | grep tag | sed 's/.*label="\(.*.\)", shape=.*/\1/' | sort | tail -1)
export OPENSHIFT_RELEASE_IMAGE=registry.svc.ci.openshift.org/ocp/release:$VERSION
export OPENSHIFT_RELEASE_IMAGE=registry.svc.ci.openshift.org/ocp/release:4.4
oc adm release extract --registry-config $PULL_SECRET --command=openshift-install --to . $OPENSHIFT_RELEASE_IMAGE
