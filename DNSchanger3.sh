
#!/bin/bash

# Check if arguments are provided
if [ $# -lt 1 ]; then
    echo -e "\033[31mYou're doing it wrong...\033[0m"
    echo -e "\033[31mExample: $0 1.1.1.1 1.0.0.1\033[0m"
    exit 1
fi

# Enable debug tracing only if arguments are provided
set -x

DNS1="$1"
DNS2="$2"

if ! echo "$DNS1" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^([0-9a-fA-F:]+:[0-9a-fA-F:]+)$' >/dev/null; then
    echo "Error: $DNS1 is not a valid IPv4 or IPv6 address."
    exit 1
fi

if [ -n "$DNS2" ] && ! echo "$DNS2" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^([0-9a-fA-F:]+:[0-9a-fA-F:]+)$' >/dev/null; then
    echo "Error: $DNS2 is not a valid IPv4 or IPv6 address."
    exit 1
fi

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
    elif command -v nslookup >/dev/null 2>&1; then
        local TEST_DNS=$(nslookup google.com ${DNS1} 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | head -n1)
        if echo "$TEST_DNS" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null; then
            echo "DNS resolution test successful with $DNS1."
            return 0
        elif [ -n "$DNS2" ]; then
            TEST_DNS=$(nslookup google.com ${DNS2} 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | head -n1)
            if echo "$TEST_DNS" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null; then
                echo "DNS resolution test successful with $DNS2."
                return 0
            fi
        fi
    else
        if ping -c 1 google.com >/dev/null 2>&1; then
            echo "DNS resolution test passed (using ping, cannot verify specific DNS server)."
            return 0
        fi
    fi
    echo "DNS resolution test failed with the provided DNS servers."
    return 1
}

restart_network() {
    if systemctl is-active --quiet NetworkManager; then
        sudo systemctl restart NetworkManager
    elif systemctl is-active --quiet networking; then
        sudo systemctl restart networking
    elif command -v service >/dev/null 2>&1; then
        sudo service networking restart 2>/dev/null || true
    fi
    sleep 2
}

echo "Checking for systemd-resolved..."
if systemctl is-active --quiet systemd-resolved; then
    echo "Using systemd-resolved to set DNS servers..."
    if resolvectl --help 2>&1 | grep -q "set-dns"; then
        echo "resolvectl supports set-dns, proceeding..."
        if ! sudo resolvectl set-dns global "$DNS1${DNS2:+ $DNS2}"; then
            echo "Failed to set DNS with resolvectl set-dns. Falling back..."
        else
            sudo resolvectl reset 2>/dev/null || true
            sudo systemctl restart systemd-resolved
            restart_network
            if test_dns; then
                echo "systemd-resolved configuration successful."
                echo -e "\n\n\033[34m=== Post-Configuration Verification ===\033[0m"
                echo -e "\033[34mNetwork Interfaces:\033[0m"
                ip link show
                echo -e "\033[34mNetworkManager Connections:\033[0m"
                nmcli con show
                echo -e "\033[34mPinging $DNS1:\033[0m"
                ping -c 1 $DNS1
                if [ -n "$DNS2" ]; then
                    echo -e "\033[34mPinging $DNS2:\033[0m"
                    ping -c 1 $DNS2
                fi
                echo -e "\033[34mContents of /etc/resolv.conf (without comments):\033[0m"
                grep -v '^#' /etc/resolv.conf
                echo -e "\033[34mContents of Netplan configuration file:\033[0m"
                sudo sed 's/\(addresses: \[[^]]*\]\)/\o033[1;32m\1\o033[0m/' /etc/netplan/01-network-manager-all.yaml | cat
                echo -e "\033[34mApplying Netplan configuration:\033[0m"
                sudo netplan apply
                exit 0
            else
                echo "Failed to set DNS with systemd-resolved (test failed). Falling back..."
            fi
        fi
    else
        echo "systemd-resolved is active but resolvectl set-dns is not supported (older version). Falling back..."
    fi
else
    echo "systemd-resolved is not active. Falling back..."
fi

