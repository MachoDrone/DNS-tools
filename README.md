# DNS-tools
Easily benchmark DNS Server for your location and easily change it in Ubuntu.

This script installs dependencies and runs the DNS benchmark with namebench. The FIRST time you run it, it may be slow.
Remember, finding the Fastest DNS Server may not mean it's the most reliable or complete DNS Server.
- ```wget -qO- https://raw.githubusercontent.com/MachoDrone/DNS-tools/refs/heads/main/DNSbenchmark.sh | sudo bash```

This script easily edits your DNS Server in Ubuntu and verifies the success of the change with a test.
The script considers two methods to edit the DNS server: it either uses NetworkManager to modify the active connection’s DNS settings if available, or it directly updates the /etc/resolv.conf file with the specified DNS servers if NetworkManager isn’t in use.
- ```wget -O - https://raw.githubusercontent.com/MachoDrone/DNS-tools/refs/heads/main/DNSchanger3.sh | bash -s -- <PRIMARY_DNS> <SECONDARY_DNS>```
- e.g. ```wget -O - https://raw.githubusercontent.com/MachoDrone/DNS-tools/refs/heads/main/DNSchanger3.sh | bash -s -- 1.1.1.1 1.0.0.1```
