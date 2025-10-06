# rpi-pihole-unbound-writeup

## Project Overview

This project deployed a **network-wide ad/tracker blocker** using **Pi-hole** on a RP4, with **Unbound** configured as a recursive DNS resolver.

Because the Bell Giga Hub modem silently blocked the Pi-hole’s MAC when set as the DNS forwarder, the workaround was to **disable DHCP on the Giga Hub** and make Pi-hole the DHCP server. This ensured all clients use Pi-hole for DNS and avoids ISP interference.

The setup was hardened with firewall rules, static IPs, password protections, and DNSSEC validation.

## Base System Setup

1. **Reflash your device of choice, OS I chose to use is Ubuntu Server 24.04.3 LTS 64bit.**
2. Boot Pi and connect to network.
3. SSH into Pi from a management PC:
    
    ```bash
    ssh pi0@192.168.2.xxx
    ```
    
4. Update system Packages
    
    ```bash
    sudo apt update && sudo apt upgrade -y
    ```
    
5. Confirm system uptime and resources
    
    ```bash
    uptime
    htop
    ```
    

---

## Install Pi-hole

1. Run Pi-hole Installer
    
    ```bash
    curl -sSL https://install.pi-hole.net | bash
    ```
    
2. Set Pi-hole IP to a static address(Either through router DHCP settings or modifying /etc/netplan/ config file)
3. Set a strong pi-hole web admin psw
    
    ```bash
    pihole setpassword
    ```
    
4. Verify Pi-hole service
    
    ```bash
    systemctl status pihole-FTL --no-pager -l
    ```
    

---

## Configure Pi-hole as DHCP Server

1. In Pi-hole web UI → **Settings → DHCP**, enable DHCP.
    - Example pool: `192.168.2.100 – 192.168.2.200`
    - Lease time: `24h` (use 5m for testing).
2. Disable DHCP on Bell Giga Hub (or shrink it to a tiny pool for fallback).
3. Verify leases:
    
    ```bash
    cat /etc/pihole/dhcp.leases
    ```
    
    Example line:
    
    ```bash
    1696018800 da:85:ac:25:0c:f8 192.168.2.206 iPhone 01:da:85:ac:25:0c:f8
    ```
    
4. Live-watch DHCP activity:
    
    ```bash
    sudo journalctl -u pihole-FTL -f | grep DHCP
    ```
    

---

## Install and Configure Unbound

1. Install:
    
    ```bash
    sudo apt install unbound -y
    
    ```
    
2. Configure Unbound to listen only on loopback (`127.0.0.1#5335`):
    
    File: `/etc/unbound/unbound.conf.d/pi-hole.conf`
    
    ```
    server:
        verbosity: 0
        interface: 127.0.0.1
        port: 5335
        do-ip4: yes
        do-udp: yes
        do-tcp: yes
        root-hints: "/var/lib/unbound/root.hints"
        auto-trust-anchor-file: "/var/lib/unbound/root.key"
        harden-dnssec-stripped: yes
        harden-referral-path: yes
        use-caps-for-id: yes
    
    ```
    
3. Restart Unbound and enable:
    
    ```bash
    sudo systemctl restart unbound
    sudo systemctl enable unbound
    ```
    
4. Confirm it’s listening:
    
    ```bash
    sudo ss -lntup | grep 5335
    ```
    

---

## Link Pi-hole to Unbound

1. In Pi-hole web UI → **Settings → DNS**:
    - Uncheck public resolvers (Cloudflare, Google, etc.).
    - Add custom upstream: `127.0.0.1#5335`.
2. Restart Pi-hole DNS:
    
    ```bash
    pihole restartdn
    ```
    

---

## Test Unbound + DNSSEC

Check working recursion:

```bash
dig apple.ca @127.0.0.1 -p 5335
```

Check DNSSEC (good domain):

```bash
dig +dnssec sigok.verteiltesysteme.net @127.0.0.1 -p 5335
```

Check DNSSEC (bad domain → should fail):

```bash
dig +dnssec dnssec-failed.org @127.0.0.1 -p 5335
```

---

## Firewall Hardening with UFW

1. Install UFW:
    
    ```bash
    sudo apt install ufw -y
    ```
    
2. Default deny inbound, allow outbound:
    
    ```bash
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    ```
    
3. Allow required services (LAN only):
    
    ```bash
    # SSH
    sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp
    
    # DNS
    sudo ufw allow from 192.168.2.0/24 to any port 53 proto tcp
    sudo ufw allow from 192.168.2.0/24 to any port 53 proto udp
    
    # DHCP
    sudo ufw allow from 192.168.2.0/24 to any port 67 proto udp
    sudo ufw allow from 192.168.2.0/24 to any port 68 proto udp
    
    # Web admin
    sudo ufw allow from 192.168.2.0/24 to any port 80 proto tcp
    sudo ufw allow from 192.168.2.0/24 to any port 443 proto tcp
    ```
    
4. Enable UFW:
    
    ```bash
    sudo ufw enable
    sudo ufw status numbered
    ```
    
5. Confirm listening services:
    
    ```bash
    sudo ss -lntup
    ```
    

---

## Security and Reliability

- **Static IP** set via `/etc/netplan/` on the Pi (critical if Giga Hub DHCP is off).
- **Strong Pi-hole password** set with `pihole setpassword`.
- **Updates enabled**:
    
    ```bash
    sudo apt update && sudo apt upgrade -y
    
    ```
    
- Disabled unnecessary services:
    
    ```bash
    sudo systemctl disable --now avahi-daemon
    sudo systemctl disable --now bluetooth
    
    ```
    

---

## Validation & Monitoring

- View active leases in Pi-hole UI or:
    
    ```bash
    cat /etc/pihole/dhcp.leases
    
    ```
    
- View DNS query log in UI or:
    
    ```bash
    pihole -t
    
    ```
    
- Validate blocking:
    
    ```bash
    dig doubleclick.net @<pi-ip>
    # should return 0.0.0.0 or NODATA
    
    ```
    

---

## Project Outcome

- All LAN devices now receive IPs and DNS from Pi-hole.
- Bell Giga Hub no longer interferes (DHCP moved to Pi-hole).
- DNS queries are filtered (ad/tracker blocking) and resolved securely via Unbound.
- System is hardened with UFW firewall, static IP, updates, and strong access controls.


```mermaid
flowchart LR
    A[Client Device\n(Phone, PC, IoT)] -->|DNS Query| B[Pi-hole\n(Raspberry Pi 4)]
    B -->|Filtered / Blocked Domains| X[Blocked 🚫]
    B -->|Allowed Domains| C[Unbound\nRecursive Resolver]
    C --> D[Root DNS Servers]
    D --> E[TLD DNS Servers\n(.com, .net, .org)]
    E --> F[Authoritative DNS Servers]
    F -->|Final IP Address| C
    C --> B
    B -->|Response| A
