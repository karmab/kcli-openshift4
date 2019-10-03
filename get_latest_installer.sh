#!/bin/bash 

export PATH=.:$PATH
if [ ! -f openshift-install ] ; then
#export OPENSHIFT_RELEASE_IMAGE="registry.svc.ci.openshift.org/ocp/release:4.2"
export PULL_SECRET="openshift_pull.json"
TOKEN=$(cat $PULL_SECRET | jq -r '.auths."registry.svc.ci.openshift.org".auth' | base64 -d  | cut -d: -f2)
export VERSION=$(curl -s -H  "Authorization: Bearer $TOKEN" https://registry.svc.ci.openshift.org/v2/ocp/release/tags/list | jq -r '.tags | .[]' | sort | grep ci | tail -1)
export OPENSHIFT_RELEASE_IMAGE=registry.svc.ci.openshift.org/ocp/release:$VERSION
oc adm release extract --registry-config $PULL_SECRET --command=openshift-install --to . $OPENSHIFT_RELEASE_IMAGE
fi
