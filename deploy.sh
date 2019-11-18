#!/bin/bash

source common.sh

client=$(kcli list host | grep X | awk -F'|' '{print $2}' | xargs)
echo -e "${BLUE}Deploying on client $client${NC}"
kcli="kcli -C $client"
alias kcli >/dev/null 2>&1 && kcli=$(alias kcli | awk -F "'" '{print $2}')" -C $client"

if [ "$#" == '1' ]; then
  envname="$1"
  paramfile="$1"
  if [ ! -f $paramfile ]; then
    echo -e "${RED}Specified parameter file $paramfile doesn't exist.Leaving...${NC}"
    exit 1
  else
    $(python gather_env.py  $paramfile)
  fi
  kcliplan="$kcli create plan --paramfile=$paramfile"
else
  envname="testk"
  kcliplan="$kcli create plan"
fi

export cluster="${cluster:-$envname}"
helper_image="${helper_image:-CentOS-7-x86_64-GenericCloud.qcow2}"
helper_sleep="${helper_sleep:-15}"
image="${image:-}"
api_ip="${api_ip:-}"
public_api_ip="${public_api_ip:-}"
bootstrap_api_ip="${bootstrap_api_ip:-}"
export domain="${domain:-karmalabs.com}"
network="${network:-default}"
export masters="${masters:-1}"
export workers="${workers:-0}"
tag="${tag:-cnvlab}"
export pub_key="${pubkey:-$HOME/.ssh/id_rsa.pub}"
export pull_secret="${pull_secret:-openshift_pull.json}"
export upstream="${upstream:-false}"
force="${force:-false}"

if [ ! -f $pull_secret ] ; then
 echo -e "${RED}Missing pull secret file $pull_secret ${NC}"
 exit 1
fi
if [ ! -f $pub_key ] ; then
 echo -e "${RED}Missing public key file $pub_key ${NC}"
 exit 1
fi

clusterdir=clusters/$cluster
[ "$force" == "false" ] && [ -d $clusterdir ] && echo -e "${RED}Please Remove existing $clusterdir first${NC}..." && exit 1
export KUBECONFIG=$PWD/$clusterdir/auth/kubeconfig

which oc >/dev/null 2>&1
if [ "$?" != "0" ]; then
 echo -e "${BLUE}Downloading oc in current directory${NC}"
 curl --silent https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/$SYSTEM/oc.tar.gz > oc.tar.gz
 tar zxf oc.tar.gz
 rm -rf oc.tar.gz
fi

which openshift-install >/dev/null 2>&1
if [ "$?" != "0" ]; then
  if [ "$( grep registry.svc.ci.openshift.org $pull_secret )" != "" ] ; then
    if [ "$upstream" == "true" ] ; then
      get_upstream_installer.sh
    else
      get_nightly_installer.sh
    fi
  else
    get_stable_installer.sh
  fi
fi
INSTALLER_VERSION=$(openshift-install version | head -1 | cut -d" " -f2)
if [ "$upstream" == "true" ] ; then
  COS_VERSION="latest"
  COS_TYPE="fcos"
else
  COS_VERSION=$(echo $INSTALLER_VERSION |  sed "s/v\([0-9]*\).\([0-9]*\).*/\1\2/")
  COS_TYPE="rhcos"
fi

echo -e "${BLUE}Using installer version $INSTALLER_VERSION...${NC}"

platform=$($kcli list host | grep X | awk -F'|' '{print $3}' | xargs | sed 's/kvm/libvirt/')
if [ "$image" == "" ] ; then
    image=$($kcli list image | grep $COS_TYPE | grep $COS_VERSION | head -1 | awk -F'|' '{print $2}')
    if [ "$image" == "" ] ; then
      if [ "$platform" == "vsphere" ] ; then
        echo -e "${RED}Undefined image in parameters file...${NC}"
        exit 1
      fi
      echo -e "${BLUE}Downloading ${COS_TYPE} image...${NC}"
      kcli download image ${COS_TYPE}${COS_VERSION}
      image=$($kcli list image | grep $COS_TYPE | head -1 | awk -F'|' '{print $2}')
    fi
    image=$(basename $image)
    echo -e "${BLUE}Using image $image...${NC}"
else
  echo -e "${BLUE}Checking if image $image is available...${NC}"
  $kcli list image | grep -q $image 
  if [ "$?" != "0" ]; then
    echo -e "${RED}Missing $image. Indicate correct image in your parameters file...${NC}"
    exit 1
  fi
fi