echo "Checking for NetworkManager..."
if systemctl is-active --quiet NetworkManager; then
    echo "Using NetworkManager to set DNS servers..."
    CONN_NAME=$(nmcli -t -f NAME con show --active | head -n1)
    if [ -n "$CONN_NAME" ]; then
        echo "Active NetworkManager connection found: $CONN_NAME"
        if nmcli con mod "$CONN_NAME" ipv4.dns "$DNS1${DNS2:+,$DNS2}" && \
           nmcli con mod "$CONN_NAME" ipv4.dns-priority 1 && \
           nmcli con mod "$CONN_NAME" ipv4.ignore-auto-dns yes && \
           nmcli con up "$CONN_NAME"; then
            restart_network
            if test_dns; then
                echo "NetworkManager configuration successful."
                echo -e "\n\n\033[34m=== Post-Configuration Verification ===\033[0m"
                echo -e "\033[34mNetwork Interfaces:\033[0m"
                ip link show
                echo -e "\033[34mNetworkManager Connections:\033[0m"
                nmcli con show
                echo -e "\033[34mPinging $DNS1:\033[0m"
                ping -c 1 $DNS1
                if [ -n "$DNS2" ]; then
                    echo -e "\033[34mPinging $DNS2:\033[0m"
                    ping -c 1 $DNS2
                fi
                echo -e "\033[34mContents of /etc/resolv.conf (without comments):\033[0m"
                grep -v '^#' /etc/resolv.conf
                echo -e "\033[34mContents of Netplan configuration file:\033[0m"
                sudo sed 's/\(addresses: \[[^]]*\]\)/\o033[1;32m\1\o033[0m/' /etc/netplan/01-network-manager-all.yaml | cat
                echo -e "\033[34mApplying Netplan configuration:\033[0m"
                sudo netplan apply
                exit 0
            else
                echo "Failed to set DNS with NetworkManager (test failed). Falling back..."
            fi
        else
            echo "Failed to set DNS with NetworkManager (nmcli failed). Falling back..."
        fi
    else
        echo "No active NetworkManager connection found. Falling back..."
    fi
else
    echo "NetworkManager is not active. Falling back..."
fi

echo "Checking for netplan..."
if [ -d /etc/netplan ]; then
    echo "Using netplan to set DNS servers..."
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n1)
    if [ -z "$NETPLAN_FILE" ]; then
        echo "No netplan configuration file found. Creating /etc/netplan/01-netcfg.yaml..."
        NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
        sudo bash -c "cat > $NETPLAN_FILE" << EOL
network:
  version: 2
  renderer: networkd
  ethernets:
    all-en:
      match:
        name: "en*"
      dhcp4: yes
EOL
        sudo chmod 600 "$NETPLAN_FILE"
    fi

    if sudo grep -q "renderer: NetworkManager" "$NETPLAN_FILE"; then
        echo "Netplan is using NetworkManager renderer, skipping netplan modification as NetworkManager should handle DNS. Falling back..."
    else
        sudo cp "$NETPLAN_FILE" "$NETPLAN_FILE.bak"
        sudo sed -i '/nameservers:/,/^[a-z]/d' "$NETPLAN_FILE"
        sudo sed -i "/ethernets:/,/^[a-z]/ s/^\([[:space:]]*\)\(dhcp4:.*\)/\1\2\n\1nameservers:\n\1  addresses: [$DNS1${DNS2:+, $DNS2}]/" "$NETPLAN_FILE"
        sudo chmod 600 "$NETPLAN_FILE"
        if sudo netplan apply; then
            restart_network
            if test_dns; then
                echo "netplan configuration successful."
                echo -e "\n\n\033[34m=== Post-Configuration Verification ===\033[0m"
                echo -e "\033[34mNetwork Interfaces:\033[0m"
                ip link show
                echo -e "\033[34mNetworkManager Connections:\033[0m"
                nmcli con show
                echo -e "\033[34mPinging $DNS1:\033[0m"
                ping -c 1 $DNS1
                if [ -n "$DNS2" ]; then
                    echo -e "\033[34mPinging $DNS2:\033[0m"
                    ping -c 1 $DNS2
                fi
                echo -e "\033[34mContents of /etc/resolv.conf (without comments):\033[0m"
                grep -v '^#' /etc/resolv.conf
                echo -e "\033[34mContents of Netplan configuration file:\033[0m"
                sudo sed 's/\(addresses: \[[^]]*\]\)/\o033[1;32m\1\o033[0m/' /etc/netplan/01-network-manager-all.yaml | cat
                echo -e "\033[34mApplying Netplan configuration:\033[0m"
                sudo netplan apply
                exit 0
            else
                echo "Failed to set DNS with netplan (test failed). Falling back..."
            fi
        else
            echo "Failed to set DNS with netplan (netplan apply failed). Falling back..."
        fi
    fi
else
    echo "netplan is not present. Falling back..."
fi

echo "Checking for resolvconf..."
if ! command -v resolvconf >/dev/null 2>&1; then
    echo "resolvconf is not installed. Attempting to install for persistent DNS configuration..."
    if sudo apt update && sudo apt install -y resolvconf; then
        echo "resolvconf installed successfully."
    else
        echo "Failed to install resolvconf. Falling back..."
    fi
fi

