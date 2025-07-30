# xCAT Complete Setup Guide

This guide covers the complete setup of xCAT for diskless provisioning, from installation to booting compute nodes.

---

## Table of Contents

1. [Management Node Setup](#management-node-setup)
2. [xCAT Installation](#xcat-installation)
3. [Diskless Provisioning Configuration](#diskless-provisioning-configuration)
4. [Verification and Testing](#verification-and-testing)
5. [Troubleshooting](#troubleshooting)

---

## Management Node Setup

### Prerequisites - Vagrant Configuration

Create a Vagrant VM for the xCAT management node:

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

### VirtualBox Compute Node VM Setup
- Create new VM **without OS ISO**
- Network: Host-only Adapter (same network as management node) 
- Boot order: **Network first**

---

## xCAT Installation

> **Note:** Installation using `go-xcat` doesn't work; you must manually modify the repo to bypass GPG key verification.

### 1. Local Repository Setup

#### xcat-core

**Download and extract:**
```bash
mkdir -p ~/xcat
cd ~/xcat/
wget http://xcat.org/files/xcat/xcat-core/2.16.x_Ubuntu/xcat-core/xcat-core-2.16.5-ubuntu.tar.bz2
tar jxvf xcat-core-2.16.5-ubuntu.tar.bz2
```

**Configure local repo:**
```bash
cd ~/xcat/xcat-core
./mklocalrepo.sh
```

#### xcat-dep

**Download and extract:**
```bash
cd ~/xcat
wget http://xcat.org/files/xcat/xcat-dep/2.x_Ubuntu/xcat-dep-2.16.5-ubuntu.tar.bz2
tar jxvf xcat-dep-2.16.5-ubuntu.tar.bz2
```

**Configure local repo:**
```bash
cd ~/xcat/xcat-dep/
./mklocalrepo.sh
```

### 2. Configure APT Repositories

**Install required packages:**
```bash
apt-get update
apt-get install software-properties-common
```

**Add standard Ubuntu repositories:**
```bash
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main"
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates main"
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe"
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates universe"
```

**Create xCAT repositories (bypassing GPG verification):**

Create xcat-core repository file:
```bash
sudo nano /etc/apt/sources.list.d/xcat-core.list
```
Add content:
```
deb [arch=amd64 trusted=yes] file:///home/vagrant/xcat/xcat-core bionic/
```

Create xcat-dep repository file:
```bash
sudo nano /etc/apt/sources.list.d/xcat-dep.list
```
Add content:
```
deb [arch=amd64 trusted=yes] file:///home/vagrant/xcat/xcat-dep bionic/
```

### 3. Install xCAT

```bash
apt-get clean all
apt-get update
apt-get install xcat
```

### 4. Verify Installation

**Source xCAT environment:**
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

### 5. xCAT Service Management

| Action   | SysV Init                | systemd                        |
|----------|--------------------------|--------------------------------|
| Start    | `service xcatd start`    | `systemctl start xcatd.service`|
| Stop     | `service xcatd stop`     | `systemctl stop xcatd.service` |
| Restart  | `service xcatd restart`  | `systemctl restart xcatd.service`|
| Status   | `service xcatd status`   | `systemctl status xcatd.service`|

---

## Diskless Provisioning Configuration

### 1. Download and Import OS

**Download CentOS ISO:**
```bash
sudo mkdir /isos
cd /isos
sudo wget https://ftp.iij.ad.jp/pub/linux/centos-vault/7.8.2003/isos/x86_64/CentOS-7-x86_64-DVD-2003.iso
```

**Import ISO to xCAT:**
```bash
copycds CentOS-7-x86_64-DVD-2003.iso
```

### 2. Network Configuration

**Check network interfaces:**
```bash
ip a
```

**Configure xCAT network settings:**
```bash
# Configure xCAT network settings (assuming enp0s8 is your private interface)
chdef -t site dhcpinterfaces="enp0s8"
chdef -t site domain="local"
chdef -t site nameservers="192.168.56.10"

# Configure IPv4-only environment
chdef -t site useipv6=0
chdef -t site dhcpsetup=1

# Remove IPv6 network entry if it exists
rmdef -t network fd17:625c:f037:2::/64
```

**Initialize network services:**
```bash
makedhcp -n
makenetworks
makedns
```

**Configure DHCP range:**
```bash
chdef -t network 192_168_56_0-255_255_255_0 dynamicrange="192.168.56.100-192.168.56.200"
chdef -t network 192_168_56_0-255_255_255_0 nameservers=192.168.56.10

# Restart DHCP service
systemctl restart isc-dhcp-server
```

### 3. Define Compute Node

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

### 4. Generate OS Image

**Install required packages:**
```bash
apt update
apt install -y yum rpm
```

**Generate and package the OS image:**
```bash
genimage centos7.8-x86_64-netboot-compute
packimage centos7.8-x86_64-netboot-compute
```

**Configure node boot settings:**
```bash
nodeset compute1 osimage=centos7.8-x86_64-netboot-compute
```

### 5. Fix TFTP Configuration (Critical)

**The Issue**: TFTP default configuration serves from `/var/lib/tftpboot` but xCAT files are in `/tftpboot`

**Edit TFTP configuration:**
```bash
nano /etc/default/tftpd-hpa
```

**Change TFTP_DIRECTORY:**
```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure"
```

**Restart TFTP service:**
```bash
systemctl restart tftpd-hpa
```

### 6. Create HTTP Symlinks for Boot Files

**Create directory structure:**
```bash
mkdir -p /var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/
mkdir -p /var/www/html/install/netboot/centos7.8/x86_64/compute/
mkdir -p /var/www/html/tftpboot/xcat/xnba/nodes/
```

**Create symlinks:**
```bash
ln -sf /install/netboot/centos7.8/x86_64/compute/kernel /var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/kernel
ln -sf /install/netboot/centos7.8/x86_64/compute/initrd-stateless.gz /var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/initrd-stateless.gz
ln -sf /install/netboot/centos7.8/x86_64/compute/rootimg.cpio.gz /var/www/html/install/netboot/centos7.8/x86_64/compute/rootimg.cpio.gz
ln -sf /tftpboot/xcat/xnba/nodes/compute1 /var/www/html/tftpboot/xcat/xnba/nodes/compute1
```

**Set permissions:**
```bash
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/
```

### 7. Final DHCP Configuration

**Clear and regenerate DHCP:**
```bash
systemctl stop isc-dhcp-server
> /var/lib/dhcp/dhcpd.leases
makedhcp -n
makedhcp compute1
systemctl start isc-dhcp-server
```

### 8. Optional: Set Node Password

```bash
chtab key=system passwd.username=root passwd.password=abc123
```

---

## Verification and Testing

### Pre-Boot Verification

**Test TFTP access:**
```bash
tftp 192.168.56.10
binary
get xcat/xnba.kpxe
quit
```

**Test HTTP access:**
```bash
curl -I http://192.168.56.10/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/kernel
curl -I http://192.168.56.10/install/netboot/centos7.8/x86_64/compute/rootimg.cpio.gz
```

**Check node configuration:**
```bash
cat /tftpboot/xcat/xnba/nodes/compute1
lsdef compute1
```

### Boot Process

1. **Start VirtualBox compute node VM**
2. **Monitor the boot process:**
   ```bash
   # In separate terminals:
   tail -f /var/log/syslog | grep dhcp
   tail -f /var/log/apache2/access.log
   ```

### Post-Boot Verification

**Check node status:**
```bash
lsdef compute1 -i status
```

**Test connectivity:**
```bash
ping 192.168.56.50
ssh compute1
```

**Test xCAT commands:**
```bash
xdsh compute1 whoami
xdsh compute1 "cat /etc/os-release"
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

## Troubleshooting

### Common Issues

- **TFTP not working**: Check `/etc/default/tftpd-hpa` directory setting
- **HTTP files not accessible**: Verify symlinks and Apache permissions  
- **Boot hangs**: Check kernel parameters and network interface names
- **DHCP issues**: Verify MAC address matches your VirtualBox VM
- **genimage fails**: Ensure `yum` and `rpm` packages are installed

### Key Files to Monitor

- `/tftpboot/xcat/xnba/nodes/compute1` - Boot script
- `/etc/dhcp/dhcpd.conf` - DHCP configuration
- `/var/lib/dhcp/dhcpd.leases` - DHCP leases
- `/var/log/syslog` - DHCP and system logs
- `/var/log/apache2/access.log` - HTTP access logs

### Service Status Commands

```bash
systemctl status xcatd
systemctl status isc-dhcp-server
systemctl status tftpd-hpa  
systemctl status apache2
```

---

## Success Indicators

✅ **xCAT Installation**: `lsxcatd -a` shows version info  
✅ **OS Import**: `copycds` completes without errors  
✅ **Image Generation**: `genimage` and `packimage` complete successfully  
✅ **TFTP Service**: Can download `xcat/xnba.kpxe`  
✅ **HTTP Service**: Boot files accessible via HTTP  
✅ **DHCP Service**: Compute node gets correct IP (192.168.56.50)  
✅ **Network Boot**: Compute node downloads and boots CentOS kernel  
✅ **SSH Access**: Can connect to compute node  
✅ **xCAT Management**: Node shows `status=booted`  

The compute node should boot completely diskless with CentOS 7 running from RAM and root filesystem served from the management node.
