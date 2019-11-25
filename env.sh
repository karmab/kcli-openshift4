envname={{ cluster|default('testk') }}
cluster={{ cluster|default('testk') }}
helper_image={{ helper_image|default('CentOS-7-x86_64-GenericCloud.qcow2') }}
helper_sleep={{ helper_sleep|default(15) }}
image={{ image }}
api_ip={{ api_ip }}
public_api_ip={{ public_api_ip }}
bootstrap_api_ip={{ bootstrap_api_ip }}
domain={{ domain|default('karmalabs.com') }}
network="{{ network|default('default') }}"
masters={{ masters|default(1) }}
workers={{ workers|default(0) }}
tag={{ tag|default('cnvlab') }}
pub_key={{ pubkey|default('~/.ssh/id_rsa.pub') }}
pull_secret={{ pull_secret|default('openshift_pull.json') }}
upstream={{ upstream|default(False) }}
force={{ force|default(False) }}
{% if bootstrap_mac is defined and bootstrap_ip is defined and dhcp_ip is defined and dhcp_netmask is defined and dhcp_gateway and dhcp_dns is defined -%}
dhcp_ip={{ dhcp_ip }}
dhcp_netmask={{ dhcp_netmask }}
dhcp_gateway={{ dhcp_gateway }}
dhcp_dns={{ dhcp_dns }}
{%- if bootstrap_helper_mac is defined and bootstrap_helper_ip is defined -%}
node_macs={{ [bootstrap_helper_mac] + [bootstrap_mac] + master_macs + worker_macs }}
node_ips={{ [bootstrap_helper_ip] + [bootstrap_ip] + master_ips + worker_ips + [bootstrap_ip] }}
node_names={{ cluster|ocpnodes(platform, masters, workers) }}
{% elif bootstrap_helper_mac is not defined and bootstrap_helper_ip is not defined %}
node_macs={{ [bootstrap_mac] + master_macs + worker_macs }}
node_ips={{ [bootstrap_ip] + master_ips + worker_ips + [bootstrap_ip] }}
node_names={{ cluster|ocpnodes(platform, masters, workers) }}
{%- endif %}
{%- endif %}
