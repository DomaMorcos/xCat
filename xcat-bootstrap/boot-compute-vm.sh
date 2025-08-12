#!/bin/bash
# filepath: /home/doma/Desktop/DevOps/xcat-lab/automated/boot-compute-vm.sh
set -e

COMPUTE_VM_NAME="computenode"
COMPUTE_MAC="08:00:27:AB:CD:EF"

echo "========================================="
echo "Starting Diskless Compute VM"
echo "========================================="

# Check if VM exists
if ! VBoxManage list vms | grep -q "$COMPUTE_VM_NAME"; then
    echo "❌ Compute VM '$COMPUTE_VM_NAME' not found!"
    echo "Please run ./create-compute-vm.sh first"
    exit 1
fi

# Check if management node is running
echo "Checking if management node is ready..."
if ! vagrant status | grep -q "running"; then
    echo "❌ Management node is not running!"
    echo "Please run 'vagrant up' first"
    exit 1
fi

# Verify management node is ready
echo "Verifying xCAT management node..."
if ! vagrant ssh -c "test -f /tmp/setup_complete" 2>/dev/null; then
    echo "❌ xCAT setup not complete on management node!"
    echo "Please wait for 'vagrant up' to finish completely"
    exit 1
fi

# Check xCAT services are running (run as root)
echo "Checking xCAT services..."
vagrant ssh -c "
sudo -i << 'EOF'
source /etc/profile.d/xcat.sh
export PATH=/opt/xcat/bin:/opt/xcat/sbin:/opt/xcat/share/xcat/tools:\$PATH

echo 'Checking xCAT services:'
echo 'xcatd:' \$(systemctl is-active xcatd)
echo 'apache2:' \$(systemctl is-active apache2)
echo 'isc-dhcp-server:' \$(systemctl is-active isc-dhcp-server)
echo 'bind9:' \$(systemctl is-active bind9)
echo ''

echo 'Checking compute node in xCAT:'
/opt/xcat/bin/lsdef computenode | head -10
echo ''

echo 'Checking DHCP configuration:'
if grep -q '08:00:27:AB:CD:EF' /etc/dhcp/dhcpd.conf; then
    echo '✅ MAC address found in DHCP config'
    grep -A3 -B3 '08:00:27:AB:CD:EF' /etc/dhcp/dhcpd.conf
else
    echo '❌ MAC address not found in DHCP config!'
    echo 'Regenerating DHCP configuration...'
    
    # Regenerate DHCP configuration
    /opt/xcat/bin/makedhcp -n 2>/dev/null || true
    /opt/xcat/bin/makedhcp computenode 2>/dev/null || true
    
    if grep -q '08:00:27:AB:CD:EF' /etc/dhcp/dhcpd.conf; then
        echo '✅ MAC address now found in DHCP config after regeneration'
    else
        echo '❌ Still no MAC address in DHCP config - this will prevent PXE boot'
    fi
fi
echo ''

echo 'Checking network boot files:'
ls -la /tftpboot/xcat/xnba.kpxe 2>/dev/null || echo 'xnba.kpxe not found!'
ls -la /install/netboot/centos7.8/x86_64/compute/ 2>/dev/null | head -5 || echo 'Compute image not found!'
echo ''

echo 'Testing DHCP server:'
systemctl restart isc-dhcp-server
systemctl is-active isc-dhcp-server && echo '✅ DHCP server restarted successfully' || echo '❌ DHCP server failed to restart'
EOF
"

echo "✅ Management node is ready"

# Stop VM if it's running to ensure clean state
echo "Ensuring VM is stopped for clean boot..."
VBoxManage controlvm "$COMPUTE_VM_NAME" poweroff 2>/dev/null || true
sleep 3

# Completely reset VM network configuration
echo "Resetting VM network configuration..."
VBoxManage modifyvm "$COMPUTE_VM_NAME" --nic1 none
sleep 1
VBoxManage modifyvm "$COMPUTE_VM_NAME" --nic2 none
sleep 1

# Ensure proper configuration for diskless boot
echo "Configuring VM for diskless PXE boot..."
VBoxManage modifyvm "$COMPUTE_VM_NAME" --boot1 net --boot2 none --boot3 none --boot4 none
VBoxManage modifyvm "$COMPUTE_VM_NAME" --nic1 hostonly --hostonlyadapter1 vboxnet0
VBoxManage modifyvm "$COMPUTE_VM_NAME" --macaddress1 $(echo $COMPUTE_MAC | tr -d ':')
VBoxManage modifyvm "$COMPUTE_VM_NAME" --nicbootprio1 1
VBoxManage modifyvm "$COMPUTE_VM_NAME" --nictype1 82540EM  # Use Intel adapter for better PXE support
VBoxManage modifyvm "$COMPUTE_VM_NAME" --cableconnected1 on

# Verify vboxnet0 configuration
echo "Verifying host-only network configuration..."
VBoxManage list hostonlyifs | grep -A5 vboxnet0 || echo "⚠️ vboxnet0 not properly configured"

# Clear any VM snapshots or saved states that might interfere
echo "Clearing any saved states..."
VBoxManage discardstate "$COMPUTE_VM_NAME" 2>/dev/null || true

# Start the compute VM with GUI
echo "Starting compute VM with GUI..."
VBoxManage startvm "$COMPUTE_VM_NAME" --type gui

echo "========================================="
echo "🚀 Compute VM Started!"
echo "========================================="
echo ""
echo "Expected boot sequence:"
echo "1. VM gets MAC: $COMPUTE_MAC"
echo "2. DHCP assigns IP: 192.168.56.6 (static from xCAT)"
echo "3. Download xnba.kpxe via TFTP from 192.168.56.10"
echo "4. Download kernel and initrd via HTTP"
echo "5. Boot CentOS diskless from RAM"
echo "6. Show 'computenode login' prompt"
echo ""
echo "🔍 Debug commands if boot fails:"
echo "   vagrant ssh"
echo "   sudo tail -f /var/log/dhcp/dhcpd.log"
echo "   sudo tail -f /var/log/apache2/access.log"
echo "   sudo tcpdump -i enp0s8 -n"
echo ""
echo "⚠️  If you see 'localhost login' instead of 'computenode login':"
echo "   1. Check that DHCP assigns correct IP (should be 192.168.56.6)"
echo "   2. Check that TFTP serves xnba.kpxe correctly"
echo "   3. Check that HTTP serves kernel/initrd files"
echo "   4. VM might be falling back to internal boot system"
echo ""
echo "Watch the VirtualBox GUI for PXE boot messages!"
echo "========================================="