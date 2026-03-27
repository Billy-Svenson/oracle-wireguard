#######################################################
# WireGuard VPN Server on Oracle Cloud Free Tier
# oracle_wireguard_bilguun_2026_03_26.sh
#######################################################

#######################################################
# Prerequisites
#######################################################

# - Oracle Cloud Free Tier account with E2.Micro instance running Ubuntu 22.04
# - SSH access to the instance
# - Oracle Security List: UDP port 51820 open (done in Step 2)
#
# Network layout:
# Server (Oracle):     10.0.0.1  — YOUR_ORACLE_PUBLIC_IP
# Windows PC client:   10.0.0.2
# Phone client:        10.0.0.3

#######################################################
# Step 1 — System Update
#######################################################

# - SSH into Oracle VM
ssh ubuntu@YOUR_ORACLE_PUBLIC_IP

# - Update system
sudo apt update && sudo apt upgrade -y
# Kernel upgrade dialog appears → press OK
# Daemons restart dialog appears → press OK

# - Reboot to apply kernel update
sudo reboot

# - Reconnect after 30 seconds
ssh ubuntu@YOUR_ORACLE_PUBLIC_IP

#######################################################
# Step 2 — Open Port in Oracle Console (browser)
#######################################################

# -(login to Oracle Cloud Console)
https://cloud.oracle.com

# -Networking → Virtual Cloud Networks → Your VCN
# -Security Lists → Default Security List
# -Add Ingress Rules
"Add Ingress Rule"
Source CIDR: "0.0.0.0/0"
IP Protocol: "UDP"
Destination Port Range: "51820"
"Add Ingress Rules"

#######################################################
# Step 3 — Install WireGuard
#######################################################

# - Check if WireGuard is already installed
sudo apt install wireguard -y
# Reading package lists... Done
# wireguard is already the newest version (1.0.20210914-1ubuntu2).
# 0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.

# - Enable IP forwarding so traffic can route through the server
sudo sysctl -w net.ipv4.ip_forward=1
# net.ipv4.ip_forward = 1

echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
# net.ipv4.ip_forward=1

#######################################################
# Step 4 — Generate Keys
#######################################################

# - Generate server keypair
wg genkey | sudo tee /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key
# AsCRidFuSVMTWv6sTZbcgPLiJQYfSV0JaVqZMaDFP14=

sudo chmod 600 /etc/wireguard/server_private.key

# - View server keys
sudo cat /etc/wireguard/server_public.key
# AsCRidFuSVMTWv6sTZbcgPLiJQYfSV0JaVqZMaDFP14=

sudo cat /etc/wireguard/server_private.key
# SLk4razoAO569CXXFpWATpKES9iOLlUVPaphpp2HE1o=

# - Generate Windows PC keypair
wg genkey | sudo tee /etc/wireguard/pc_private.key | wg pubkey | sudo tee /etc/wireguard/pc_public.key
# tuphClcgK6W/6r3wKqMwCTuY17FpNkV0e8TwWg2KbUU=

sudo cat /etc/wireguard/pc_private.key
# MEwj7eWelUIW+4vwI4aF+hJqPdLsqJYnVbxATBYDz1Y=

sudo cat /etc/wireguard/pc_public.key
# tuphClcgK6W/6r3wKqMwCTuY17FpNkV0e8TwWg2KbUU=

# - Generate phone keypair
wg genkey | sudo tee /etc/wireguard/phone_private.key | wg pubkey | sudo tee /etc/wireguard/phone_public.key
# MA86OpG+nD1b3w9DyTRRxMmkwu4i0amup7ESNd+va0A=

sudo cat /etc/wireguard/phone_private.key
# iNPglEz9+It4HqM/0VC9wSTIpcOBfisrjT/elY1mZFY=

sudo cat /etc/wireguard/phone_public.key
# MA86OpG+nD1b3w9DyTRRxMmkwu4i0amup7ESNd+va0A=

# NOTE: Keys are generated ON the server then distributed to devices
# Each device gets its own unique keypair — never reuse keys

#######################################################
# Step 5 — Check Network Interface Name
#######################################################

# - Find the main network interface (needed for PostUp/PostDown rules)
ip -o link show | awk '{print $2}' | grep -v lo
# ens3:
# tailscale0:
# docker0:
# → Main interface is ens3 — use this in wg0.conf PostUp/PostDown

#######################################################
# Step 6 — Create Server Config
#######################################################

sudo nano /etc/wireguard/wg0.conf

# File contents:
# [Interface]
# PrivateKey = SLk4razoAO569CXXFpWATpKES9iOLlUVPaphpp2HE1o=
# Address = 10.0.0.1/24
# ListenPort = 51820
# PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
# PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
#
# [Peer]
# # Windows PC
# PublicKey = tuphClcgK6W/6r3wKqMwCTuY17FpNkV0e8TwWg2KbUU=
# AllowedIPs = 10.0.0.2/32
#
# [Peer]
# # Phone
# PublicKey = MA86OpG+nD1b3w9DyTRRxMmkwu4i0amup7ESNd+va0A=
# AllowedIPs = 10.0.0.3/32

sudo chmod 600 /etc/wireguard/wg0.conf

#######################################################
# Step 7 — Fix Oracle iptables (critical)
#######################################################

# Oracle VMs ship with a REJECT all rule at the bottom of iptables
# The Oracle Security List alone is NOT enough — must add rules inside VM
# Without this: packets arrive but get dropped with "admin prohibited"

# - Allow WireGuard port
sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT

