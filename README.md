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
- Write access to /etc/hosts file to allow editing of this file.
- If targetting anything else than your local hypervisor, *~/.kcli/config.yml* properly configured (check https://kcli.readthedocs.io/en/master/#configuration and https://kcli.readthedocs.io/en/master/#provider-specifics)
- An available ip in your vm's network to use as *api_ip*. Make sure it is excluded from your dhcp server.
- Direct access to the deployed vms. Use something like this otherwise `sshuttle -r your_hypervisor 192.168.122.0/24 -v`).
- Target platform needs:
  - rhcos image ( *kcli download rhcos43* for instance ). the script will download latest if not present.
  - centos helper image ( *kcli download centos7* ). This is only needed on ovirt/vsphere/openstack
  - Target platform needs ignition support (for Ovirt/Rhv, this means >= 4.3.4).
  - For Libvirt, support for fw_cfg in qemu (install qemu-kvm-ev on centos for instance).
  - On Openstack, you will need to create a network with port security disabled (as we need a vip to be reachable on the masters). You will also need to create two ports on this network and map them to floating ips. Put the corresponding api_ip and public_api_ip in your parameter file. You can use [openstack.sh.sample](openstack.sh.sample) as a starting point. You also need to open relevant ports (80, 443, 6443 and 22623) in your security groups.

## How to Use

### Container Install

```
curl https://raw.githubusercontent.com/karmab/kcli-openshift4/master/install.sh | sh
```

If you run kcli from rpm/deb/pip, simply clone this repo and run the kcli-openshift4 script from there.

### Create a parameters.yml

```
kcli-openshift4 template parameters.yml
```

Tweak the resulting parameter file with the folloving variables:

- *version*. You can choose between nightly, ci, stable and upstream. Defaults to `nightly`. ci requires specific data in your secret
- *cluster*. Defaults to `testk`.
- *domain*. For cloud platforms, it should point to a domain name you have access to.Defaults to `karmalabs.com`.
- *network_type*. Defaults to `OpenShiftSDN`.
- *pub_key* location. Defaults to `$HOME/.ssh/id_rsa.pub`.
- *pull_secret* location. Defaults to `./openshift_pull.json`. You can omit this parameter when you set version to `upstream`
- *image* rhcos image to use (should be qemu for libvirt/kubevirt and openstack one for ovirt/openstack).
- *helper_image* which image to use when deploying temporary helper vms (defaults to `CentOS-7-x86_64-GenericCloud.qcow2`)
- *masters* number of masters. Defaults to `1`.
- *workers* number of workers. Defaults to `0`.
- *network*. Defaults to `default`.
- *master_memory*. Defaults to `8192Mi`.
- *worker_memory*. Defaults to `8192Mi`.
- *bootstrap_memory*. Defaults to `4096Mi`.
- *numcpus*. Defaults to `4`.
- *disk size* default disk size for final nodes. Defaults to `30Gb`.
- *extra_disk* whether to create a secondary disk (to use with rook, for instance). Defaults to `false`.
- *extra\_disks* array of additional disks.
- *api_ip* the ip to use for api ip. Defaults to `None`, in which case a temporary vm will be launched to gather a free one.
- *extra\_networks* array of additional networks.
- *master\_macs* optional array of master mac addresses.
- *worker\_macs* optional array of worker mac addresses.
- *numa* optional numa conf dictionary to apply to the workers only. Check [here](https://github.com/karmab/kcli-plans/blob/master/samples/cputuning/numa.yml) for an example.
- *numamode* optional numamode to apply to the workers only.
- *cpupinning* optional cpupinning conf to apply to the workers only.
- *pcidevices* optional array of pcidevices to passthrough to the first worker only. Check [here](https://github.com/karmab/kcli-plans/blob/master/samples/pcipassthrough/pci.yml) for an example.
- *ca* optional string of certificates to trust
- *baremetal* Whether to use openshift-baremetal-deploy (and as such, deploy baremetal operator deployed during the install)

### Deploying

```
kcli-openshift4 create parameters.yml
````

- You will be asked for your sudo password in order to create a /etc/hosts entry for the api vip.

- once that finishes, set the following environment variable in order to use oc commands `export KUBECONFIG=clusters/$cluster/auth/kubeconfig`

### Adding more workers

```
kcli-openshift4 scale -w num_of_workers parameters.yml
```

### Cleaning up

```
kcli-openshift4 delete parameters.yml
````

### Getting openshift-install binary beforehands

```
kcli-openshift4 download
````

By default, it will download the stable openshift-install in your current directory, but you can also specify a version (either stable,nightly or upstream).

There is also a tag flag you can use to get a specific image from registry.svc.ci registry, for which you will need to provide a valid pull secret.

### Providing custom machine configs

The assets found in the customisation directory are copied to the directory generated by the install, prior to deployment.

As such, any machine config file present in this directory will be added to the deployment.

## Architecture

Check [Architecture](ARCHITECTURE.md)
