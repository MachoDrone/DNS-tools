#!/bin/bash

# Check if at least one DNS argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <DNS1> [DNS2]"
    echo "Example: $0 8.8.8.8 8.8.4.4"
    exit 1
fi

DNS1=$1
DNS2=$2

# Function to get the active network interface
get_interface() {
    ip link | grep -E "state UP" | awk -F: '{print $2}' | tr -d ' ' | head -n 1
}

# Show DNS entries before the script
echo "DNS server entries before the script:"
if systemctl is-active systemd-resolved >/dev/null 2>&1; then
    resolvectl status | grep "DNS Servers" || echo "No DNS servers found."
elif systemctl is-active NetworkManager >/dev/null 2>&1; then
    nmcli dev show | grep "DNS" || echo "No DNS servers found."
else
    cat /etc/resolv.conf | grep "nameserver" || echo "No nameserver entries found."
fi

# Set DNS servers
INTERFACE=$(get_interface)
if [ -z "$INTERFACE" ]; then
    echo "Error: No active network interface found."
    exit 1
fi

if systemctl is-active systemd-resolved >/dev/null 2>&1; then
    echo "Setting DNS servers to $DNS1${DNS2:+ and $DNS2} via systemd-resolved..."
    resolvectl set-dns "$INTERFACE" "$DNS1${DNS2:+ $DNS2}"
    echo "Restarting systemd-resolved to apply DNS changes..."
    systemctl restart systemd-resolved
elif systemctl is-active NetworkManager >/dev/null 2>&1; then
    echo "Setting DNS servers to $DNS1${DNS2:+ and $DNS2} via NetworkManager..."
    nmcli con mod "$(nmcli -t -f NAME con show --active | head -n 1)" ipv4.dns "$DNS1${DNS2:+ $DNS2}"
    nmcli con up "$(nmcli -t -f NAME con show --active | head -n 1)"
    echo "Restarting NetworkManager to apply DNS changes..."
    systemctl restart NetworkManager
else
    echo "No supported DNS service (systemd-resolved or NetworkManager) found."
    echo "Falling back to editing /etc/resolv.conf (may not persist)..."
    cp /etc/resolv.conf /etc/resolv.conf.bak
    echo "nameserver $DNS1" > /etc/resolv.conf
    [ -n "$DNS2" ] && echo "nameserver $DNS2" >> /etc/resolv.conf
fi

# Wait briefly for services to restart
sleep 2

# Show DNS entries after the script
echo "DNS server entries after the script:"
if systemctl is-active systemd-resolved >/dev/null 2>&1; then
    resolvectl status | grep "DNS Servers" || echo "No DNS servers found."
elif systemctl is-active NetworkManager >/dev/null 2>&1; then
    nmcli dev show | grep "DNS" || echo "No DNS servers found."
else
    cat /etc/resolv.conf | grep "nameserver" || echo "No nameserver entries found."
fi

# Test DNS resolution
echo "Testing DNS resolution with 'google.com'..."
if ping -c 4 google.com >/dev/null 2>&1; then
    echo "DNS test successful: google.com resolved and pinged."
else
    echo "DNS test failed: Could not resolve or ping google.com."
fi
