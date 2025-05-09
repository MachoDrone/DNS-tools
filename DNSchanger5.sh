#!/bin/bash

# DNSchanger.sh: Set DNS servers, extract wallet address, and display system info
# Usage: ./DNSchanger.sh [DNS1] [DNS2]
# Defaults to Cloudflare DNS (1.1.1.1, 1.0.0.1) if no arguments provided

# Set DNS servers from arguments or default to 1.1.1.1 1.0.0.1
DNS1=${1:-1.1.1.1}
DNS2=${2:-1.0.0.1}
DNS_SERVERS="$DNS1 $DNS2"

# Determine Ubuntu type and version
UBUNTU_TYPE=$(if grep -qi microsoft /proc/version; then echo WSL2; else if dpkg -l | grep -q ubuntu-desktop; then echo Desktop; elif dpkg -l | grep -q ubuntu-server; then echo Server; else echo Minimal; fi; fi)
UBUNTU_VERSION=$(lsb_release -rs)

# Extract wallet address from nosana-node logs
WALLET=$(docker logs -t nosana-node 2>/dev/null | grep -E '[A-Za-z0-9]{26,44}' | head -n 1 | awk '{print $NF}')

# Show current DNS and query status
echo "Current DNS Servers:"
resolvectl status | grep "DNS Servers"
dig example.com | grep SERVER

# Configure DNS
sudo bash -c "
  if [ -d /etc/netplan ]; then
    for f in /etc/netplan/*.yaml; do
      cp \"\$f\" \"\$f.bak\"
      sed -i '/nameservers:/,+1d' \"\$f\"
    done
    netplan apply
  fi
  mkdir -p /etc/systemd/resolved.conf.d
  rm -f /etc/systemd/resolved.conf.d/*.conf
  echo -e '[Resolve]\nDNS=$DNS_SERVERS\nDomains=~.\nCache=yes\nLLMNR=no\nMulticastDNS=no' > /etc/systemd/resolved.conf.d/custom_dns.conf
  echo -e '[Resolve]\nDNSStubListener=yes' > /etc/systemd/resolved.conf
  if command -v nmcli > /dev/null; then
    for conn in \$(nmcli -t -f NAME c show --active); do
      nmcli con mod \"\$conn\" ipv4.ignore-auto-dns yes ipv4.dns '' 2>/dev/null
    done
  fi
  systemctl restart systemd-resolved
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  if [ -f /etc/wsl.conf ] && ! grep -q 'systemd=true' /etc/wsl.conf; then
    echo '[boot]\nsystemd=true' >> /etc/wsl.conf
  fi
"

# Show updated DNS and query status
echo "Updated DNS Servers:"
resolvectl status | grep "DNS Servers"
dig example.com | grep SERVER

# Display wallet address
if [ -n "$WALLET" ]; then
  echo "Host Address: $WALLET"
else
  echo "No wallet address found"
fi

# Explain default DNS choice and provide sample command
echo "Default DNS servers (1.1.1.1, 1.0.0.1) chosen for their reliability, privacy, and speed (Cloudflare DNS)."
echo "Sample command with custom DNS: $0 8.8.8.8 8.8.4.4"

# Display Ubuntu version statement
echo "Running on $UBUNTU_TYPE Ubuntu $UBUNTU_VERSION"
