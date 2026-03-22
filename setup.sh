#!/bin/bash

set -e

clear

echo "███    ███  ██████  ██   ██ ██    ██     ██████  ██████  ██ ██████   ██████  ███████"
echo "████  ████ ██    ██  ██ ██   ██  ██      ██   ██ ██   ██ ██ ██   ██ ██       ██     "
echo "██ ████ ██ ██    ██   ███     ████       ██████  ██████  ██ ██   ██ ██   ███ █████  "
echo "██  ██  ██ ██    ██  ██ ██     ██        ██   ██ ██   ██ ██ ██   ██ ██    ██ ██     "
echo "██      ██  ██████  ██   ██    ██        ██████  ██   ██ ██ ██████   ██████  ███████"
echo ""
echo "Script by Kitty (exi3a)"

VM_BRIDGE="vmbr1"
UPLINK_BRIDGE="vmbr0"
SUBNET="10.10.0.0/24"
GATEWAY_IP="10.10.0.1"

CIDR="${SUBNET#*/}"
NETWORK="${SUBNET%/*}"

ip2int() {
  local IFS=.
  read -r a b c d <<< "$1"
  echo $(( (a<<24) + (b<<16) + (c<<8) + d ))
}

int2ip() {
  local ip=$1
  echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"
}

MASK_INT=$(( 0xFFFFFFFF << (32 - CIDR) & 0xFFFFFFFF ))
MASK=$(int2ip $MASK_INT)

NET_INT=$(ip2int "$NETWORK")
BROADCAST_INT=$(( NET_INT | (~MASK_INT & 0xFFFFFFFF) ))

RANGE_START=$(int2ip $(( NET_INT + 1 )))
RANGE_END=$(int2ip $(( BROADCAST_INT - 1 )))

if [[ $EUID -ne 0 ]]; then
  echo "[!] Run as root"
  exit 1
fi

echo "[+] Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y netfilter-persistent iptables-persistent 

echo "[+] Enabling firewall persistence..."
systemctl enable netfilter-persistent
systemctl start netfilter-persistent

echo "[+] Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ipforward.conf
sysctl -p /etc/sysctl.d/99-ipforward.conf

echo "[+] Checking bridge $VM_BRIDGE..."

if ! ip link show "$VM_BRIDGE" &>/dev/null; then
  echo "[+] Creating $VM_BRIDGE..."

  cat >> /etc/network/interfaces <<EOF

auto $VM_BRIDGE
iface $VM_BRIDGE inet static
    address $GATEWAY_IP/$CIDR
    bridge-ports none
    bridge-stp off
    bridge-fd 0
EOF

  echo "[+] Reloading network..."
  ifreload -a || systemctl restart networking
else
  echo "[✓] $VM_BRIDGE already exists"
fi

echo "[+] Backing up current firewall..."
iptables-save > /root/firewall-backup-$(date +%F-%H%M).v4 || true

echo "[+] Writing firewall rules..."

cat > /etc/iptables/rules.v4 <<EOF
*raw
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT

*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A PREROUTING -m conntrack --ctstate RELATED,ESTABLISHED -j CONNMARK --restore-mark --nfmask 0xff0000 --ctmask 0xff0000
-A OUTPUT -m conntrack --ctstate NEW -m mark ! --mark 0x0/0xff0000 -j CONNMARK --save-mark --nfmask 0xff0000 --ctmask 0xff0000
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s $SUBNET -o $UPLINK_BRIDGE -j MASQUERADE
COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p tcp --dport 8006 -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -s $SUBNET -p tcp --dport 9100 -j ACCEPT
-A INPUT -s $SUBNET -j DROP

-A FORWARD -i $VM_BRIDGE -o $UPLINK_BRIDGE -j ACCEPT
-A FORWARD -i $UPLINK_BRIDGE -o $VM_BRIDGE -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i $VM_BRIDGE -o $VM_BRIDGE -j DROP
-A FORWARD -s $SUBNET ! -i $VM_BRIDGE -j DROP

COMMIT
EOF

echo "[+] Applying firewall..."
iptables-restore < /etc/iptables/rules.v4

echo "[+] Saving firewall rules..."
netfilter-persistent save

echo "[+] Reloading firewall..."
systemctl restart netfilter-persistent

if systemctl is-enabled netfilter-persistent >/dev/null; then
  echo "[✓] Persistence enabled"
else
  echo "[!] Persistence issue"
fi

echo "[✓] Setup complete!"
echo "[✓] Subnet: $NETWORK"
echo "[✓] CIDR: /$CIDR"
echo "[✓] Subnet mask: $MASK"
echo "[✓] Range: $RANGE_START - $RANGE_END"
echo "[✓] Gateway: $GATEWAY_IP"
