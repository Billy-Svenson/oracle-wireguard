# oracle-wireguard-vpn

WireGuard VPN server on Oracle Cloud Free Tier. Self-hosted alternative to commercial VPNs — full control, no third party.

## Infrastructure

| Component | Detail |
|---|---|
| Host | Oracle Cloud Free Tier — E2.Micro |
| OS | Ubuntu 22.04 LTS |
| Protocol | WireGuard UDP 51820 |
| Server VPN IP | 10.0.0.1 |

## Clients

| Device | VPN IP |
|---|---|
| Windows PC | 10.0.0.2 |
| Phone | 10.0.0.3 |

## Key Gotcha — Oracle iptables

Oracle VMs have a default `REJECT all` rule. Must explicitly allow:

```bash
sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT
sudo iptables -I FORWARD -i wg0 -j ACCEPT
sudo iptables -I FORWARD -o wg0 -j ACCEPT
sudo netfilter-persistent save
```

## Setup Guide

[docs/01_wireguard_setup.md](docs/01_wireguard_setup.md)
