#!/bin/bash 

oc create secret generic htpass-secret --from-file=htpasswd=htpasswd -n openshift-config
oc apply -f oauth.yml
oc adm policy add-cluster-role-to-user cluster-admin admin
