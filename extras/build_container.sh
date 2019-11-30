engine="docker"
which podman >/dev/null 2>&1 && engine="podman"
$engine rmi karmab/kcli
$engine rmi karmab/kcli-openshift4
$engine pull karmab/kcli
$engine build -t karmab/kcli-openshift4 .
