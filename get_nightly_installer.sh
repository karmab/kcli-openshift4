#!/bin/bash 

source common.sh
echo -e "${BLUE}Downloading latest openshift-install from registry.svc.ci.openshift.org in current directory${NC}"
which jq  >/dev/null 2>&1
if [ "$?" != "0" ] ; then
  echo -e "${BLUE}Downloading jq in current directory${NC}"
  curl --silent https://github.com/stedolan/jq/releases/download/$jq > jq
  chmod u+x jq
fi
export PULL_SECRET="openshift_pull.json"
export VERSION=$(curl -s https://openshift-release.svc.ci.openshift.org/graph | grep version| grep nightly | sort | tail -1 | sed 's/.*"\(.*\)",/\1/')
export OPENSHIFT_RELEASE_IMAGE=registry.svc.ci.openshift.org/ocp/release:$VERSION
oc adm release extract --registry-config $PULL_SECRET --command=openshift-install --to . $OPENSHIFT_RELEASE_IMAGE