if command -v resolvconf >/dev/null 2>&1; then
    echo "Using resolvconf to set DNS servers..."
    sudo mkdir -p /etc/resolvconf/resolv.conf.d
    echo "nameserver $DNS1" | sudo tee /etc/resolvconf/resolv.conf.d/base >/dev/null
    if [ -n "$DNS2" ]; then
        echo "nameserver $DNS2" | sudo tee -a /etc/resolvconf/resolv.conf.d/base >/dev/null
    fi
    restart_network
    if test_dns; then
        echo "resolvconf configuration successful."
        echo -e "\n\n\033[34m=== Post-Configuration Verification ===\033[0m"
        echo -e "\033[34mNetwork Interfaces:\033[0m"
        ip link show
        echo -e "\033[34mNetworkManager Connections:\033[0m"
        nmcli con show
        echo -e "\033[34mPinging $DNS1:\033[0m"
        ping -c 1 $DNS1
        if [ -n "$DNS2" ]; then
            echo -e "\033[34mPinging $DNS2:\033[0m"
            ping -c 1 $DNS2
        fi
        echo -e "\033[34mContents of /etc/resolv.conf (without comments):\033[0m"
        grep -v '^#' /etc/resolv.conf
        echo -e "\033[34mContents of Netplan configuration file:\033[0m"
        sudo sed 's/\(addresses: \[[^]]*\]\)/\o033[1;32m\1\o033[0m/' /etc/netplan/01-network-manager-all.yaml | cat
        echo -e "\033[34mApplying Netplan configuration:\033[0m"
        sudo netplan apply
        exit 0
    else
        echo "Failed to set DNS with resolvconf (test failed). Falling back..."
    fi
else
    echo "resolvconf is not installed and could not be installed. Falling back..."
fi

echo "Checking for /etc/network/interfaces..."
if [ -f /etc/network/interfaces ]; then
    echo "Using /etc/network/interfaces to set DNS servers..."
    sudo cp /etc/network/interfaces /etc/network/interfaces.bak
    if grep -q "dns-nameservers" /etc/network/interfaces; then
        sudo sed -i "s/^\s*dns-nameservers.*/    dns-nameservers $DNS1${DNS2:+ $DNS2}/" /etc/network/interfaces
    else
        INTERFACE=$(grep -E "^iface" /etc/network/interfaces | head -n1 | awk '{print $2}')
        if [ -n "$INTERFACE" ]; then
            sudo sed -i "/^iface $INTERFACE inet/ a\    dns-nameservers $DNS1${DNS2:+ $DNS2}" /etc/network/interfaces
        else
            echo "No network interface found in /etc/network/interfaces. Falling back..."
        fi
    fi
    if sudo systemctl restart networking 2>/dev/null || sudo service networking restart 2>/dev/null; then
        restart_network
        if test_dns; then
            echo "/etc/network/interfaces configuration successful."
            echo -e "\n\n\033[34m=== Post-Configuration Verification ===\033[0m"
            echo -e "\033[34mNetwork Interfaces:\033[0m"
            ip link show
            echo -e "\033[34mNetworkManager Connections:\033[0m"
            nmcli con show
            echo -e "\033[34mPinging $DNS1:\033[0m"
            ping -c 1 $DNS1
            if [ -n "$DNS2" ]; then
                echo -e "\033[34mPinging $DNS2:\033[0m"
                ping -c 1 $DNS2
            fi
            echo -e "\033[34mContents of /etc/resolv.conf (without comments):\033[0m"
            grep -v '^#' /etc/resolv.conf
            echo -e "\033[34mContents of Netplan configuration file:\033[0m"
            sudo sed 's/\(addresses: \[[^]]*\]\)/\o033[1;32m\1\o033[0m/' /etc/netplan/01-network-manager-all.yaml | cat
            echo -e "\033[34mApplying Netplan configuration:\033[0m"
            sudo netplan apply
            exit 0
        else
            echo "Failed to set DNS with /etc/network/interfaces (test failed). Falling back..."
        fi
    else
        echo "Failed to restart networking service. Falling back..."
    fi
else
    echo "/etc/network/interfaces not found. Falling back..."
fi

echo "Falling back to direct modification of /etc/resolv.conf (may not persist)..."
sudo cp /etc/resolv.conf /etc/resolv.conf.bak
echo "nameserver $DNS1" | sudo tee /etc/resolv.conf >/dev/null
if [ -n "$DNS2" ]; then
    echo "nameserver $DNS2" | sudo tee -a /etc/resolv.conf >/dev/null
fi
echo "Warning: These changes may not persist after reboot."
restart_network
if test_dns; then
    echo "Direct /etc/resolv.conf modification successful."
    echo -e "\n\n\033[34m=== Post-Configuration Verification ===\033[0m"
    echo -e "\033[34mNetwork Interfaces:\033[0m"
    ip link show
    echo -e "\033[34mNetworkManager Connections:\033[0m"
    nmcli con show
    echo -e "\033[34mPinging $DNS1:\033[0m"
    ping -c 1 $DNS1
    if [ -n "$DNS2" ]; then
        echo -e "\033[34mPinging $DNS2:\033[0m"
        ping -c 1 $DNS2
    fi
    echo -e "\033[34mContents of /etc/resolv.conf (without comments):\033[0m"
    grep -v '^#' /etc/resolv.conf
    echo -e "\033[34mContents of Netplan configuration file:\033[0m"
    sudo sed 's/\(addresses: \[[^]]*\]\)/\o033[1;32m\1\o033[0m/' /etc/netplan/01-network-manager-all.yaml | cat
    echo -e "\033[34mApplying Netplan configuration:\033[0m"
    sudo netplan apply
    exit 0
else
    echo "DNS resolution still failed with the provided DNS servers. Please check your network configuration."
    exit 1
fi
md@nn04:~$ 
