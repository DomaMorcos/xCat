# xCAT Management Node Setup (Ubuntu/bionic64)

> **Note:** Installation using `go-xcat` doesn't work; you must manually modify the repo to bypass GPG key verification.

---

## Local Repository Setup

### xcat-core

**Download:**
```bash
mkdir -p ~/xcat
cd ~/xcat/
wget http://xcat.org/files/xcat/xcat-core/<version>.x_Ubuntu/xcat-core/xcat-core-<version>-ubuntu.tar.bz2
```

**Extract:**
```bash
tar jxvf xcat-core-<version>-ubuntu.tar.bz2
```

**Configure local repo:**
```bash
cd ~/xcat/xcat-core
./mklocalrepo.sh
```

### xcat-dep

**Download:**
```bash
mkdir -p ~/xcat/
cd ~/xcat
wget http://xcat.org/files/xcat/xcat-dep/2.x_Ubuntu/xcat-dep-<version>-ubuntu.tar.bz2
```

**Extract:**
```bash
tar jxvf xcat-dep-<version>-ubuntu.tar.bz2
```

**Configure local repo:**
```bash
cd ~/xcat/xcat-dep/
./mklocalrepo.sh
```

---

## Install xCAT

**Add xCAT GPG Public Key:**
```bash
wget -O - "http://xcat.org/files/xcat/repos/apt/apt.key" | apt-key add -
```

**Install add-apt-repository:**
```bash
apt-get install software-properties-common
```

**Modify apt repositories to bypass GPG verification:**

Create and edit the xcat-core repository file:
```bash
sudo nano /etc/apt/sources.list.d/xcat-core.list
```

Add the following content:
```
deb [arch=amd64 trusted=yes] file:///home/vagrant/xcat/xcat-core bionic/
```

Create and edit the xcat-dep repository file:
```bash
sudo nano /etc/apt/sources.list.d/xcat-dep.list
```

Add the following content:
```
deb [arch=amd64 trusted=yes] file:///home/vagrant/xcat/xcat-dep bionic/
```


**For x86_64:**
```bash
add-apt-repository "deb http://archive.ubuntudep/ubuntu $(lsb_release -sc) main"
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates main"
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe"
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates universe"
```


**Install xCAT:**
```bash
apt-get clean all
apt-get update
apt-get install xcat
```

---

## Verify xCAT Installation

**Source profile:**
```bash
source /etc/profile.d/xcat.sh
```

**Check xCAT version:**
```bash
lsxcatd -a
```

**Verify database initialization:**
```bash
tabdump site
```
Example output:
```
#key,value,comments,disable
"blademaxp","64",,
"domain","pok.stglabs.ibm.com",,
...
```

---

## Starting and Stopping xCAT

| Action   | SysV Init                | systemd                        |
|----------|--------------------------|--------------------------------|
| Start    | `service xcatd start`    | `systemctl start xcatd.service`|
| Stop     | `service xcatd stop`     | `systemctl stop xcatd.service` |
| Restart  | `service xcatd restart`  | `systemctl restart xcatd.service`|
| Status   | `service xcatd status`   | `systemctl status xcatd.service`|

---




# xCAT Diskless Provisioning Guide

## Overview
This guide shows how to provision a diskless compute node using:
- **Management Node**: Vagrant VM (Ubuntu 18.04) with xCAT
- **Compute Node**: VirtualBox VM (no ISO) that boots from network

## Prerequisites

### Vagrant Management Node
```ruby
Vagrant.configure("2") do |config|
  config.vm.define "xcat-mn" do |mn|
    mn.vm.box = "ubuntu/bionic64"
    mn.vm.hostname = "xcat-mn"
    mn.vm.network "private_network", ip: "192.168.56.10"

    mn.vm.provider :virtualbox do |vb|
      vb.memory = 4096
      vb.cpus = 2
    end
  end
end
```

### VirtualBox Compute Node VM
- Create new VM **without OS ISO**
- Network: Host-only Adapter (same network as management node) 
- Boot order: **Network first**

---

## Step-by-Step Configuration

### 1. Download CentOS ISO
```bash
# Create directory and download CentOS ISO
sudo mkdir /isos
cd /isos
sudo wget https://ftp.iij.ad.jp/pub/linux/centos-vault/7.8.2003/isos/x86_64/CentOS-7-x86_64-DVD-2003.iso

# Copy ISO to xCAT and create OS repository
copycds CentOS-7-x86_64-DVD-2003.iso
```

### 2. Initial Network Configuration
```bash
# Check available network interfaces
ip a

# Configure xCAT network settings (assuming enp0s8 is your private interface)
chdef -t site dhcpinterfaces="enp0s8"
chdef -t site domain="local"
chdef -t site nameservers="192.168.56.10"

# Configure IPv4-only environment
chdef -t site useipv6=0
chdef -t site dhcpsetup=1

# Remove IPv6 network entry if it exists
rmdef -t network fd17:625c:f037:2::/64

# Initialize network services
makedhcp -n
makenetworks
makedns
```

### 3. Configure Network Range
```bash
# Configure dynamic range for DHCP
chdef -t network 192_168_56_0-255_255_255_0 dynamicrange="192.168.56.100-192.168.56.200"
chdef -t network 192_168_56_0-255_255_255_0 nameservers=192.168.56.10

# Restart DHCP service
systemctl restart isc-dhcp-server
```

### 4. Define Compute Node
```bash
# Replace 08:00:27:08:AE:B3 with actual MAC from your VirtualBox VM
mkdef compute1 groups=compute,all ip=192.168.56.50 mac=08:00:27:08:AE:B3 \
  netboot=xnba arch=x86_64 installnic=enp0s8 primarynic=enp0s8

# Set provisioning method
chdef compute1 provmethod=centos7.8-x86_64-netboot-compute

# Update DNS and DHCP
makehosts compute1
makedhcp compute1
```

