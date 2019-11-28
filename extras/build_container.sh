engine="docker"
which podman >/dev/null 2>&1 && engine="podman"
$engine rmi localhost/karmab/kcli-openshift4
$engine pull karmab/kcli
$engine build -t karmab/kcli-openshift4 .
