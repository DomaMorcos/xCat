set -e

COMPUTE_VM_NAME="computenode"
COMPUTE_MAC="08:00:27:AB:CD:EF"  # Static MAC address - MUST match bootstrap.sh

echo "========================================="
echo "Creating Diskless Compute VM"
echo "========================================="

# Check if VirtualBox is installed
if ! command -v VBoxManage &> /dev/null; then
    echo "❌ VirtualBox is not installed on this host"
    echo "Please install VirtualBox first"
    exit 1
fi

# Ensure host-only network exists
echo "Setting up VirtualBox host-only network..."
if ! VBoxManage list hostonlyifs | grep -q vboxnet0; then
    echo "Creating vboxnet0..."
    VBoxManage hostonlyif create
    VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
else
    echo "✅ vboxnet0 already exists"
fi

# Clean up any existing compute VM
echo "Cleaning up any existing compute VM..."
VBoxManage controlvm "$COMPUTE_VM_NAME" poweroff 2>/dev/null || true
sleep 3
VBoxManage unregistervm "$COMPUTE_VM_NAME" --delete 2>/dev/null || true

# Create new VM
echo "Creating new diskless compute VM..."
VBoxManage createvm --name "$COMPUTE_VM_NAME" --register

# Configure VM settings for diskless boot
echo "Configuring VM settings..."
VBoxManage modifyvm "$COMPUTE_VM_NAME" --memory 2048
VBoxManage modifyvm "$COMPUTE_VM_NAME" --cpus 2
VBoxManage modifyvm "$COMPUTE_VM_NAME" --ostype "Linux_64"
VBoxManage modifyvm "$COMPUTE_VM_NAME" --firmware bios
VBoxManage modifyvm "$COMPUTE_VM_NAME" --rtcuseutc on

# Critical: Set the EXACT MAC address that xCAT expects
echo "Setting static MAC address for xCAT..."
VBoxManage modifyvm "$COMPUTE_VM_NAME" --macaddress1 $(echo $COMPUTE_MAC | tr -d ':')

# Configure network adapters - ONLY use host-only for clean PXE boot
echo "Configuring network adapters..."
# Adapter 1: Host-only ONLY (for xCAT management and PXE boot)
VBoxManage modifyvm "$COMPUTE_VM_NAME" --nic1 hostonly
VBoxManage modifyvm "$COMPUTE_VM_NAME" --hostonlyadapter1 vboxnet0

# Disable adapter 2 for clean boot (can be enabled later if needed)
VBoxManage modifyvm "$COMPUTE_VM_NAME" --nic2 none

# Critical: Set boot order for diskless PXE boot
echo "Setting boot order for diskless PXE boot..."
VBoxManage modifyvm "$COMPUTE_VM_NAME" --boot1 net
VBoxManage modifyvm "$COMPUTE_VM_NAME" --boot2 none
VBoxManage modifyvm "$COMPUTE_VM_NAME" --boot3 none
VBoxManage modifyvm "$COMPUTE_VM_NAME" --boot4 none

# Enable PXE boot priority
VBoxManage modifyvm "$COMPUTE_VM_NAME" --nicbootprio1 1

# Disable audio and other unnecessary devices for cleaner boot
VBoxManage modifyvm "$COMPUTE_VM_NAME" --audio none
VBoxManage modifyvm "$COMPUTE_VM_NAME" --usb off

echo "========================================="
echo "✅ Diskless Compute VM Created!"
echo "========================================="
echo "VM Name: $COMPUTE_VM_NAME"
echo "MAC Address: $COMPUTE_MAC"
echo "Expected IP: 192.168.56.6 (assigned by xCAT DHCP)"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Start management node: vagrant up"
echo "2. Wait for xCAT setup to complete"
echo "3. Boot compute VM: ./boot-compute-vm.sh"
echo ""
echo "⚠️  IMPORTANT: MAC address MUST match bootstrap.sh!"
echo "Current MAC: $COMPUTE_MAC"
echo "========================================="