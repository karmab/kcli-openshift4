#!/bin/bash 

user=admin
password=admin
htpasswd=$(printf "$user:$(openssl passwd -apr1 $password)\n")
htpasswd=$(echo $htpasswd | base64)

oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: htpass-secret
  namespace: openshift-config
data:
  htpasswd: $htpasswd
EOF

# configure HTPasswd IDP
oc apply -f - <<EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpassidp
    challenge: true
    login: true
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF

#sleep 20
oc adm policy add-cluster-role-to-user cluster-admin admin