### 5. Prepare OS Image
```bash
# Install required packages for image generation
apt update
apt install -y yum rpm

# Generate and package the OS image
genimage centos7.8-x86_64-netboot-compute
packimage centos7.8-x86_64-netboot-compute
```

### 6. Configure Node Boot Settings
```bash
# Set the node to use the netboot image
nodeset compute1 osimage=centos7.8-x86_64-netboot-compute
```

### 7. Fix TFTP Configuration (Critical Step)
**The Main Issue**: TFTP was configured to serve from `/var/lib/tftpboot` but xCAT files are in `/tftpboot`

```bash
# Edit TFTP configuration
nano /etc/default/tftpd-hpa

# Change TFTP_DIRECTORY from "/var/lib/tftpboot" to "/tftpboot"
# File should look like:
# TFTP_USERNAME="tftp"
# TFTP_DIRECTORY="/tftpboot"
# TFTP_ADDRESS=":69"
# TFTP_OPTIONS="--secure"

# Restart TFTP service
systemctl restart tftpd-hpa
```

### 8. Create HTTP Symlinks for Boot Files
```bash
# Create directory structure for HTTP access
mkdir -p /var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/
mkdir -p /var/www/html/install/netboot/centos7.8/x86_64/compute/
mkdir -p /var/www/html/tftpboot/xcat/xnba/nodes/

# Create symlinks for boot files
ln -sf /install/netboot/centos7.8/x86_64/compute/kernel /var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/kernel
ln -sf /install/netboot/centos7.8/x86_64/compute/initrd-stateless.gz /var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/initrd-stateless.gz
ln -sf /install/netboot/centos7.8/x86_64/compute/rootimg.cpio.gz /var/www/html/install/netboot/centos7.8/x86_64/compute/rootimg.cpio.gz
ln -sf /tftpboot/xcat/xnba/nodes/compute1 /var/www/html/tftpboot/xcat/xnba/nodes/compute1

# Set proper permissions
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/
```

### 9. Update DHCP Configuration
```bash
# Clear old leases and regenerate DHCP
systemctl stop isc-dhcp-server
> /var/lib/dhcp/dhcpd.leases
makedhcp -n
makedhcp compute1
systemctl start isc-dhcp-server
```

### 10. Verify Configuration
```bash
# Test TFTP access
tftp 192.168.56.10
binary
get xcat/xnba.kpxe
quit

# Test HTTP access
curl -I http://192.168.56.10/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/kernel
curl -I http://192.168.56.10/install/netboot/centos7.8/x86_64/compute/rootimg.cpio.gz

# Check node configuration
cat /tftpboot/xcat/xnba/nodes/compute1
lsdef compute1
```

### 11. Boot the Compute Node
1. Start your VirtualBox compute node VM
2. It should PXE boot from network
3. Monitor the process:
   ```bash
   # In separate terminals:
   tail -f /var/log/syslog | grep dhcp
   tail -f /var/log/apache2/access.log
   ```

### 12. Optional: Set Node Password
```bash
# Set root password for compute node access
chtab key=system passwd.username=root passwd.password=abc123
```

---

## Boot Sequence Explained

1. **DHCP**: Compute node gets IP (192.168.56.50) and filename `xcat/xnba.kpxe`
2. **TFTP**: Downloads `xnba.kpxe` boot loader  
3. **HTTP Chain**: `xnba.kpxe` requests `http://192.168.56.10/tftpboot/xcat/xnba/nodes/compute1`
4. **Kernel Load**: Downloads kernel and initrd via HTTP
5. **Root Filesystem**: Downloads and mounts rootimg.cpio.gz in RAM
6. **Boot Complete**: CentOS kernel starts with diskless root filesystem

---

## Verification Commands

After successful boot, verify the setup:

```bash
# Check node status
lsdef compute1 -i status

# Connect to compute node
ssh compute1

# Test from management node
xdsh compute1 whoami
ping 192.168.56.50

# Check OS version on compute node
xdsh compute1 "cat /etc/os-release"
```

---

## Troubleshooting

### Common Issues:
- **TFTP not working**: Check `/etc/default/tftpd-hpa` directory setting
- **HTTP files not accessible**: Verify symlinks and Apache permissions  
- **Boot hangs**: Check kernel parameters and network interface names
- **DHCP issues**: Verify MAC address matches your VirtualBox VM
- **genimage fails**: Ensure `yum` and `rpm` packages are installed

### Key Files to Check:
- `/tftpboot/xcat/xnba/nodes/compute1` - Boot script
- `/etc/dhcp/dhcpd.conf` - DHCP configuration
- `/var/lib/dhcp/dhcpd.leases` - DHCP leases
- `/var/log/syslog` - DHCP and system logs
- `/var/log/apache2/access.log` - HTTP access logs

### Service Status Commands:
```bash
systemctl status isc-dhcp-server
systemctl status tftpd-hpa  
systemctl status apache2
```

---

## Success Indicators

✅ CentOS ISO successfully copied with `copycds`  
✅ OS image generated and packaged without errors  
✅ TFTP serves `xcat/xnba.kpxe` correctly  
✅ HTTP serves kernel, initrd, and rootimg files  
✅ Compute node gets IP via DHCP (192.168.56.50)  
✅ Compute node downloads and boots CentOS kernel  
✅ Node accessible via SSH from management node  
✅ Node shows `status=booted` in xCAT  

The compute node should boot completely diskless with CentOS 7 running from RAM and root filesystem served from the management node.