mkdir -p $clusterdir || true
pub_key=`cat $pub_key`
pull_secret=`cat $pull_secret | tr -d [:space:]`
envsubst < install-config.yaml > $clusterdir/install-config.yaml

openshift-install --dir=$clusterdir create manifests
cp customisation/* $clusterdir/openshift
if [ "$workers" -gt "0" ]; then
  rm -f $clusterdir/openshift/99-ingress-controller.yaml
else
  sed -i "s/1/$masters/" $clusterdir/openshift/99-ingress-controller.yaml
fi
openshift-install --dir=$clusterdir create ignition-configs

if [[ "$platform" == *virt* ]] || [[ "$platform" == *openstack* ]] || [[ "$platform" == *vsphere* ]]; then
  if [ -f $paramfile ]; then
    dhcp_params=$(python gather_dhcp.py $paramfile platform)
    if [ ! -z "$dhcp_params" ] ; then 
      echo -e "${GREEN}Deploying helper dhcp node${NC}"
      kcli create plan -f dhcp.yml --paramfile $paramfile -P dhcp_image=$helper_image -P network=$network -P prefix=$cluster -P domain=$cluster.$domain $dhcp_params $cluster
    fi
  fi
fi

if [ "$platform" == "openstack" ]; then
  if [ -z "$api_ip" ] || [ -z "$public_api_ip" ]; then
    echo -e "${RED}You need to define both api_ip and public_api_ip in your parameters file${NC}"
    exit 1
  fi
fi

if [[ "$platform" == *virt* ]] || [[ "$platform" == *openstack* ]] || [[ "$platform" == *vsphere* ]]; then
  if [ -z "$api_ip" ]; then
    echo -e "${RED}You need to define api_ip in your parameters file${NC}"
    exit 1
  else
    if [[ "$platform" == *openstack* ]]; then
        host_ip=$public_api_ip
    else
        host_ip=$api_ip
    fi
    echo -e "${BLUE}Using $host_ip for api vip ...${NC}"
    duplicates=$(grep -c "^[^#].*api.$cluster.$domain" /etc/hosts)
    if [ "$duplicates" -gt "1" ] ; then
      echo -e "${BLUE}Cleaning duplicate entries for api.$cluster.$domain in /etc/hosts${NC}"
      sudo sed -i "/api.$cluster.$domain/d" /etc/hosts
    fi
    grep -q "$host_ip api.$cluster.$domain" /etc/hosts || sudo sh -c "echo $host_ip api.$cluster.$domain console-openshift-console.apps.$cluster.$domain oauth-openshift.apps.$cluster.$domain prometheus-k8s-openshift-monitoring.apps.$cluster.$domain >> /etc/hosts"
  fi
  if [ -d /Users ] ; then
    [ -d /etc/resolver ] || sudo mkdir /etc/resolver 
    if [ ! -f /etc/resolver/$cluster.$domain ] || [ "$(grep $api_ip /etc/resolver/$cluster.$domain)" == "" ] ; then
      echo -e "${BLUE}Adding wildcard for apps.$cluster.$domain in /etc/resolver...${NC}"
      sudo sh -c "echo nameserver $api_ip > /etc/resolver/$cluster.$domain"
    fi
  elif [ ! -f /etc/NetworkManager/dnsmasq.d/$cluster.$domain.conf ] || [ "$(grep $api_ip /etc/NetworkManager/dnsmasq.d/$cluster.$domain.conf)" == "" ] ; then
    echo -e "${BLUE}Adding wildcard for apps.$cluster.$domain in NetworkManager...${NC}"
    sudo sh -c "echo server=/apps.$cluster.$domain/$api_ip > /etc/NetworkManager/dnsmasq.d/$cluster.$domain.conf"
    sudo systemctl reload NetworkManager
  fi
  if [ "$platform" == "kubevirt" ] || [ "$platform" == "openstack" ] || [ "$platform" == "vsphere" ]; then
    # bootstrap ignition is too big for kubevirt/openstack/vsphere so we deploy a temporary web server
    if [ "$platform" == "kubevirt" ]; then
      helper_image="kubevirt/fedora-cloud-container-disk-demo"
      helper_parameters=""
      iptype="ip"
    else
      if [ "$helper_image" == "" ] ; then
        helper_image=$($kcli list image | grep -i 'centos\|fedora' | head -1)
        if [ "$helper_image" != "" ] ; then
          echo -e "${BLUE}Downloading centos helper image...${NC}"
          $kcli download centos7
          helper_image="CentOS-7-x86_64-GenericCloud.qcow2"
        else
          helper_image=$(basename "$helper_image")
        fi
        echo -e "${BLUE}Using helper image $helper_image${NC}"
      else
        echo -e "${BLUE}Checking if image $image is available...${NC}"
        $kcli list image | grep -q $helper_image 
        if [ "$?" != "0" ]; then
          echo -e "${RED}Missing image $helper_image. Indicate correct helper image in your parameters file...${NC}"
          exit 1
        fi
      fi
      if [ "$platform" == "openstack" ]; then
        helper_parameters="-P flavor=m1.medium"
        iptype="privateip"
        iptype="ip"
      else
        iptype="ip"
      fi
    fi
    $kcli create vm -p $helper_image -P plan=$cluster -P nets=[$network] $helper_parameters $cluster-bootstrap-helper
    while [ "$bootstrap_api_ip" == "" ] ; do
      bootstrap_api_ip=$($kcli info vm -f $iptype -v $cluster-bootstrap-helper)
      echo -e "${BLUE}Waiting 5s for bootstrap helper node to be running...${NC}"
      sleep 5
    done
    sleep $helper_sleep
    $kcli ssh root@$cluster-bootstrap-helper "iptables -F ; yum -y install httpd ; systemctl start httpd"
    $kcli scp $clusterdir/bootstrap.ign root@$cluster-bootstrap-helper:/var/www/html/bootstrap
    sed "s@https://api-int.$cluster.$domain:22623/config/master@http://$bootstrap_api_ip/bootstrap@" $clusterdir/master.ign > $clusterdir/bootstrap.ign
  fi
  sed -i "s@https://api-int.$cluster.$domain:22623/config@http://$api_ip:8080@" $clusterdir/master.ign $clusterdir/worker.ign
fi

if [[ "$platform" != *virt* ]] && [[ "$platform" != *openstack* ]] && [[ "$platform" != *vsphere* ]]; then
  # bootstrap ignition is too big for cloud platforms to handle so we deploy a temporary web server
  $kcli create vm -p $helper_image -P reservedns=true -P domain=$cluster.$domain -P tags=[$tag] -P plan=$cluster -P nets=[$network] $cluster-bootstrap-helper
  status=""
  while [ "$status" != "running" ] ; do
      status=$($kcli info vm -f status -v $cluster-bootstrap-helper | tr '[:upper:]' '[:lower:]' | sed 's/up/running/')
      echo -e "${BLUE}Waiting 5s for bootstrap helper node to be running...${NC}"
      sleep 5
  done
  $kcli ssh root@$cluster-bootstrap-helper "yum -y install httpd ; systemctl start httpd ; systemctl stop firewalld"
  $kcli scp clusters/$cluster/bootstrap.ign root@$cluster-bootstrap-helper:/var/www/html/bootstrap
  sed s@https://api-int.$cluster.$domain:22623/config/master@http://$cluster-bootstrap-helper.$cluster.$domain/bootstrap@ $clusterdir/master.ign > $clusterdir/bootstrap.ign
fi

if [[ "$platform" == *virt* ]] || [[ "$platform" == *openstack* ]] || [[ "$platform" == *vsphere* ]]; then
  $kcliplan -f ocp.yml -P image=$image $cluster
  openshift-install --dir=$clusterdir wait-for bootstrap-complete || exit 1
  todelete="$cluster-bootstrap"
  [ "$platform" == "kubevirt" ] && todelete="$todelete $cluster-bootstrap-helper"
  [[ "$platform" != *"virt"* ]] && todelete="$todelete $cluster-bootstrap-helper"
  $kcli delete vm --yes $todelete
else
  $kcliplan -f ocp_cloud.yml -P image=$image $cluster
  openshift-install --dir=$clusterdir wait-for bootstrap-complete || exit 1
  $kcli delete vm --yes $cluster-bootstrap $cluster-bootstrap-helper
fi

if [[ "$platform" == *virt* ]] || [ "$platform" == "vsphere" ]; then
  cp $clusterdir/worker.ign $clusterdir/worker.ign.ori
  curl --silent -kL https://api.$cluster.$domain:22623/config/worker -o $clusterdir/worker.ign
fi

if [ "$workers" -gt "0" ]; then
  oc adm taint nodes -l node-role.kubernetes.io/master node-role.kubernetes.io/master:NoSchedule-
fi
echo -e "${BLUE}Launching install-complete step. Note it will be retried one extra time in case of timeouts${NC}"
openshift-install --dir=$clusterdir wait-for install-complete || openshift-install --dir=$clusterdir wait-for install-complete

echo -e "${BLUE}Deploying certs autoapprover cronjob${NC}"
oc create -f autoapprovercron.yml