# - Allow packet forwarding (required for internet routing through VPN)
sudo iptables -I FORWARD -i wg0 -j ACCEPT
sudo iptables -I FORWARD -o wg0 -j ACCEPT

# - Save rules so they survive reboot
sudo apt install iptables-persistent -y
sudo netfilter-persistent save
# run-parts: executing /usr/share/netfilter-persistent/plugins.d/15-ip4tables save
# run-parts: executing /usr/share/netfilter-persistent/plugins.d/25-ip6tables save

# - Verify rules saved
sudo cat /etc/iptables/rules.v4 | grep 51820
# -A INPUT -p udp -m udp --dport 51820 -j ACCEPT

sudo iptables -L FORWARD -v -n | grep wg0
# ACCEPT  all -- wg0  any  anywhere  anywhere
# ACCEPT  all -- any  wg0  anywhere  anywhere

#######################################################
# Step 8 — Start WireGuard
#######################################################

sudo systemctl enable wg-quick@wg0
# Created symlink /etc/systemd/system/multi-user.target.wants/wg-quick@wg0.service

sudo systemctl start wg-quick@wg0

# - Verify running
sudo wg show
# interface: wg0
#   public key: AsCRidFuSVMTWv6sTZbcgPLiJQYfSV0JaVqZMaDFP14=
#   private key: (hidden)
#   listening port: 51820
#
# peer: tuphClcgK6W/6r3wKqMwCTuY17FpNkV0e8TwWg2KbUU=
#   allowed ips: 10.0.0.2/32
#
# peer: MA86OpG+nD1b3w9DyTRRxMmkwu4i0amup7ESNd+va0A=
#   allowed ips: 10.0.0.3/32

#######################################################
# Step 9 — Windows PC Client Config
#######################################################

# - Download WireGuard for Windows
https://wireguard.com/install

# - Install and open WireGuard
"Add Tunnel" → "Create from scratch"

# - Paste this config, name it Oracle-VPN, save
# [Interface]
# PrivateKey = MEwj7eWelUIW+4vwI4aF+hJqPdLsqJYnVbxATBYDz1Y=
# Address = 10.0.0.2/24
# DNS = 1.1.1.1
#
# [Peer]
# PublicKey = AsCRidFuSVMTWv6sTZbcgPLiJQYfSV0JaVqZMaDFP14=
# Endpoint = YOUR_ORACLE_PUBLIC_IP:51820
# AllowedIPs = 0.0.0.0/0
# PersistentKeepalive = 25
#
# AllowedIPs = 0.0.0.0/0   → full tunnel (all traffic via VPN)
# AllowedIPs = 10.0.0.0/24 → split tunnel (VPN network only, normal internet)

"Activate"

#######################################################
# Step 10 — Phone Client Config
#######################################################

# - Install WireGuard app on phone (iOS or Android)
# - Add tunnel → Create from scratch
# - Enter manually or scan QR code

# [Interface]
# PrivateKey = iNPglEz9+It4HqM/0VC9wSTIpcOBfisrjT/elY1mZFY=
# Address = 10.0.0.3/24
# DNS = 1.1.1.1
#
# [Peer]
# PublicKey = AsCRidFuSVMTWv6sTZbcgPLiJQYfSV0JaVqZMaDFP14=
# Endpoint = YOUR_ORACLE_PUBLIC_IP:51820
# AllowedIPs = 0.0.0.0/0
# PersistentKeepalive = 25

"Save" → "Activate"

#######################################################
# Verification
#######################################################

# - Check handshake and traffic on server after clients connect
sudo wg show
# interface: wg0
#   public key: AsCRidFuSVMTWv6sTZbcgPLiJQYfSV0JaVqZMaDFP14=
#   private key: (hidden)
#   listening port: 51820
#
# peer: tuphClcgK6W/6r3wKqMwCTuY17FpNkV0e8TwWg2KbUU=
#   allowed ips: 10.0.0.2/32
#   latest handshake: 1 minute, 23 seconds ago
#   transfer: 4.50 MiB received, 2.10 MiB sent
#
# peer: MA86OpG+nD1b3w9DyTRRxMmkwu4i0amup7ESNd+va0A=
#   endpoint: 95.193.151.100:28409
#   allowed ips: 10.0.0.3/32
#   latest handshake: 9 hours, 31 minutes, 10 seconds ago
#   transfer: 136.37 KiB received, 19.24 KiB sent

# - Verify from client device
# Open browser → whatismyip.com
# Should show Oracle's IP, not your home/mobile IP ✓

#######################################################
# Troubleshooting
#######################################################

# - Watch live WireGuard traffic
sudo tcpdump -i any udp port 51820
# Look for both In AND Out packets
# Only In = server not responding = likely iptables blocking

# - Watch traffic inside the tunnel
sudo tcpdump -i wg0
# If you see "admin prohibited" responses = FORWARD rules missing
# Fix: sudo iptables -I FORWARD -i wg0 -j ACCEPT
#      sudo iptables -I FORWARD -o wg0 -j ACCEPT

# - Check WireGuard logs
sudo journalctl -u wg-quick@wg0 -f

# - Add a new device without restarting WireGuard
sudo wg set wg0 peer NEW_CLIENT_PUBLIC_KEY allowed-ips 10.0.0.4/32
# Also add [Peer] block to /etc/wireguard/wg0.conf for persistence

#######################################################
# Service Management
#######################################################

# - Check status
sudo systemctl status wg-quick@wg0

# - Restart
sudo wg-quick down wg0 && sudo wg-quick up wg0

# - View active connections
sudo wg show

ggwp
