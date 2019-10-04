#!/bin/bash

source common.sh

client=$(kcli list --clients | grep X | awk -F'|' '{print $2}' | xargs)
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
    while read line ; do
        ( echo $line | grep -q ':' ) || continue
        ( echo $line | grep -q '\[' ) && continue
        export $(echo "$line" | cut -d: -f1 | xargs)=$(echo "$line" | cut -d: -f2 | xargs) ;
    done < $paramfile
  fi
  kcliplan="$kcli plan --paramfile=$paramfile"
else
  envname="testk"
  kcliplan="$kcli plan"
fi

export cluster="${cluster:-$envname}"
helper_template="${helper_template:-CentOS-7-x86_64-GenericCloud.qcow2}"
helper_sleep="${helper_sleep:-15}"
template="${template:-}"
api_ip="${api_ip:-}"
dns_ip="${dns_ip:-}"
public_api_ip="${public_api_ip:-}"
bootstrap_api_ip="${bootstrap_api_ip:-}"
export domain="${domain:-karmalabs.com}"
network="${network:-default}"
export masters="${masters:-1}"
export workers="${workers:-0}"
tag="${tag:-cnvlab}"
export pub_key="${pubkey:-$HOME/.ssh/id_rsa.pub}"
export pull_secret="${pull_secret:-openshift_pull.json}"
force="${force:-false}"

if [ ! -f $pull_secret ] ; then
 echo -e "${RED}Missing pull secret file $pull_secret ${NC}"
 exit 1
fi

which -s oc
if [ "$?" != "0" ]; then
 echo -e "${BLUE}Downloading oc in current directory${NC}"
 curl --silent https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/$SYSTEM/oc.tar.gz > oc.tar.gz
 tar zxf oc.tar.gz
 rm -rf oc.tar.gz
fi

clusterdir=clusters/$cluster
export KUBECONFIG=$PWD/$clusterdir/auth/kubeconfig
which -s openshift-install
if [ "$?" != "0" ]; then
  if [ "$( grep registry.svc.ci.openshift.org $pull_secret )" != "" ] ; then
      get_latest_installer.sh
  else
      get_stable_installer.sh
  fi
fi
INSTALLER_VERSION=$(openshift-install version | head -1 | cut -d" " -f2)
echo -e "${BLUE}Using installer version $INSTALLER_VERSION...${NC}"

[ "$force" == "false" ] && [ -d $clusterdir ] && echo -e "${RED}Please Remove existing $clusterdir first${NC}..." && exit 1
mkdir -p $clusterdir || true

platform=$($kcli list --clients | grep X | awk -F'|' '{print $3}' | xargs | sed 's/kvm/libvirt/')
if [ "$template" == "" ] ; then
    template=$($kcli list --templates | grep rhcos | head -1 | awk -F'|' '{print $2}')
    if [ "$template" == "" ] ; then
      if [ "$platform" == "vsphere" ] ; then
        echo -e "${RED}Undefined template in parameters file...${NC}"
        exit 1
      fi
      echo -e "${BLUE}Downloading latest rhcos template...${NC}"
      kcli download rhcoslatest
      template=$($kcli list --templates | grep rhcos | head -1 | awk -F'|' '{print $2}')
    fi
    template=$(basename $template)
    echo -e "${BLUE}Using template $template and adding it to your parameters file...${NC}"
    [ ! -z $paramfile ] && echo "template: $template" >> $paramfile
else
  echo -e "${BLUE}Checking if template $template is available...${NC}"
  $kcli list --templates | grep -q $template 
  if [ "$?" != "0" ]; then
    echo -e "${RED}Missing $template. Indicate correct template in your parameters file...${NC}"
    exit 1
  fi
fi

pub_key=`cat $pub_key`
pull_secret=`cat $pull_secret | tr -d [:space:]`
envsubst < install-config.yaml > $clusterdir/install-config.yaml

