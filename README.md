*DISCLAIMER*: This is not supported in anyway by Red Hat.

This repo provides a way for deploying openshift4 ( or okd ) on any platform and on an arbitrary number of masters and workers.

Openshift installer is used along with kcli for creation and customization of the vms.

The main features are:

- Easy customisation the vms.
- Single procedure regardless of the virtualization platform (tested on libvirt, ovirt, vsphere, kubevirt, openstack, aws and gcp)
- Self contained dns. (For cloud platforms, we do use cloud public dns)
- No need to compile installer or tweak libvirtd.
- Vms can be connected to a physical bridge.
- Multiple clusters can live on the same l2 network.
- Easily scale workers.
- Installation running in a dedicated container

## Requirements

- Valid pull secret.
- ssh public key.
- Latest kcli-openshift4
    - if you're running kcli through podman/docker, use *install.sh* to install kcli-openshift4 the same way. Also make sure your user has write access to /etc/hosts file to allow editing of this file.
    - if you're running kcli through rpm/deb, simply launch the kcli-openshift4 command.
    - If you want to target something else that your local hypervisor, you will need to configure ~/.kcli/config.yml following https://kcli.readthedocs.io/en/master/#configuration and https://kcli.readthedocs.io/en/master/#provider-specifics
- An available ip in your vm's network to use as *api_ip*. Make sure it is excluded from your dhcp server.
- Direct access to the deployed vms. Use something like this otherwise `sshuttle -r your_hypervisor 192.168.122.0/24 -v`).
- Target platform needs:
  - rhcos image ( *kcli download rhcos43* for instance ). the script will download latest if not present.
  - centos helper image ( *kcli download centos7* ). This is only needed on ovirt/vsphere/openstack
  - Target platform needs ignition support (for Ovirt/Rhv, this means >= 4.3.4).
  - For Libvirt, support for fw_cfg in qemu (install qemu-kvm-ev on centos for instance).
  - On Openstack, you will need to create a network with port security disabled (as we need a vip to be reachable on the masters). You will also need to create two ports on this network and map them to floating ips. Put the corresponding api_ip and public_api_ip in your parameter file. You can use [openstack.sh.sample](openstack.sh.sample) as a starting point. You also need to open relevant ports (80, 443, 6443 and 22623) in your security groups.

## How to Use

### Create a parameters.yml

```
kcli-openshift4 -t parameters.yml
```

First, create a parameter file similar to [*parameters.yml.sample*](parameters.yml.sample) and tweak the values you want:

- *version* name. You can choose between nightly, stable and upstream. Defaults to `nightly`
- *cluster* name. Defaults to `testk`
- *domain* name. For cloud platforms, it should point to a domain name you have access to.Defaults to `karmalabs.com`
- *pub_key* location. Defaults to `$HOME/.ssh/id_rsa.pub`
- *pull_secret* location. Defaults to `./openshift_pull.json`. You can omit this parameter when you set version to `upstream`
- *image* rhcos image to use (should be qemu for libvirt/kubevirt and openstack one for ovirt/openstack).
- *helper_image* which image to use when deploying temporary helper vms (defaults to `CentOS-7-x86_64-GenericCloud.qcow2`)
- *masters* number of masters. Defaults to `1`
- *workers* number of workers. Defaults to `0`
- *network*. Defaults to `default`
- *master_memory*. Defaults to `8192Mi`
- *worker_memory*. Defaults to `8192Mi`
- *bootstrap_memory*. Defaults to `4096Mi`
- *numcpus*. Defaults to `4`
- *disk size* default disk size for final nodes. Defaults to `30Gb`
- *extra_disk* whether to create a secondary disk (to use with rook, for instance). Defaults to `false`
- *extra\_disks* array of additional disks.
- *api_ip* the ip to use for api ip. Defaults to `None`, in which case a temporary vm will be launched to gather a free one.
- *extra\_networks* array of additional networks.
- *master\_macs* array of master mac addresses.
- *worker\_macs* array of worker mac addresses.

### Deploying

```
kcli-openshift4 parameters.yml
````

- You will be asked for your sudo password in order to create a /etc/hosts entry for the api vip.

- once that finishes, set the following environment variable in order to use oc commands `export KUBECONFIG=clusters/$cluster/auth/kubeconfig`

### Adding more workers

```
kcli-openshift4 -w num_of_workers parameters.yml
```

### Cleaning up

```
kcli-openshift4 -c parameters.yml
````

### Using a custom/latest openshift image

You can use the script *get_ci_installer.sh* or the following lines:

```
if [ ! -f openshift-install ] ; then
export PULL_SECRET="openshift_pull.json"
export VERSION=$(curl -s 'https://openshift-release.svc.ci.openshift.org/graph?format=dot' | grep tag | sed 's/.*label="\(.*.\)", shape=.*/\1/' | sort | tail -1)
export OPENSHIFT_RELEASE_IMAGE=registry.svc.ci.openshift.org/ocp/release:$VERSION
oc adm release extract --registry-config $PULL_SECRET --command=openshift-install --to . $OPENSHIFT_RELEASE_IMAGE
fi
```

There are other get_* scripts provided for retrieving a downstream nightly build of the installer or latest upstream

### Providing custom machine configs

The assets found in the customisation directory are copied to the directory generated by the install, prior to deployment.

As such, any machine config file present in this directory will be added to the deployment.

## Architecture

Check [Architecture](ARCHITECTURE.md)
