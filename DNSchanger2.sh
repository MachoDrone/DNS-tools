#!/bin/bash

# Check if at least one DNS argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <DNS1> [DNS2]"
    echo "Example: $0 8.8.8.8 8.8.4.4"
    exit 1
fi

DNS1=$1
DNS2=$2

# Function to get the active connection name (for NetworkManager)
get_nm_connection() {
    nmcli -t -f NAME con show --active | head -n 1
}

# Show DNS entries before the script
echo "DNS server entries before the script:"
if systemctl is-active NetworkManager >/dev/null 2>&1; then
    nmcli dev show | grep "DNS" || echo "No DNS servers found."
elif systemctl is-active systemd-resolved >/dev/null 2>&1; then
    resolvectl status | grep "DNS Servers" || echo "No DNS servers found."
else
    cat /etc/resolv.conf | grep "nameserver" || echo "No nameserver entries found."
fi

# Set DNS servers
if systemctl is-active NetworkManager >/dev/null 2>&1; then
    CONN=$(get_nm_connection)
    if [ -z "$CONN" ]; then
        echo "Error: No active NetworkManager connection found."
        exit 1
    fi
    echo "Setting DNS servers to $DNS1${DNS2:+ and $DNS2} via NetworkManager..."
    nmcli con mod "$CONN" ipv4.dns "$DNS1${DNS2:+ $DNS2}"
    nmcli con up "$CONN" >/dev/null 2>&1
    echo "Restarting NetworkManager to apply DNS changes..."
    systemctl restart NetworkManager
elif systemctl is-active systemd-resolved >/dev/null 2>&1; then
    echo "Setting DNS servers to $DNS1${DNS2:+ and $DNS2} via systemd-resolved (manual fallback)..."
    cp /run/systemd/resolve/resolv.conf /run/systemd/resolve/resolv.conf.bak
    echo "nameserver $DNS1" > /run/systemd/resolve/resolv.conf
    [ -n "$DNS2" ] && echo "nameserver $DNS2" >> /run/systemd/resolve/resolv.conf
    echo "Restarting systemd-resolved to apply DNS changes..."
    systemctl restart systemd-resolved
else
    echo "No supported DNS service found. Editing /etc/resolv.conf (may not persist)..."
    cp /etc/resolv.conf /etc/resolv.conf.bak
    echo "nameserver $DNS1" > /etc/resolv.conf
    [ -n "$DNS2" ] && echo "nameserver $DNS2" >> /etc/resolv.conf
fi

# Wait for services to stabilize
sleep 2

# Show DNS entries after the script
echo "DNS server entries after the script:"
if systemctl is-active NetworkManager >/dev/null 2>&1; then
    nmcli dev show | grep "DNS" || echo "No DNS servers found."
elif systemctl is-active systemd-resolved >/dev/null 2>&1; then
    resolvectl status | grep "DNS Servers" || echo "No DNS servers found."
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

# Show network interface statuses, including Docker and Podman
echo -e "\nNetwork interface statuses:"
ip link show | awk '/^[0-9]+:/ {
    iface=$2; sub(/:$/, "", iface);
    state=($3 ~ /UP/ ? "UP" : "DOWN");
    if (iface ~ /^docker[0-9]+/) { desc=" (Docker bridge)" }
    else if (iface ~ /^veth.*@if[0-9]+/) { desc=" (Docker/Podman container interface)" }
    else if (iface ~ /^podman[0-9]*$/) { desc=" (Podman network)" }
    else if (iface ~ /^podman_nested/) { desc=" (Podman in Docker network)" }
    else { desc="" }
    print "  " iface ": " state desc
}'
