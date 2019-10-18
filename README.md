This repo provides a way for deploying ocp4 using an intermediate approach to upi/ipi, and by heavily leveraging kcli.

It's of course not supported in anyway by Red Hat.

The main features are:

- Single procedure regardless of the virtualization platform (tested on libvirt, ovirt, vsphere, kubevirt, openstack,aws and gcp)
- No need to control dns. Those elements are hosted as static pods on the master nodes. (For cloud platforms, we do use cloud public dns)
- Easy customisation the vms.
- Multiple clusters can live on the same l2 network.
- No need to compile installer.
- No need to tweak libvirtd.
- Vms can be connected to a physical bridge.

## Requirements

- Valid pull secret.
- ssh public key.
- jq. If not found, the script will download it for you.
- kcli >= 20.0 (optional, *deploy.sh* will run it through podman/docker if not present). If you want to target something else that your local hypervisor, you will need to configure ~/.kcli/config.yml following https://kcli.readthedocs.io/en/master/#configuration and https://kcli.readthedocs.io/en/master/#provider-specifics
- Direct access to the deployed vms. Use something like this otherwise `sshuttle -r your_hypervisor 192.168.122.0/24 -v`).
- Two unused ips in your network to use as *api_ip* and *dns_ip*. Make sure there are excluded from your dhcp server. If not specified, centos temporary vms will be launched to reserve free ips.
- Target platform needs:
  - rhcos image ( *kcli download rhcoslatest* ). *deploy.sh* will download latest if not present
  - (optional) centos image ( *kcli download centos7* ). This is only needed when you don't specify an *api_ip* and *dns_ip*
- For libvirt, support for fw_cfg in qemu (install qemu-kvm-ev on centos for instance).
- Target platform needs ignition support (for ovirt/rhv, this either requires ovirt >= 4.3.4).
- On openstack, you will need to create a network with port security disabled (as we need a vip to be reachable on the masters). You will also need to create two ports on this network and map them to floating ips. Put the corresponding api_ip, dns_ip and public_api_ip in your parameter file. You can use [openstack.sh.sample](openstack.sh.sample) as a starting point. You also need to open relevant ports (80, 443, 6443 and 22623) in your security groups.
- If defining yourself the vips to use, make sure they are excluded from your dhcp server.

## How to Use

### Setting your environment

if you create a file called *env.sh*, it will be sourced during deployment. You can put a specific kcli alias there if you're using the container version, or otherwise let the deployment script figure out which alias to use.

Default values can be checked in the parameters section of the file `ocp.yml` or by running `kcli plan -i ocp.yml`

If you want to tweak them, create a parameter file similar to [*parameters.yml.sample*](parameters.yml.sample) and edit:

- *cluster* name. Defaults to `testk`
- *domain* name. For cloud platforms, it should point to a domain name you have access toº. `Defaults to karmalabs.com`
- *pub_key* location. Defaults to `$HOME/.ssh/id_rsa.pub`
- *pull_secret* location. Defaults to `./openshift_pull.json`
- *template* rhcos template to use (should be qemu for libvirt/kubevirt and openstack one for ovirt/openstack).
- *helper_template* which template to use when deploying temporary vms (defaults to `CentOS-7-x86_64-GenericCloud.qcow2`)
- *helper_sleep*. Defaults to `15`. Number of seconds to wait when deploying the bootstrap helper node on openstack/kubevirt/vsphere before sshing into it
- *masters* number of masters. Defaults to `1`
- *workers* number of workers. Defaults to `0`
- *network*. Defaults to `default`
- *master_memory*. Defaults to `8192Mi`
- *worker_memory*. Defaults to `8192Mi`
- *bootstrap_memory*. Defaults to `4096Mi`
- *numcpus*. Defaults to `4`
- *disk size* default disk size for final nodes. Defaults to `30Gb`
- *extra_disk* whether to create a secondary disk (to use with rook, for instance). Defaults to `false`
- *extra\_disks* array of sizes for additional disk.
- *api_ip* the ip to use for api ip. Defaults to `None`, in which case a temporary vm will be launched to gather a free one.
- *dns_ip* the ip to use for dns ip. Defaults to `None`, in which case a temporary vm will be launched to gather a free one.

