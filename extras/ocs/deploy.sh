#!/bin/bash
ocs_version="${ocs_version:-release-4.2}"
NAMESPACE="openshift-storage"
LOCALNAMESPACE="local-storage"

# Provide disks to use for mon and osd pvcs
export cluster="${cluster:-openshift-storage}"
# Size number for mon pvcs
export mon_size="${mon_size:-5}"
# List of /dev/* disks to use for osd, separated by comma
export osd_devices="${osd_devices:-/dev/vdb}"
export osd_size="${osd_size:-55}"

if [ "${osd_devices}" == "" ]; then
  echo You need to define osd_devices
  exit 1
fi

if [ "${osd_size}" == "" ]; then
  echo You need to define osd_size
  exit 1
fi

echo Using osd_devices ${osd_devices} of size ${osd_size}

oc create -f https://raw.githubusercontent.com/openshift/ocs-operator/${ocs_version}/deploy/deploy-with-olm.yaml

while ! oc wait --for condition=ready pod -l name=ocs-operator -n ${NAMESPACE} --timeout=2400s; do sleep 10 ; done
while ! oc wait --for condition=ready pod -l app=rook-ceph-operator -n ${NAMESPACE} --timeout=2400s; do sleep 10 ; done
while ! oc wait --for condition=ready pod -l app=noobaa -n ${NAMESPACE} --timeout=2400s; do sleep 10 ; done
while ! oc wait --for condition=ready pod -l name=local-storage-operator -n ${NAMESPACE} --timeout=2400s; do sleep 10 ; done

# This should be done by the ocs operator
oc adm policy add-cluster-role-to-user cluster-admin -z ocs-operator -n openshift-storage
oc adm policy add-cluster-role-to-user cluster-admin -z local-storage-operator -n openshift-storage

# Gather list of master nodes
export masters=$(oc get node -o custom-columns=NAME:.metadata.name --no-headers | tr '\n' ',' | sed 's/.$//')
master_count=$(echo $(IFS=,; set -f; set -- $masters; echo $#))
# Calculate number of osd to create
osd_count=$(echo $(IFS=,; set -f; set -- $osd_devices; echo $#))
export osd_count=$(( $osd_count * $master_count ))

oc create -f mon_sc.yml
export counter=0
for node in $(oc get node -o custom-columns=IP:.status.addresses[0].address --no-headers); do
    ssh -o StrictHostKeyChecking=no core@$node "sudo mkdir /mnt/mon"
    envsubst < hostpath.yml | oc create -f -
    export counter=$(( $counter + 1 )) 
done
envsubst < cr_osd.yml | oc create -f -

# Mark masters as storage nodes
for master in $( echo $masters | sed 's/,/ /g') ; do 
    oc label nodes $master cluster.ocs.openshift.io/openshift-storage=''
done

envsubst < storagecluster.yml | oc create -f -

while ! oc wait --for condition=ready pod -l app=rook-ceph-mgr -n ${NAMESPACE} --timeout=2400s; do sleep 10 ; done

curl -s https://raw.githubusercontent.com/rook/rook/master/cluster/examples/kubernetes/ceph/toolbox.yaml | sed "s/namespace: rook-ceph/namespace: openshift-storage/" | oc create -f -

# oc patch storageclass ${cluster}-ceph-rbd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
envsubst < sc.yml | oc create -f -

# Wait for OSD prepare jobs to be completed
echo "Waiting for the OSD jobs to be run..."

while ! oc wait --for condition=complete job -n ${NAMESPACE} -l app=rook-ceph-osd-prepare --timeout=2400s; do sleep 10 ; done

oc create -f cephblockpool.yml
