###########################################################
# WireGuard VPN Server — Oracle Cloud Free Tier
# Self-hosted VPN with full internet routing
###########################################################

################# - Architecture - ########################
# Server:  Oracle E2.Micro (Ubuntu 22.04) — YOUR_ORACLE_PUBLIC_IP
# Protocol: WireGuard (UDP 51820)
# Network:  10.0.0.0/24
#   Server:     10.0.0.1
#   Windows PC: 10.0.0.2
#   Phone:      10.0.0.3
#
# Client configs:
#   AllowedIPs = 0.0.0.0/0  → full tunnel (all traffic via VPN)
#   AllowedIPs = 10.0.0.0/24 → split tunnel (VPN network only)

################# - Requirements - ########################
# - Oracle Cloud Free Tier account
# - Ubuntu 22.04 VM (E2.Micro) with public IP
# - Oracle Security List: UDP 51820 open
# - SSH access to Oracle VM

###########################################################
# Step 1 — System Update
###########################################################

ssh ubuntu@YOUR_ORACLE_PUBLIC_IP
sudo apt update && sudo apt upgrade -y
# → Kernel upgrade dialog: press OK
# → Daemons restart dialog: press OK
sudo reboot
# Wait 30 seconds then reconnect:
ssh ubuntu@YOUR_ORACLE_PUBLIC_IP

###########################################################
# Step 2 — Install WireGuard
###########################################################

sudo apt install wireguard -y

# Enable IP forwarding (allows traffic to route through server)
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

###########################################################
# Step 3 — Generate Server Keys
###########################################################

wg genkey | sudo tee /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key
sudo chmod 600 /etc/wireguard/server_private.key

sudo cat /etc/wireguard/server_public.key
# → Keep this — needed in all client configs

sudo cat /etc/wireguard/server_private.key
# → Keep this — goes in server wg0.conf

###########################################################
# Step 4 — Generate Client Keys (one per device)
###########################################################

# Windows PC:
wg genkey | sudo tee /etc/wireguard/pc_private.key | wg pubkey | sudo tee /etc/wireguard/pc_public.key

# Phone:
wg genkey | sudo tee /etc/wireguard/phone_private.key | wg pubkey | sudo tee /etc/wireguard/phone_public.key

# View all keys:
sudo cat /etc/wireguard/pc_private.key
sudo cat /etc/wireguard/pc_public.key
sudo cat /etc/wireguard/phone_private.key
sudo cat /etc/wireguard/phone_public.key

# NOTE: Generate keys ON the server, then distribute to devices
# Each device gets its own unique keypair — never reuse keys

###########################################################
# Step 5 — Server Config
###########################################################

# Check your network interface name first:
ip -o link show | awk '{print $2}' | grep -v lo
# → ens3 (update PostUp/PostDown if different)

sudo nano /etc/wireguard/wg0.conf
# Paste:
# [Interface]
# PrivateKey = YOUR_SERVER_PRIVATE_KEY
# Address = 10.0.0.1/24
# ListenPort = 51820
# PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
# PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
#
# [Peer]
# # Windows PC
# PublicKey = YOUR_PC_PUBLIC_KEY
# AllowedIPs = 10.0.0.2/32
#
# [Peer]
# # Phone
# PublicKey = YOUR_PHONE_PUBLIC_KEY
# AllowedIPs = 10.0.0.3/32

sudo chmod 600 /etc/wireguard/wg0.conf

###########################################################
# Step 6 — Oracle Security List (browser)
###########################################################

# cloud.oracle.com → Networking → Virtual Cloud Networks
# → Your VCN → Security Lists → Default Security List
# → Add Ingress Rule:
#   Source CIDR:      0.0.0.0/0
#   IP Protocol:      UDP
#   Destination Port: 51820
# → Add Ingress Rule

###########################################################
# Step 7 — Fix iptables (Oracle blocks by default)
###########################################################

# Oracle VMs ship with iptables rules that block everything
# by default — must explicitly allow WireGuard and forwarding

# Allow WireGuard port:
sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT

# Allow packet forwarding (required for internet routing):
sudo iptables -I FORWARD -i wg0 -j ACCEPT
sudo iptables -I FORWARD -o wg0 -j ACCEPT

