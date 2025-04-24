#!/bin/bash

# Check if arguments are provided
if [ $# -lt 1 ]; then
    echo -e "\033[31mdoing it wrong...\033[0m"
    echo -e "\033[31mExample: wget -O - https://raw.githubusercontent.com/MachoDrone/DNS-tools/refs/heads/main/DNSchanger3.sh | bash -s -- 1.1.1.1 1.0.0.1\033[0m"
    exit 1
fi

# Enable debug tracing
set -x

DNS1="$1"
DNS2="$2"

# Validate DNS1
if ! echo "$DNS1" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^([0-9a-fA-F:]+:[0-9a-fA-F:]+)$' >/dev/null; then
    echo "Error: $DNS1 is not a valid IPv4 or IPv6 address."
    exit 1
fi

# Validate DNS2 if provided
if [ -n "$DNS2" ] && ! echo "$DNS2" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^([0-9a-fA-F:]+:[0-9a-fA-F:]+)$' >/dev/null; then
    echo "Error: $DNS2 is not a valid IPv4 or IPv6 address."
    exit 1
fi

# Function to check network connectivity
check_network() {
    local UP_IFACE=$(ip link show | grep -E '^[0-9]+: (eth|en|wlan|ibp)[0-9a-zA-Z@]+:.*state UP' | awk '{print $2}' | cut -d':' -f1 | head -n1)
    if [ -n "$UP_IFACE" ]; then
        echo "Network interface $UP_IFACE is UP."
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            echo "Internet connectivity confirmed."
            return 0
        else
            echo "Interface $UP_IFACE is UP but cannot reach the internet."
            return 1
        fi
    else
        echo "No network interfaces are UP (excluding loopback and container interfaces)."
        return 1
    fi
}

# Function to test DNS resolution
test_dns() {
    if ! check_network; then
        echo "Cannot test DNS: No network connectivity."
        return 1
    fi
    if command -v dig >/dev/null 2>&1; then
        local TEST_DNS=$(dig +short @${DNS1} google.com | grep -v '^$' | head -n1)
        if echo "$TEST_DNS" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null; then
            echo "DNS resolution test successful with $DNS1."
            return 0
        elif [ -n "$DNS2" ]; then
            TEST_DNS=$(dig +short @${DNS2} google.com | grep -v '^$' | head -n1)
            if echo "$TEST_DNS" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null; then
                echo "DNS resolution test successful with $DNS2."
                return 0
            fi
        fi
    fi
    echo "DNS resolution test failed with the provided DNS servers."
    return 1
}

# Function to compare DNS arguments to ping results and Netplan configuration
compare_and_verify() {
    if ping -c 1 "$DNS1" >/dev/null 2>&1; then
        echo -e "\033[32mPing to $DNS1 successful\033[0m"
    else
        echo -e "\033[31mPing to $DNS1 failed\033[0m"
        return 1
    fi
    if [ -n "$DNS2" ]; then
        if ping -c 1 "$DNS2" >/dev/null 2>&1; then
            echo -e "\033[32mPing to $DNS2 successful\033[0m"
        else
            echo -e "\033[31mPing to $DNS2 failed\033[0m"
            return 1
        fi
    fi
    if sudo grep -q "addresses: \[$DNS1${DNS2:+, $DNS2}\]" /etc/netplan/01-network-manager-all.yaml; then
        echo -e "\033[32mNetplan configuration matches provided DNS servers\033[0m"
    else
        echo -e "\033[31mNetplan configuration does not match provided DNS servers\033[0m"
        return 1
    fi
    return 0
}

# Restart network services
restart_network() {
    if systemctl is-active --quiet NetworkManager; then
        sudo systemctl restart NetworkManager
    elif command -v service >/dev/null 2>&1; then
        sudo service networking restart 2>/dev/null || true
    fi
    sleep 2
}

# Main logic
echo -e "\033[34mChecking for systemd-resolved...\033[0m"
if systemctl is-active --quiet systemd-resolved; then
    echo -e "\033[34mUsing systemd-resolved to set DNS servers...\033[0m"
    if resolvectl --help 2>&1 | grep -q "set-dns"; then
        if sudo resolvectl set-dns global "$DNS1${DNS2:+ $DNS2}"; then
            sudo resolvectl reset 2>/dev/null || true
            sudo systemctl restart systemd-resolved
            restart_network
            if test_dns; then
                echo "systemd-resolved configuration successful."
                if compare_and_verify; then
                    echo -e "\033[32msuccessful\033[0m"
                else
                    echo -e "\033[31mfailed\033[0m"
                fi
                # Post-configuration verification
                echo -e "\n\033[34m=== Post-Configuration Verification ===\033[0m"
                echo -e "\033[34mNetwork Interfaces:\033[0m"
                ip link show
                echo -e "\033[34mNetworkManager Connections:\033[0m"
                nmcli con show
                echo -e "\033[34mPinging $DNS1\033[0m"
                ping -c 1 "$DNS1"
                if [ -n "$DNS2" ]; then
                    echo -e "\033[34mPinging $DNS2\033[0m"
                    ping -c 1 "$DNS2"
                fi
                echo -e "\033[34mContents of /etc/resolv.conf (without comments):\033[0m"
                grep -v '^#' /etc/resolv.conf
                echo -e "\033[34mContents of Netplan configuration file:\033[0m"
                sudo cat /etc/netplan/01-network-manager-all.yaml
                echo -e "\033[34mApplying Netplan configuration:\033[0m"
                sudo netplan apply && echo -e "\033[32msuccessful\033[0m" || echo -e "\033[31mfailed\033[0m"
                exit 0
            fi
        fi
    fi
fi

# Fallback to Netplan
echo -e "\033[34mChecking for netplan...\033[0m"
if [ -d /etc/netplan ]; then
    echo -e "\033[34mUsing netplan to set DNS servers...\033[0m"
    NETPLAN_FILE=$(ls /etc/netplan/01-network-manager-all.yaml 2>/dev/null | head -n1)
    if [ -n "$NETPLAN_FILE" ]; then
        sudo cp "$NETPLAN_FILE" "$NETPLAN_FILE.bak"
        sudo sed -i '/nameservers:/,/^[a-z]/d' "$NETPLAN_FILE"
        sudo sed -i '/ethernets:/,/^[a-z]/ s/^\([[:space:]]*\)\(dhcp4:.*\)/\1\2\n\1nameservers:\n\1  addresses: ['"$DNS1${DNS2:+, $DNS2}"']/' "$NETPLAN_FILE"
        sudo chmod 600 "$NETPLAN_FILE"
        restart_network
        if test_dns; then
            echo "netplan configuration successful."
            if compare_and_verify; then
                echo -e "\033[32msuccessful\033[0m"
            else
                echo -e "\033[31mfailed\033[0m"
            fi
            echo -e "\n\033[34m=== Post-Configuration Verification ===\033[0m"
            echo -e "\033[34mNetwork Interfaces:\033[0m"
            ip link show
            echo -e "\033[34mPinging $DNS1\033[0m"
            ping -c 1 "$DNS1"
            if [ -n "$DNS2" ]; then
                echo -e "\033[34mPinging $DNS2\033[0m"
                ping -c 1 "$DNS2"
            fi
            echo -e "\033[34mContents of Netplan configuration file:\033[0m"
            sudo cat "$NETPLAN_FILE"
            echo -e "\033[34mApplying Netplan configuration:\033[0m"
            sudo netplan apply && echo -e "\033[32msuccessful\033[0m" || echo -e "\033[31mfailed\033[0m"
            exit 0
        fi
    fi
fi

echo "Failed to configure DNS with all available methods."
exit 1
