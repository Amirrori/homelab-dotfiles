#!/bin/bash
# CT 1250 (pterodactyl) firewall: host INPUT + DOCKER-USER (published ports bypass INPUT).
# Idempotent; run by pterodactyl-fw.service at boot before docker.
set -euo pipefail

SELF=10.140.3.15
# Home's devices: LAN, Windows VM, RAS peers (VyOS N_HOME_V4 minus the server CTs).
# Add trusted friends' WireGuard subnet here later.
TRUSTED="10.140.1.0/24 10.140.3.13 10.255.231.100/31 10.255.232.100/31 10.255.235.100/31 10.255.236.100/31"
MGMT=10.140.2.0/24                # PVE/VyOS mgmt VLAN: SSH only
PROXY=10.140.3.16                 # CT 1260 nginx: https://panel.example.com + https://wings.example.com (2026-10-24)
PANEL_NETS=172.30.0.0/16          # panel compose networks (frontend .0/24, backend .1/24)
PANEL_FRONT=172.30.0.0/24
GAME_NET=172.18.0.0/16            # wings pterodactyl_nw
DOCKER_ALL=172.16.0.0/12
PRIVATE="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16"

chain() { # chain <cmd> <name> <parent>: create/flush and hook at top of parent
  $1 -N "$2" 2>/dev/null || $1 -F "$2"
  $1 -C "$3" -j "$2" 2>/dev/null || $1 -I "$3" 1 -j "$2"
}

# --- IPv4 INPUT: services on the CT itself (sshd, wings :8080, sftp :2022)
chain iptables PTERO-IN INPUT
iptables -A PTERO-IN -i lo -j ACCEPT
iptables -A PTERO-IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A PTERO-IN -m conntrack --ctstate INVALID -j DROP
iptables -A PTERO-IN -p icmp -j ACCEPT
iptables -A PTERO-IN -s $PANEL_FRONT -d $SELF -p tcp --dport 8080 -j ACCEPT   # panel -> wings API
iptables -A PTERO-IN -s $PROXY -d $SELF -p tcp --dport 8080 -j ACCEPT         # proxy -> wings (wings.example.com)
for s in $TRUSTED; do
  iptables -A PTERO-IN -s "$s" -d $SELF -p tcp -m multiport --dports 22,2022,8080 -j ACCEPT
done
iptables -A PTERO-IN -s $MGMT -d $SELF -p tcp --dport 22 -j ACCEPT
iptables -A PTERO-IN -j DROP

# --- IPv4 DOCKER-USER: traffic to/from containers (docker hooks it at top of FORWARD)
iptables -N DOCKER-USER 2>/dev/null || iptables -F DOCKER-USER
iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -A DOCKER-USER -m conntrack --ctstate INVALID -j DROP
for s in $TRUSTED; do
  iptables -A DOCKER-USER -i eth0 -s "$s" -d $GAME_NET -j RETURN                      # game ports
  iptables -A DOCKER-USER -i eth0 -s "$s" -d $PANEL_FRONT -p tcp --dport 80 -j RETURN  # panel web
done
iptables -A DOCKER-USER -i eth0 -s $PROXY -d $PANEL_FRONT -p tcp --dport 80 -j RETURN # proxy -> panel web (panel.example.com)
iptables -A DOCKER-USER -i eth0 -j DROP
# east-west within each zone (br_netfilter is on, so bridged traffic hits FORWARD)
iptables -A DOCKER-USER -s $PANEL_NETS -d $PANEL_NETS -j RETURN
iptables -A DOCKER-USER -s $GAME_NET -d $GAME_NET -j RETURN
# panel -> wings goes via https://wings.example.com = the proxy (only exception to the private-space block)
iptables -A DOCKER-USER -s $PANEL_FRONT -d $PROXY -p tcp --dport 443 -j RETURN
# containers never reach private space: PVE/VyOS/IX/community VMs/home LAN/other docker zones
for p in $PRIVATE; do
  iptables -A DOCKER-USER -s $DOCKER_ALL -d "$p" -j DROP
done
iptables -A DOCKER-USER -j RETURN

# --- IPv6: nothing listens for v6 clients; containers get no v6 forwarding at all
chain ip6tables PTERO-IN6 INPUT
ip6tables -A PTERO-IN6 -i lo -j ACCEPT
ip6tables -A PTERO-IN6 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A PTERO-IN6 -m conntrack --ctstate INVALID -j DROP
ip6tables -A PTERO-IN6 -p ipv6-icmp -j ACCEPT
ip6tables -A PTERO-IN6 -j DROP
chain ip6tables PTERO-FWD6 FORWARD
ip6tables -A PTERO-FWD6 -i eth0 -j DROP
ip6tables -A PTERO-FWD6 -o eth0 -j DROP
