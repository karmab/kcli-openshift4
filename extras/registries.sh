
clusterdir="clusters/prout"
#BASE64="base64 -w0"
BASE64="base64"

cat > registries.conf << EOF
[registries]
  [registries.search]
    registries = ["registry.access.redhat.com", "docker.io"]
  [registries.insecure]
    registries = ["brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888"]
  [registries.block]
    registries = []
EOF

cat > registries.yaml << EOF
spec:
  config:
    ignition:
      config: {}
      security:
        tls: {}
      timeouts: {}
      version: 2.2.0
    networkd: {}
    passwd: {}
    storage: {
            "files": [
                {
                    "path": "/etc/containers/registries.conf",
                    "filesystem": "root",
                    "mode": 420,
                    "contents": {
                    "source": "data:;base64,$(cat registries.conf|$BASE64)"
                    }
                }
                }
            ]
        }
EOF

cat > "${clusterdir}/99-master-registries.yaml" << EOF
---
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  creationTimestamp: null
  labels:  
    machineconfiguration.openshift.io/role: master
  name: 99-master-registries
$(cat registries.yaml)
EOF

cat > "${clusterdir}/99-worker-registries.yaml" << EOF
---
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  creationTimestamp: null
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-registries
$(cat registries.yaml)
EOF

rm -f registries.conf registries.yaml
