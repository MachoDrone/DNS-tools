#!/bin/bash

# Check if DNS arguments are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <DNS1> <DNS2>"
    echo "Example: $0 8.8.8.8 8.8.4.4"
    exit 1
fi

DNS1=$1
DNS2=$2

# Show DNS entries before the script
echo "DNS server entries before the script:"
cat /etc/resolv.conf | grep "nameserver" || echo "No nameserver entries found."

# Backup resolv.conf
cp /etc/resolv.conf /etc/resolv.conf.bak

# Update DNS entries
echo "nameserver $DNS1" > /etc/resolv.conf
echo "nameserver $DNS2" >> /etc/resolv.conf

# Apply changes immediately (Ubuntu 24.04 uses systemd-resolved)
if systemctl is-active systemd-resolved >/dev/null 2>&1; then
    echo "Restarting systemd-resolved to apply DNS changes..."
    systemctl restart systemd-resolved
else
    echo "systemd-resolved not active. Changes may not apply until reboot or manual service restart."
fi

# Wait briefly for service to restart
sleep 2

# Show DNS entries after the script
echo "DNS server entries after the script:"
cat /etc/resolv.conf | grep "nameserver" || echo "No nameserver entries found."

# Basic test to verify DNS is working
echo "Testing DNS resolution with 'google.com'..."
if ping -c 4 google.com >/dev/null 2>&1; then
    echo "DNS test successful: google.com resolved and pinged."
else
    echo "DNS test failed: Could not resolve or ping google.com."
fi
