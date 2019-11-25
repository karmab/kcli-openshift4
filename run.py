#!/usr/bin/env python

import argparse
from distutils.spawn import find_executable
from glob import glob
import json
from kvirt.config import Kconfig
from kvirt.common import pprint, get_parameters
import os
import re
from shutil import copy2, rmtree, move
from subprocess import call
import sys
from time import sleep
import yaml
import ssl
from urllib.request import urlopen


virtplatforms = ['kvm', 'kubevirt', 'ovirt', 'openstack', 'vsphere']
cloudplatforms = ['aws', 'gcp']


def pwd_path(x):
    if x is None:
        return None
    result = '/workdir/%s' % x if os.path.exists('/i_am_a_container') else x
    return result


def real_path(x):
    return x.replace('/workdir/', '')


def insecure_fetch(url):
    context = ssl._create_unverified_context()
    data = urlopen(url, context=context)
    return data.read()


def get_values(data, element, field):
    results = []
    if '%s_%s' % (element, field) in data:
        new = data['%s_%s' % (element, field)]
        results.extend(new)
    return results


def get_installer(nightly=False, macosx=False):
    repo = 'ocp-dev-preview' if nightly else 'ocp'
    INSTALLSYSTEM = 'mac' if os.path.exists('/Users') or macosx else 'linux'
    msg = 'Downloading openshift-install from https://mirror.openshift.com/pub/openshift-v4/clients/%s' % repo
    pprint(msg, color='blue')
    r = urlopen("https://mirror.openshift.com/pub/openshift-v4/clients/%s/latest/release.txt" % repo).readlines()
    version = None
    for line in r:
        if 'Name' in str(line):
            version = str(line).split(':')[1].strip().replace('\\n', '').replace("'", "")
            break
    if version is None:
        pprint("Coudldn't find version", color='red')
        os._exit(1)
    cmd = "curl -s https://mirror.openshift.com/pub/openshift-v4/clients/%s/latest/" % repo
    cmd += "openshift-install-%s-%s.tar.gz " % (INSTALLSYSTEM, version)
    cmd += "| tar zxf - openshift-install"
    cmd += "; chmod 700 openshift-install"
    call(cmd, shell=True)


def get_upstream_installer(macosx=False):
    INSTALLSYSTEM = 'mac' if os.path.exists('/Users') or macosx else 'linux'
    msg = 'Downloading okd openshift-install from github in current directory'
    pprint(msg, color='blue')
    r = urlopen("https://api.github.com/repos/openshift/okd/releases")
    data = json.loads(r.read())
    version = sorted([x['tag_name'] for x in data])[-1]
    cmd = "curl -Ls https://github.com/openshift/okd/releases/download/"
    cmd += "%s/openshift-install-%s-%s.tar.gz" % (version, INSTALLSYSTEM, version)
    cmd += "| tar zxf - openshift-install"
    cmd += "; chmod 700 openshift-install"
    call(cmd, shell=True)


def gather_dhcp(data, platform):
    cluster = data.get('cluster', 'testk')
    masters = data.get('masters', 1)
    workers = data.get('workers', 0)
    bootstrap_name = "%s-bootstrap" % cluster
    bootstrap_mac = data.get('bootstrap_mac')
    bootstrap_ip = data.get('bootstrap_ip')
    dhcp_ip = data.get('dhcp_ip')
    dhcp_netmask = data.get('dhcp_netmask')
    dhcp_gateway = data.get('dhcp_gateway')
    dhcp_dns = data.get('dhcp_dns')
    if bootstrap_mac is None or bootstrap_ip is None or dhcp_ip is None or dhcp_netmask is None\
            or dhcp_gateway is None or dhcp_dns is None:
        return {}
    if platform in ['kubevirt', 'openstack', 'vsphere']:
        bootstrap_helper_name = "%s-bootstrap-helper" % cluster
        bootstrap_helper_mac = data.get('bootstrap_helper_mac')
        bootstrap_helper_ip = data.get('bootstrap_helper_ip')
        if bootstrap_helper_mac is None or bootstrap_helper_ip is None:
            return {}
    master_names = ['%s-master-%s' % (cluster, num) for num in range(masters)]
    worker_names = ['%s-worker-%s' % (cluster, num) for num in range(workers)]
    node_names = master_names + worker_names
    master_macs = get_values(data, 'master', 'macs')
    worker_macs = get_values(data, 'worker', 'macs')
    node_macs = master_macs + worker_macs
    master_ips = get_values(data, 'master', 'ips')
    worker_ips = get_values(data, 'worker', 'ips')
    node_ips = master_ips + worker_ips
    if node_macs and node_ips and len(node_macs) == len(node_ips) and len(node_names) == len(node_macs):
        nodes = len(node_macs) + 1
        node_names.insert(0, bootstrap_name)
        node_macs.insert(0, bootstrap_mac)
        node_ips.insert(0, bootstrap_ip)
        if platform in ['kubevirt', 'openstack', 'vsphere']:
            nodes += 1
            node_names.insert(0, bootstrap_helper_name)
            node_macs.insert(0, bootstrap_helper_mac)
            node_ips.insert(0, bootstrap_helper_ip)
        node_names = ','.join(node_names)
        node_macs = ','.join(node_macs)
        node_ips = ','.join(node_ips)
        return {'node_names': node_names, 'node_macs': node_macs, 'node_ips': node_ips, 'nodes': nodes}


