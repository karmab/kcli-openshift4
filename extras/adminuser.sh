#!/bin/bash 

user1=admin
password1=admin
user2=dev
password2=dev
htpasswd=$(printf "$user1:$(openssl passwd -apr1 $password1)\n$user2:$(openssl passwd -apr1 $password2)\n")
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

oc adm policy add-cluster-role-to-user cluster-admin admin
