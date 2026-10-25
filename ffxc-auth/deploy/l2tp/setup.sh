#!/usr/bin/env bash
#
# L2TP/IPsec endpoint for the relay profile.
#
# iOS speaks L2TP with a pre-shared key and MSCHAPv2. That is two packages on
# the server (strongswan + xl2tpd) and no certificate infrastructure, which is
# why the profile ships this instead of IKEv2 EAP.
#
# Run as root on the same VPS as the relay:
#
#   VPN_USER=sophia-xxxx VPN_PASSWORD='...' IPSEC_PSK='...' \
#     RELAY_PORT=1299 bash deploy/l2tp/setup.sh
#
# Then put the same three values into ffxc-auth/.env as RELAY_L2TP_USER,
# RELAY_L2TP_PASSWORD and RELAY_IPSEC_SECRET, with RELAY_VPN_SERVER set to the
# public IP or hostname of this box.

set -euo pipefail

VPN_USER="${VPN_USER:?set VPN_USER}"
VPN_PASSWORD="${VPN_PASSWORD:?set VPN_PASSWORD}"
IPSEC_PSK="${IPSEC_PSK:?set IPSEC_PSK}"
RELAY_PORT="${RELAY_PORT:-1299}"
SUBNET="${SUBNET:-192.168.42.0/24}"
LOCAL_IP="${LOCAL_IP:-192.168.42.1}"
POOL_START="${POOL_START:-192.168.42.10}"
POOL_END="${POOL_END:-192.168.42.99}"
DNS_PRIMARY="${DNS_PRIMARY:-1.1.1.1}"
DNS_SECONDARY="${DNS_SECONDARY:-9.9.9.9}"

if [[ $EUID -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

PUBLIC_IF="$(ip -4 route show default | awk '{print $5; exit}')"
if [[ -z "$PUBLIC_IF" ]]; then
  echo "cannot detect the default interface" >&2
  exit 1
fi

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq strongswan strongswan-pki xl2tpd ppp iptables iproute2

echo "== ipsec"
cat >/etc/ipsec.conf <<EOF
config setup
    uniqueids=no
    charondebug="ike 1, knl 1, cfg 0"

conn L2TP-PSK
    keyexchange=ikev1
    authby=secret
    type=transport
    left=%defaultroute
    leftid=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    rightsubnet=v4:${SUBNET}
    auto=add
    dpddelay=30
    dpdtimeout=120
    dpdaction=clear
    ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
    esp=aes256-sha1,aes128-sha1,3des-sha1!
EOF

umask 077
cat >/etc/ipsec.secrets <<EOF
: PSK "${IPSEC_PSK}"
EOF
umask 022

echo "== xl2tpd"
mkdir -p /var/run/xl2tpd
cat >/etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = yes
saref refinfo = 30
debug avp = no
debug network = no
debug state = no
debug tunnel = no

[lns default]
ip range = ${POOL_START}-${POOL_END}
local ip = ${LOCAL_IP}
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = no
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

cat >/etc/ppp/options.xl2tpd <<EOF
require-mschap-v2
ms-dns ${DNS_PRIMARY}
ms-dns ${DNS_SECONDARY}
asyncmap 0
auth
crtscts
lock
hide-password
modem
mtu 1400
mru 1400
name l2tpd
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
noccp
novj
nodefaultroute
EOF

umask 077
cat >/etc/ppp/chap-secrets <<EOF
# client        server  secret          IP addresses
"${VPN_USER}"   l2tpd   "${VPN_PASSWORD}"   *
EOF
umask 022

echo "== forwarding + nat"
sysctl -qw net.ipv4.ip_forward=1
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >>/etc/sysctl.conf

iptables -t nat -C POSTROUTING -s "$SUBNET" -o "$PUBLIC_IF" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$PUBLIC_IF" -j MASQUERADE

for port in 500 4500; do
  iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null \
    || iptables -A INPUT -p udp --dport "$port" -j ACCEPT
done
iptables -C INPUT -p udp --dport 1701 -j ACCEPT 2>/dev/null \
  || iptables -A INPUT -p udp --dport 1701 -j ACCEPT
# The proxy port itself is only reachable through the tunnel, so it is opened
# for the VPN pool rather than for the world.
iptables -C INPUT -s "$SUBNET" -p tcp --dport "$RELAY_PORT" -j ACCEPT 2>/dev/null \
  || iptables -A INPUT -s "$SUBNET" -p tcp --dport "$RELAY_PORT" -j ACCEPT
iptables -C FORWARD -s "$SUBNET" -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -s "$SUBNET" -j ACCEPT
iptables -C FORWARD -d "$SUBNET" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -d "$SUBNET" -m state --state RELATED,ESTABLISHED -j ACCEPT

if dpkg -l netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save >/dev/null
else
  echo "note: install iptables-persistent to keep the rules across reboots"
fi

echo "== services"
systemctl enable --now strongswan-starter >/dev/null 2>&1 || systemctl enable --now strongswan >/dev/null 2>&1
systemctl restart strongswan-starter 2>/dev/null || systemctl restart strongswan
systemctl enable --now xl2tpd
systemctl restart xl2tpd

echo
echo "done. relay profile env:"
echo "  RELAY_VPN_MODE=l2tp"
echo "  RELAY_VPN_SERVER=$(curl -s --max-time 5 https://api.ipify.org || echo '<public-ip>')"
echo "  RELAY_L2TP_USER=${VPN_USER}"
echo "  RELAY_L2TP_PASSWORD=<the password you passed in>"
echo "  RELAY_IPSEC_SECRET=<the psk you passed in>"
echo
echo "check: ipsec statusall | xl2tpd -D (debug)"
