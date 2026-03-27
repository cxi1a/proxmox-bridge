# 🚀 Proxmox Private Bridge Network 🚀

A secure NAT-based private network for Proxmox using iptables. ( vmbr0 -> vmbr1 )

This script quickly sets up bridges, iptables rules, and private IPs/subnets for private networking on your VMs and LXC containers.

---

✅ **Features:**

* Auto-detects main ethernet interface and IP
* Automatically sets up a bridge (vmbr1) for private networking.
* Assigns subnet, CIDR, gateway, and IP range for VMs/LXC containers.
* Writes and applies iptables rules for NAT, forwarding, and subnet isolation.
* Configures the system to forward traffic between bridges.
* Reloads network interfaces after bridge setup.
* Outputs subnet, CIDR, mask, range, and gateway after setup.

---

🔗 **Usage:**

```bash <(curl -s https://raw.githubusercontent.com/cxi1a/proxmox-bridge/main/setup.sh)```

---

📝 **Author:**

Original script by **Kitty (exi3a)**