def template(paramfile):
    pprint("Generating parameter file %s" % real_path(paramfile), color='green')
    params = get_parameters('ocp.yml')
    parameters = '\n'.join([parameter.lstrip() for parameter in params.split('\n')[1:]])
    path = paramfile
    with open(path, 'w') as f:
        f.write("version: stable\n")
        f.write(parameters)
        f.write("macosx: False\n")


def scale(paramfile, workers):
    config = Kconfig()
    client = config.client
    platform = config.type
    k = config.k
    pprint("Scaling on client %s" % client, color='blue')
    if not os.path.exists(paramfile):
        pprint("Specified parameter file %s doesn't exist.Leaving..." % real_path(paramfile), color='red')
        sys.exit(1)
    with open(paramfile) as entries:
        paramdata = yaml.safe_load(entries)
    cluster = paramdata.get('cluster', 'testk')
    config.plan(cluster, delete=True)
    image = k.info("%s-master-0" % cluster).get('image')
    if image is None:
        pprint("Missing image...", color='red')
        sys.exit(1)
    else:
        pprint("Using image %s" % image, color='red')
    paramdata['image'] = image
    paramdata['scale'] = True
    paramdata['workers'] = workers
    if platform in virtplatforms:
        config.plan(cluster, inputfile='ocp.yml', overrides=paramdata)
    elif platform in cloudplatforms:
        config.plan(cluster, inputfile='ocp_cloud.yml', overrides=paramdata)


def clean(paramfile):
    config = Kconfig()
    client = config.client
    pprint("Cleaning on client %s" % client, color='blue')
    if not os.path.exists(paramfile):
        pprint("Specified parameter file %s doesn't exist.Leaving..." % real_path(paramfile), color='red')
        sys.exit(1)
    with open(paramfile) as entries:
        paramdata = yaml.safe_load(entries)
    cluster = paramdata.get('cluster', 'testk')
    config.plan(cluster, delete=True)
    clusterdir = pwd_path("clusters/%s" % cluster)
    if os.path.exists(clusterdir):
        pprint("Deleting %s" % real_path(clusterdir), color='green')
        rmtree(clusterdir)