### Deploying

- `./deploy.sh` or `deploy.sh your_parameter_file` if you have created one.

- You will be asked for your sudo password in order to create a /etc/hosts entry for the api vip.

- once that finishes, set the following environment variable in order to use oc commands `export KUBECONFIG=clusters/$cluster/auth/kubeconfig`

### Adding more workers

- `./scale.sh num_of_workers` or `scale.sh your_parameter_file num_of_workers` if you have created one.

### Cleaning up

- `./clean.sh` or `clean.sh your_parameter_file` if you have created one.

### Using a custom/latest openshift image

You can use the script *get_latest_installer.sh* or the following lines:

```
if [ ! -f openshift-install ] ; then
export OPENSHIFT_RELEASE_IMAGE="registry.svc.ci.openshift.org/ocp/release:4.2"
export PULL_SECRET="openshift_pull.json"
TOKEN=$(cat $PULL_SECRET | jq -r '.auths."registry.svc.ci.openshift.org".auth' | base64 -d  | cut -d: -f2)
oc adm release extract --registry-config $PULL_SECRET --command=openshift-install --to . $OPENSHIFT_RELEASE_IMAGE
fi
```

### Providing custom machine configs

The assets found in the customisation directory are copied to the directory generated by the install, prior to deployment.

As such, any machine config file present in this directory will be added to the deployment.

## Architecture

### On libvirt/ovirt/vsphere/kubevirt/openstack

We deploy :

- an arbitrary number of masters.
- an arbitrary number of workers.
- a bootstrap node removed during the install.
- on kubevirt/openstack/vsphere, an additional bootstrap helper node removed during the install. It serves ignition data to the bootstrap node, as the field used to store userdata can't handle the many characters of the bootstrap ignition file.

If oc or openshift-install are missing, there latest versions are downloaded on the fly, either from registry.svc.ci.openshift.org if the provided pull secret has an auth for this registry or using public mirrors otherwise.

If no template is specified in a parameters file, latest rhcos image is downloaded and the corresponding line is added in the parameter file (to allow for scaling workers once install is finished).

All the ignition files needed for the install are generated.

Then, if no api ip or dns_ip has been specified, a temporary deployment of vms using a centos7 template is launched to gather available ips.

Final deployment is then launched.

Keepalived and Coredns with mdns are created on the fly on the bootstrap and master nodes as static pods. Initially, the api vip runs on the bootstrap node.

Nginx is created as static pod on the bootstrap node to serve as a http only web server for some additional ignition files needed on the nodes and which can't get injected (they are generated on the bootstrap node).

Haproxy is created as static pod on the master nodes to load balance traffic to the routers. When there are no workers, routers are instead scheduled on the master nodes and the haproxy static pod isn't created, so routers are simply accessed through the vip without load balancing in this case.

Once bootstrap steps finished, the corresponding vm gets deleted, causing keepalived to migrate the vips to one of the masters.

Also note that for bootstrap, masters and workers nodes, we merge the ignition data generated by the openshift installer with the ones generated by kcli, in particular we prepend dns server on those nodes to point to our keepalived vip, force hostnames and inject static pods.

### On aws/gcp

On those platform, we can't host a private vip on the nodes, so we rely exclusively on dns (with no load balancing at the moment)

For aws, you can use the rhcos-* ami images

For gcp, you will need to get the rhcos image, move it to a google bucket and import the image (this will soon be automated in kcli download)

An extra temporary node is deployed to serve ignition data to the bootstrap node, as those platforms use userdata field to pass ignition, and the bootstrap has too many characters.

Additionally, we automatically create the following dns records:

- api.$cluster.$domain initially pointing to the public ip of the bootstrap node, and later on changed to point to the public ip of the first master node
- *.apps.$cluster.$domain pointing to the public ip of the first master node ( or the first worker node if present)
- etcd-$num and default fqdn entries pointing to the private ip for the corresponding masters
- the proper srv dns entries.
