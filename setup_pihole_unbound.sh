#!/bin/bash

# --- SYSTEM PREP ---
echo "🔹 Updating system..."
sudo apt update && sudo apt upgrade -y
sudo apt install curl htop ufw -y

# --- PI-HOLE INSTALLATION ---
echo "🔹 Installing Pi-hole..."
curl -sSL https://install.pi-hole.net | bash

# --- PI-HOLE ADMIN PASSWORD ---
echo "🔹 Set a strong Pi-hole admin password..."
echo "Run: pihole setpassword"

# --- VERIFY SERVICES ---
echo "🔹 Checking Pi-hole service..."
sudo systemctl status pihole-FTL --no-pager -l

# --- UNBOUND INSTALLATION ---
echo "🔹 Installing Unbound..."
sudo apt install unbound -y

# --- CREATE UNBOUND CONFIG ---
echo "🔹 Creating Unbound configuration for Pi-hole..."
sudo tee /etc/unbound/unbound.conf.d/pi-hole.conf > /dev/null <<EOF
server:
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    root-hints: "/var/lib/unbound/root.hints"
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes
    unwanted-reply-threshold: 10000
    use-caps-for-id: no
    cache-min-ttl: 3600
    cache-max-ttl: 86400
    prefetch: yes
EOF

# --- ENABLE UNBOUND SERVICE ---
echo "🔹 Enabling and starting Unbound..."
sudo systemctl restart unbound
sudo systemctl enable unbound

# --- VERIFY UNBOUND PORTS ---
echo "🔹 Verifying Unbound is listening on port 5335..."
sudo ss -lntup | grep 5335

# --- FIREWALL HARDENING ---
echo "🔹 Configuring UFW firewall rules..."
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow local network access (replace 192.x.x.x/24 if needed)
sudo ufw allow from 192.x.x.x/24 to any port 22 proto tcp
sudo ufw allow from 192.x.x.x/24 to any port 53 proto tcp
sudo ufw allow from 192.x.x.x/24 to any port 53 proto udp
sudo ufw allow from 192.x.x.x/24 to any port 67 proto udp
sudo ufw allow from 192.x.x.x/24 to any port 68 proto udp
sudo ufw allow from 192.x.x.x/24 to any port 80 proto tcp
sudo ufw allow from 192.x.x.x/24 to any port 443 proto tcp

# Enable firewall
sudo ufw enable
sudo ufw status numbered

# --- TESTING COMMANDS ---
echo "🔹 Testing Unbound DNS resolution..."
dig apple.ca @127.0.0.1 -p 5335
dig +dnssec sigok.verteiltesysteme.net @127.0.0.1 -p 5335
dig +dnssec dnssec-failed.org @127.0.0.1 -p 5335

# --- SERVICE CHECKS ---
echo "🔹 Checking services..."
sudo systemctl status pihole-FTL --no-pager -l
sudo systemctl status unbound --no-pager -l

# --- LOG MONITORING ---
echo "🔹 Monitor Pi-hole logs with:"
echo "pihole -t"
echo "sudo journalctl -u unbound -f"
echo "sudo journalctl -u pihole-FTL -f"

# --- FINISHED ---
echo "Setup complete! Configure Pi-hole DNS upstream to: 127.0.0.1#5335"
echo "Visit: http://<your_pi_ip>/admin"