# Save rules permanently (survive reboot):
sudo apt install iptables-persistent -y
sudo netfilter-persistent save

# Verify:
sudo iptables -L INPUT -v -n | grep 51820
sudo iptables -L FORWARD -v -n | grep wg0
# → Both should show ACCEPT rules

# NOTE: This was the main gotcha — Oracle's iptables has a
# REJECT all rule at the bottom. Without explicitly inserting
# ACCEPT rules before it, all WireGuard traffic gets blocked
# with "admin prohibited" even if Oracle Security List is open.

###########################################################
# Step 8 — Start WireGuard
###########################################################

sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Verify running:
sudo wg show
# → Should show interface wg0 with listening port 51820
# → Should show both peers listed

###########################################################
# Step 9 — Client Configs
###########################################################

# Windows PC config (save as Oracle-VPN.conf, import in WireGuard app):
# [Interface]
# PrivateKey = YOUR_PC_PRIVATE_KEY
# Address = 10.0.0.2/24
# DNS = 1.1.1.1
#
# [Peer]
# PublicKey = YOUR_SERVER_PUBLIC_KEY
# Endpoint = YOUR_ORACLE_PUBLIC_IP:51820
# AllowedIPs = 0.0.0.0/0    ← full tunnel (all traffic via VPN)
# PersistentKeepalive = 25

# Phone config (enter manually in WireGuard app or scan QR):
# [Interface]
# PrivateKey = YOUR_PHONE_PRIVATE_KEY
# Address = 10.0.0.3/24
# DNS = 1.1.1.1
#
# [Peer]
# PublicKey = YOUR_SERVER_PUBLIC_KEY
# Endpoint = YOUR_ORACLE_PUBLIC_IP:51820
# AllowedIPs = 0.0.0.0/0    ← full tunnel
# PersistentKeepalive = 25

# Split tunnel alternative (only route VPN network, keep normal internet):
# AllowedIPs = 10.0.0.0/24

###########################################################
# Step 10 — Install WireGuard on Windows
###########################################################

# Download: wireguard.com/install
# Install → Add Tunnel → Import from file
# Select your .conf file → Activate

###########################################################
# Verification
###########################################################

# On Oracle — check active peers and traffic:
sudo wg show
# → Should show latest handshake timestamp
# → Should show transfer bytes increasing

# Test from client device:
# → Browser: whatismyip.com → should show Oracle's IP
# → Not your home/mobile IP

###########################################################
# Service Management
###########################################################

# Check status:
sudo systemctl status wg-quick@wg0
sudo wg show

# Restart:
sudo wg-quick down wg0 && sudo wg-quick up wg0

# View logs:
sudo journalctl -u wg-quick@wg0 -f

# Add new peer (no restart needed):
sudo wg set wg0 peer NEW_CLIENT_PUBLIC_KEY allowed-ips 10.0.0.4/32
# Also add to wg0.conf so it persists after reboot

###########################################################
# Troubleshooting
###########################################################

# Packets arriving but no response (admin prohibited):
# → iptables REJECT rule blocking traffic
# → Fix: sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT
# → Fix: sudo iptables -I FORWARD -i wg0 -j ACCEPT
# → Fix: sudo iptables -I FORWARD -o wg0 -j ACCEPT
# → Fix: sudo netfilter-persistent save

# Tunnel connects but no internet:
# → Forwarding rules missing
# → Check: sudo iptables -L FORWARD -v -n
# → Should show ACCEPT for wg0 in/out

# No handshake at all:
# → Key mismatch — verify client public key matches peer in wg0.conf
# → Verify: echo "CLIENT_PRIVATE_KEY" | wg pubkey
# →   output must match peer PublicKey in wg0.conf

# Packets arriving on ens3 but not processed by WireGuard:
# → Oracle Security List rule missing UDP 51820
# → Check Oracle Console → VCN → Security Lists → Ingress Rules

# Diagnose live:
sudo tcpdump -i any udp port 51820    # watch all WireGuard traffic
sudo tcpdump -i wg0                   # watch traffic inside tunnel
sudo tcpdump -i ens3 -n               # watch all ens3 traffic