openshift-install --dir=$clusterdir create manifests
cp customisation/* $clusterdir/openshift
sed -i "s/3/$masters/" $clusterdir/openshift/99-ingress-controller.yaml
openshift-install --dir=$clusterdir create ignition-configs

if [ "$platform" == "openstack" ]; then
  if [ -z "$api_ip" ] || [ -z "$public_api_ip" ]; then
    echo -e "${RED}You need to define both api_ip and public_api_ip in your parameter file${NC}"
    exit 1
  fi
fi

if [[ "$platform" == *virt* ]] || [[ "$platform" == *openstack* ]] || [[ "$platform" == *vsphere* ]]; then
  if [ -z "$api_ip" ]; then
    # we deploy a temp vm to grab an ip for the api, if not predefined
    $kcli vm -p $helper_template -P plan=$cluster -P nets=[$network] $cluster-helper
    api_ip=""
    while [ "$api_ip" == "" ] ; do
      api_ip=$($kcli info -f ip -v $cluster-helper)
      echo -e "${BLUE}Waiting 5s to retrieve api ip from helper node...${NC}"
      sleep 5
    done
    $kcli delete --yes $cluster-helper
    echo -e "${BLUE}Using $api_ip for api vip ...${NC}"
    echo -e "${BLUE}Adding entry for api.$cluster.$domain in your /etc/hosts...${NC}"
    if [[ "$platform" == *openstack* ]]; then
        host_ip=$public_api_ip
    else
        host_ip=$api_ip
    fi
    sudo sed -i "/api.$cluster.$domain/d" /etc/hosts
    sudo sh -c "echo $host_ip api.$cluster.$domain console-openshift-console.apps.$cluster.$domain oauth-openshift.apps.$cluster.$domain prometheus-k8s-openshift-monitoring.apps.$cluster.$domain >> /etc/hosts"
    echo "api_ip: $api_ip" >> $paramfile
  else
    if [[ "$platform" == *openstack* ]]; then
        host_ip=$public_api_ip
    else
        host_ip=$api_ip
    fi
    echo -e "${BLUE}Using $host_ip for api vip ...${NC}"
    duplicates=$(grep -c "^[^#].*api.$cluster.$domain" /etc/hosts)
    if [ "$duplicates" -gt "1" ] ; then
      echo -e "${RED}Duplicate entries for api.$cluster.$domain found in /etc/hosts${NC}"
      exit 1
    fi
    grep -q "$host_ip api.$cluster.$domain" /etc/hosts || sudo sh -c "echo $host_ip api.$cluster.$domain console-openshift-console.apps.$cluster.$domain oauth-openshift.apps.$cluster.$domain prometheus-k8s-openshift-monitoring.apps.$cluster.$domain >> /etc/hosts"
  fi
  if [ -z "$dns_ip" ]; then
    # we deploy a temp vm to grab an ip for the dns, if not predefined
    $kcli vm -p $helper_template -P plan=$cluster -P nets=[$network] $cluster-dns-helper
    dns_ip=""
    while [ "$dns_ip" == "" ] ; do
      dns_ip=$($kcli info -f ip -v $cluster-dns-helper)
      echo -e "${BLUE}Waiting 5s to retrieve dns ip from dns helper node...${NC}"
      sleep 5
    done
    $kcli delete --yes $cluster-dns-helper
  fi
  echo -e "${BLUE}Using $dns_ip for dns vip ...${NC}"
  if [ -d /Users ] ; then
    [ -d /etc/resolver ] || sudo mkdir /etc/resolver 
    if [ ! -f /etc/resolver/$cluster.$domain ] || [ "$(grep $dns_ip /etc/resolver/$cluster.$domain)" == "" ] ; then
      echo -e "${BLUE}Adding wildcard for apps.$cluster.$domain in /etc/resolver...${NC}"
      sudo sh -c "echo nameserver $dns_ip > /etc/resolver/$cluster.$domain"
    fi
  elif [ ! -f /etc/NetworkManager/dnsmasq.d/$cluster.$domain.conf ] || [ "$(grep $dns_ip /etc/NetworkManager/dnsmasq.d/$cluster.$domain.conf)" == "" ] ; then
    echo -e "${BLUE}Adding wildcard for apps.$cluster.$domain in NetworkManager...${NC}"
    sudo sh -c "echo server=/apps.$cluster.$domain/$dns_ip > /etc/NetworkManager/dnsmasq.d/$cluster.$domain.conf"
    sudo systemctl reload NetworkManager
  fi
  if [ "$platform" == "kubevirt" ] || [ "$platform" == "openstack" ] || [ "$platform" == "vsphere" ]; then
    # bootstrap ignition is too big for kubevirt/openstack so we serve it from a dedicated temporary node
    if [ "$platform" == "kubevirt" ]; then
      helper_template="kubevirt/fedora-cloud-container-disk-demo"
      helper_parameters=""
      iptype="ip"
    elif [ "$platform" == "openstack" ]; then
      helper_parameters="-P flavor=m1.medium"
      iptype="privateip"
      iptype="ip"
    else
      iptype="ip"
    fi
    $kcli vm -p $helper_template -P plan=$cluster -P nets=[$network] $helper_parameters $cluster-bootstrap-helper
    while [ "$bootstrap_api_ip" == "" ] ; do
      bootstrap_api_ip=$($kcli info -f $iptype -v $cluster-bootstrap-helper)
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
  # bootstrap ignition is too big for cloud platforms to handle so we serve it from a dedicated temporary vm
  $kcli vm -p $helper_template -P reservedns=true -P domain=$cluster.$domain -P tags=[$tag] -P plan=$cluster -P nets=[$network] $cluster-bootstrap-helper
  status=""
  while [ "$status" != "running" ] ; do
      status=$($kcli info -f status -v $cluster-bootstrap-helper | tr '[:upper:]' '[:lower:]' | sed 's/up/running/')
      echo -e "${BLUE}Waiting 5s for bootstrap helper node to be running...${NC}"
      sleep 5
  done
  $kcli ssh root@$cluster-bootstrap-helper "yum -y install httpd ; systemctl start httpd ; systemctl stop firewalld"
  $kcli scp clusters/$cluster/bootstrap.ign root@$cluster-bootstrap-helper:/var/www/html/bootstrap
  sed s@https://api-int.$cluster.$domain:22623/config/master@http://$cluster-bootstrap-helper.$cluster.$domain/bootstrap@ $clusterdir/master.ign > $clusterdir/bootstrap.ign
fi

if [[ "$platform" == *virt* ]] || [[ "$platform" == *openstack* ]] || [[ "$platform" == *vsphere* ]]; then
  $kcliplan -f ocp.yml -P template=$template $cluster
  openshift-install --dir=$clusterdir wait-for bootstrap-complete || exit 1
  todelete="$cluster-bootstrap"
  [ "$platform" == "kubevirt" ] && todelete="$todelete $cluster-bootstrap-helper"
  [[ "$platform" != *"virt"* ]] && todelete="$todelete $cluster-bootstrap-helper"
  $kcli delete --yes $todelete
else
  $kcliplan -f ocp_cloud.yml -P template=$template $cluster
  openshift-install --dir=$clusterdir wait-for bootstrap-complete || exit 1
  $kcli delete --yes $cluster-bootstrap $cluster-bootstrap-helper
fi

if [[ "$platform" == *virt* ]] || [ "$platform" == "vsphere" ]; then
  cp $clusterdir/worker.ign $clusterdir/worker.ign.ori
  curl --silent -kL https://api.$cluster.$domain:22623/config/worker -o $clusterdir/worker.ign
fi

if [[ "$INSTALLER_VERSION" == v4.1* ]] && [ "$workers" -lt "1" ]; then
 oc adm taint nodes -l node-role.kubernetes.io/master node-role.kubernetes.io/master:NoSchedule-
fi
echo -e "${BLUE}Launching install-complete step. Note it will be retried one extra time in case of timeouts${NC}"
openshift-install --dir=$clusterdir wait-for install-complete || openshift-install --dir=$clusterdir wait-for install-complete

echo -e "${BLUE}Deploying certs autoapprover cronjob${NC}"
oc create -f autoapprovercron.yml
