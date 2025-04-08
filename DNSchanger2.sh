#!/bin/bash

# Check if at least one DNS argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <DNS1> [DNS2]"
    echo "Example: $0 8.8.8.8 8.8.4.4"
    exit 1
fi

DNS1=$1
DNS2=$2

# Show DNS entries before the script (via systemd-resolved)
echo "DNS server entries before the script:"
resolvectl status | grep "DNS Servers" || echo "No DNS servers found."

# Set new DNS servers using resolvectl
echo "Setting DNS servers to $DNS1${DNS2:+ and $DNS2}..."
resolvectl set-dns global "$DNS1"
[ -n "$DNS2" ] && resolvectl set-dns global "$DNS1 $DNS2"

# Restart systemd-resolved to apply changes
if systemctl is-active systemd-resolved >/dev/null 2>&1; then
    echo "Restarting systemd-resolved to apply DNS changes..."
    systemctl restart systemd-resolved
    sleep 2
else
    echo "systemd-resolved not active. Changes may not apply until reboot."
    exit 1
fi

# Show DNS entries after the script
echo "DNS server entries after the script:"
resolvectl status | grep "DNS Servers" || echo "No DNS servers found."

# Test DNS resolution
echo "Testing DNS resolution with 'google.com'..."
if ping -c 4 google.com >/dev/null 2>&1; then
    echo "DNS test successful: google.com resolved and pinged."
else
    echo "DNS test failed: Could not resolve or ping google.com."
fi