def deploy(paramfile):
    ocdownloaded = False
    # installerdownloaded = False
    config = Kconfig()
    k = config.k
    client = config.client
    platform = config.type
    pprint("Deploying on client %s" % client, color='blue')
    envname = paramfile if paramfile is not None else 'testk'
    if not os.path.exists(paramfile):
        pprint("Specified parameter file %s doesn't exist.Leaving..." % real_path(paramfile), color='red')
        sys.exit(1)
    with open(paramfile) as entries:
        paramdata = yaml.safe_load(entries)
    data = {'cluster': envname,
            'helper_image': 'CentOS-7-x86_64-GenericCloud.qcow2',
            'helper_sleep': 15,
            'domain': 'karmalabs.com',
            'network': 'default',
            'masters': 1,
            'workers': 0,
            'tag': 'cnvlab',
            'pub_key': '%s/.ssh/id_rsa.pub' % os.environ['HOME'],
            'pull_secret': 'openshift_pull.json',
            'version': 'nightly',
            'macosx': False}
    data.update(paramdata)
    version = data.get('version')
    if version not in ['nightly', 'upstream']:
        pprint("Using stable version", color='blue')
    else:
        pprint("Using %s version" % version, color='blue')
    cluster = data.get('cluster')
    helper_image = data.get('helper_image')
    # helper_sleep = data.get('helper_sleep')
    image = data.get('image')
    api_ip = data.get('api_ip')
    public_api_ip = data.get('public_api_ip')
    bootstrap_api_ip = data.get('bootstrap_api_ip')
    domain = data.get('domain')
    network = data.get('network')
    masters = data.get('masters')
    workers = data.get('workers')
    tag = data.get('tag')
    pub_key = data.get('pub_key')
    pull_secret = pwd_path(data.get('pull_secret'))
    macosx = data.get('macosx')
    if macosx and not os.path.exists('/i_am_a_container'):
        macosx = False
    if platform == 'openstack' and (api_ip is None or public_api_ip is None):
        pprint("You need to define both api_ip and public_api_ip in your parameters file", color='red')
        os._exit(1)
    if not os.path.exists(pull_secret):
        pprint("Missing pull secret file %s" % pull_secret, color='red')
        sys.exit(1)
    if not os.path.exists(pub_key):
        if os.path.exists('/%s/.kcli/id_rsa.pub' % os.environ['HOME']):
            pub_key = '%s/.kcli/id_rsa.pub' % os.environ['HOME']
        else:
            pprint("Missing public key file %s" % pub_key, color='red')
            sys.exit(1)
    clusterdir = pwd_path("clusters/%s" % cluster)
    if os.path.exists(clusterdir):
        pprint("Please Remove existing %s first..." % clusterdir, color='red')
        sys.exit(1)
    os.environ['KUBECONFIG'] = "%s/auth/kubeconfig" % clusterdir
    if find_executable('oc') is None:
        SYSTEM = 'macosx' if os.path.exists('/Users') else 'linux'
        pprint("Downloading oc in current directory", color='blue')
        occmd = "curl -s https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/%s/oc.tar.gz" % SYSTEM
        occmd += "| tar zxf - oc"
        occmd += "; chmod 700 oc"
        call(occmd, shell=True)
        ocdownloaded = True
        if not macosx and os.path.exists('/i_am_a_container'):
            move('oc', '/workdir')
    if find_executable('openshift-install') is None:
        if version == 'nightly':
            get_installer(nightly=True)
        elif version == 'upstream':
            get_upstream_installer()
        else:
            get_installer()
        # installerdownloaded = True
        if not macosx and os.path.exists('/i_am_a_container'):
            move('openshift-install', '/workdir')
    INSTALLER_VERSION = os.popen('openshift-install version').readlines()[0].split(" ")[1].strip()
    pprint("Using installer version %s" % INSTALLER_VERSION, color='blue')
    if version == 'upstream':
        COS_VERSION = "latest"
        COS_TYPE = "fcos"
    else:
        version_match = re.match("v([0-9]*).([0-9]*).*", INSTALLER_VERSION)
        COS_VERSION = "%s%s" % (version_match.group(1), version_match.group(2))
        COS_TYPE = "rhcos"
    if image is None:
        images = [v for v in k.volumes() if COS_TYPE in v and COS_VERSION in v]
        if images:
            image = os.path.basename(images[0])
        else:
            pprint("Downloading %s image" % COS_TYPE, color='blue')
            result = config.handle_host(pool=config.pool, image="%s%s" % (COS_TYPE, COS_VERSION),
                                        download=True, update_profile=False)
            if result['result'] != 'success':
                os._exit(1)
            images = [v for v in k.volumes() if image.startswith("%s%s" % (COS_TYPE, COS_VERSION))]
            image = images[0]
        pprint("Using image %s" % image, color='blue')
    else:
        pprint("Checking if image %s is available" % image, color='blue')
        images = [v for v in k.volumes() if image in v]
        if not images:
            pprint("Missing %s. Indicate correct image in your parameters file..." % image, color='red')
            os._exit(1)
    paramdata['image'] = image
    if not os.path.exists(clusterdir):
        os.makedirs(clusterdir)
    data['pub_key'] = open(pub_key).read().strip()
    data['pull_secret'] = re.sub(r"\s", "", open(pull_secret).read())
    installconfig = config.process_inputfile(cluster, "install-config.yaml", overrides=data)
    with open("%s/install-config.yaml" % clusterdir, 'w') as f:
        f.write(installconfig)
    call('openshift-install --dir=%s create manifests' % clusterdir, shell=True)
    for f in [f for f in glob("customisation/*.yaml")]:
        if '99-ingress-controller.yaml' in f:
            if workers == 0:
                installconfig = config.process_inputfile(cluster, f, overrides={'replicas': masters})
                with open("%s/openshift/99-ingress-controller.yaml" % clusterdir, 'w') as f:
                    f.write(installconfig)
        else:
            copy2(f, "%s/openshift" % clusterdir)
    call('openshift-install --dir=%s create ignition-configs' % clusterdir, shell=True)
    staticdata = gather_dhcp(data, platform)
    if staticdata:
        pprint("Deploying helper dhcp node" % image, color='green')
        staticdata.update({'network': network, 'dhcp_image': helper_image, 'prefix': cluster,
                          domain: '%s.%s' % (cluster, domain)})
        config.plan(cluster, inputfile='dhcp.yml', overrides=staticdata)
    if platform in virtplatforms:
        if api_ip is None:
            pprint("You need to define api_ip in your parameters file", color='red')
            os._exit(1)
        host_ip = api_ip if platform != "openstack" else public_api_ip
        pprint("Using %s for api vip...." % host_ip, color='blue')
        if not os.path.exists("/i_am_a_container"):
            hosts = open("/etc/hosts").readlines()
            wronglines = [e for e in hosts if not e.startswith('#') and "api.%s.%s" % (cluster, domain) in e and
                          host_ip not in e]
            for wrong in wronglines:
                pprint("Cleaning duplicate entries for api.%s.%s in /etc/hosts" % (cluster, domain), color='blue')
                call("sudo sed -i '/api.%s.%s/d' /etc/hosts" % (cluster, domain), shell=True)
            hosts = open("/etc/hosts").readlines()
            correct = [e for e in hosts if not e.startswith('#') and "api.%s.%s" % (cluster, domain) in e and
                       host_ip in e]
            if not correct:
                entries = ["%s.%s.%s" % (x, cluster, domain) for x in ['api', 'console-openshift-console.apps',
                                                                       'oauth-openshift.apps',
                                                                       'prometheus-k8s-openshift-monitoring.apps']]
                entries = ' '.join(entries)
                call("sudo sh -c 'echo %s %s >> /etc/hosts'" % (host_ip, entries), shell=True)
            if os.path.exists('/Users'):
                if not os.path.exists('/etc/resolver'):
                    os.mkdir('/etc/resolver')
                if not os.path.exists('/etc/resolver/%s.%s' % (cluster, domain)):
                    pprint("Adding wildcard for apps.%s.%s in /etc/resolver" % (cluster, domain), color='blue')
                    call("sudo sh -c 'echo nameserver %s > /etc/resolver/%s.%s'" % (api_ip, cluster, domain),
                         shell=True)
                else:
                    resolverlines = open("/etc/resolver/%s.%s" % (cluster, domain)).readlines()
                    correct = [e for e in resolverlines if api_ip not in e]
                    if not correct:
                        pprint("Adding wildcard for apps.%s.%s in /etc/resolver" % (cluster, domain), color='blue')
                        call("sudo sh -c 'echo nameserver %s > /etc/resolver/%s.%s'" % (api_ip, cluster, domain),
                             shell=True)
            elif not os.path.exists("/etc/NetworkManager/dnsmasq.d/%s.%s.conf" % (cluster, domain)):
                pprint("Adding wildcard for apps.%s.%s in /etc/resolver" % (cluster, domain), color='blue')
                nm = "sudo sh -c '"
                nm += "echo server=/apps.%s.%s/%s > /etc/NetworkManager/dnsmasq.d/%s.%s.conf'" % (cluster, domain,
                                                                                                  api_ip, cluster,
                                                                                                  domain)
                nm += ";sudo systemctl reload NetworkManager"
                call(nm, shell=True)
            else:
                nmfile = open("/etc/NetworkManager/dnsmasq.d/%s.%s.conf" % (cluster, domain)).readlines()
                correct = [e for e in nmfile if host_ip in e]
                if not correct:
                    pprint("Adding wildcard for apps.%s.%s in /etc/resolver" % (cluster, domain), color='blue')
                    nm = "sudo sh -c '"
                    nm += "echo server=/apps.%s.%s/%s > /etc/NetworkManager/dnsmasq.d/%s.%s.conf'" % (cluster, domain,
                                                                                                      api_ip, cluster,
                                                                                                      domain)
                    nm += ";sudo systemctl reload NetworkManager"
                    call(nm, shell=True)
        else:
            entries = ["%s.%s.%s" % (x, cluster, domain) for x in ['api', 'console-openshift-console.apps',
                                                                   'oauth-openshift.apps',
                                                                   'prometheus-k8s-openshift-monitoring.apps']]
            entries = ' '.join(entries)
            call("sh -c 'echo %s %s >> /etc/hosts'" % (host_ip, entries), shell=True)
            if os.path.exists('/etcdir/hosts'):
                call("sh -c 'echo %s %s >> /etcdir/hosts'" % (host_ip, entries), shell=True)
        if platform in ['kubevirt', 'openstack', 'vsphere']:
            # bootstrap ignition is too big for kubevirt/openstack/vsphere so we deploy a temporary web server
            overrides = {}
            if platform == 'kubevirt':
                overrides['helper_image'] = "kubevirt/fedora-cloud-container-disk-demo"
                iptype = "ip"
            else:
                if helper_image is None:
                    images = [v for v in k.volumes() if 'centos' in v.lower() or 'fedora' in v.lower()]
                    if images:
                        image = os.path.basename(images[0])
                    else:
                        helper_image = "CentOS-7-x86_64-GenericCloud.qcow2"
                        pprint("Downloading centos helper image", color='blue')
                        result = config.handle_host(pool=config.pool, image="centos7", download=True,
                                                    update_profile=False)
                    pprint("Using helper image %s" % helper_image, color='blue')
                else:
                    images = [v for v in k.volumes() if helper_image in v]
                    if not images:
                        pprint("Missing image %s. Indicate correct helper image in your parameters file" % helper_image,
                               color='red')
                        os._exit(1)
                iptype = 'ip'
                if platform == 'openstack':
                    overrides['flavor'] = "m1.medium"
                    iptype = "privateip"
            overrides['nets'] = [network]
            overrides['plan'] = cluster
            bootstrap_helper_name = "%s-bootstrap-helper" % cluster
            config.create_vm("%s-bootstrap-helper" % cluster, helper_image, overrides=overrides)
            while bootstrap_api_ip is None:
                bootstrap_api_ip = k.info(bootstrap_helper_name).get(iptype)
                pprint("Waiting 5s for bootstrap helper node to be running...", color='blue')
                sleep(5)
            sleep(5)
            cmd = "iptables -F ; yum -y install httpd ; systemctl start httpd"
            sshcmd = k.ssh(bootstrap_helper_name, user='root', tunnel=config.tunnel, insecure=config.insecure, cmd=cmd)
            os.system(sshcmd)
            source, destination = "%s/bootstrap.ign" % clusterdir, "/var/www/html/bootstrap"
            k.scp(bootstrap_helper_name, user='root', source=source, destination=destination, tunnel=config.tunnel,
                  download=False)
            sedcmd = 'sed "s@https://api-int.%s.%s:22623/config/master@http://%s/bootstrap@" ' % (cluster, domain,
                                                                                                  bootstrap_api_ip)
            sedcmd += '%s/master.ign' % clusterdir
            sedcmd += ' > %s/bootstrap.ign' % clusterdir
            call(sedcmd, shell=True)
        sedcmd = 'sed -i "s@https://api-int.%s.%s:22623/config@http://%s:8080@"' % (cluster, domain, api_ip)
        sedcmd += ' %s/master.ign %s/worker.ign' % (clusterdir, clusterdir)
        call(sedcmd, shell=True)
    if platform in cloudplatforms:
        bootstrap_helper_name = "%s-bootstrap-helper" % cluster
        overrides = {'reservedns': True, 'domain': '%s.%s' % (cluster, domain), 'tags': [tag], 'plan': cluster,
                     'nets': [network]}
        config.create_vm("%s-bootstrap-helper" % cluster, helper_image, overrides=overrides)
        status = ""
        while status != "running":
            status = k.info(bootstrap_helper_name).get('status')
            pprint("Waiting 5s for bootstrap helper node to be running...", color='blue')
            sleep(5)
        sleep(5)
        cmd = "iptables -F ; yum -y install httpd ; systemctl start httpd"
        sshcmd = k.ssh(bootstrap_helper_name, user='root', tunnel=config.tunnel, insecure=config.insecure, cmd=cmd)
        os.system(sshcmd)
        source, destination = "%s/bootstrap.ign" % clusterdir, "/var/www/html/bootstrap"
        k.scp(bootstrap_helper_name, user='root', source=source, destination=destination, tunnel=config.tunnel,
              download=False)
        sedcmd = 'sed "s@https://api-int.%s.%s:22623/config/master@' % (cluster, domain)
        sedcmd += 'http://%s-bootstrap-helper.%s.%s/bootstrap@ "' % (cluster, domain)
        sedcmd += '%s/master.ign' % clusterdir
        sedcmd += ' > %s/bootstrap.ign' % clusterdir
        call(sedcmd, shell=True)
    if platform in virtplatforms:
        config.plan(cluster, inputfile='ocp.yml', overrides=paramdata)
        call('openshift-install --dir=%s wait-for bootstrap-complete || exit 1' % clusterdir, shell=True)
        todelete = ["%s-bootstrap" % cluster]
        if platform in ['kubevirt', 'openstack', 'vsphere']:
            todelete.append("%s-bootstrap-helper" % cluster)
        for vm in todelete:
            pprint("Deleting %s" % vm)
            k.delete(vm)
    else:
        config.plan(cluster, inputfile='ocp_cloud.yml', overrides=paramdata)
        call('openshift-install --dir=%s wait-for bootstrap-complete || exit 1' % clusterdir, shell=True)
        todelete = ["%s-bootstrap" % cluster, "%s-bootstrap-helper" % cluster]
        for vm in todelete:
            pprint("Deleting %s" % vm)
            k.delete(vm)
    if workers > 0:
        call("oc adm taint nodes -l node-role.kubernetes.io/master node-role.kubernetes.io/master:NoSchedule-",
             shell=True)
    installcommand = 'openshift-install --dir=%s wait-for install-complete' % clusterdir
    installcommand = "%s | %s" % (installcommand, installcommand)
    pprint("Launching install-complete step. Note it will be retried one extra time in case of timeouts", color='blue')
    call(installcommand, shell=True)
    pprint("Deploying certs autoapprover cronjob", color='blue')
    if platform in virtplatforms:
        copy2("%s/worker.ign" % clusterdir, "%s/worker.ign.ori" % clusterdir)
        with open("%s/worker.ign" % clusterdir, 'w') as w:
            workerdata = insecure_fetch("https://api.%s.%s:22623/config/worker" % (cluster, domain))
            w.write(str(workerdata))
    call("oc create -f autoapprovercron.yml", shell=True)
    if ocdownloaded and macosx and os.path.exists('/i_am_a_container'):
        occmd = "curl -s https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/maxosx/oc.tar.gz"
        occmd += "| tar zxf - oc"
        occmd += "; chmod 700 oc"
        call(occmd, shell=True)
        move('oc', '/workdir/oc')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Openshift deployer leveraring kcli library')
    parser.add_argument('-c', '--clean', help='Clean', action='store_true')
    parser.add_argument('-s', '--scale', help='Scale', action='store_true')
    parser.add_argument('-t', '--template', help='Template', action='store_true')
    parser.add_argument('-w', '--workers', help='Total number of workers (used when scaling)', type=int)
    parser.add_argument('paramfile', help='Parameter file')
    args = parser.parse_args()
    workers = args.workers
    action_scale = args.scale
    action_clean = args.clean
    action_template = args.template
    paramfile = args.paramfile
    if os.path.exists('/i_am_a_container'):
        os.environ['PATH'] = '/:/workdir:%s' % os.environ['PATH']
        paramfile = '/workdir/%s' % paramfile
    if action_clean:
        clean(paramfile)
    elif action_scale:
        scale(paramfile, workers)
    elif action_template:
        template(paramfile)
    else:
        deploy(paramfile)
