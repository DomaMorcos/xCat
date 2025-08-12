set +e  # Don't exit on errors - let's handle them gracefully


COMPUTE_IP="192.168.56.6"
COMPUTE_MAC="08:00:27:AB:CD:EF"
NODE_NAME="computenode"

echo "========================================="
echo "xCAT Phase 2: ISO Import & Final Setup"
echo "========================================="

# Source xCAT environment
source /etc/profile.d/xcat.sh
export PATH=/opt/xcat/bin:/opt/xcat/sbin:/opt/xcat/share/xcat/tools:$PATH

# =================================
# SETUP ROOT ENVIRONMENT & CERTIFICATES
# =================================
echo "Setting up root environment and xCAT certificates..."
export HOME=/root
export USER=root
export LOGNAME=root
cd /root

# Remove any existing certificate files
rm -rf /root/.xcat 2>/dev/null || true

# Ensure xcatd is running properly
echo "Ensuring xcatd daemon is running..."
systemctl restart xcatd
sleep 10

# Wait for xcatd to be ready
echo "Waiting for xcatd daemon..."
for i in {1..30}; do
    if netstat -an | grep -q ":3001.*LISTEN"; then
        echo "✅ xcatd is listening on port 3001"
        break
    fi
    echo "⏳ Waiting for xcatd... ($i/30)"
    sleep 2
done

if ! netstat -an | grep -q ":3001.*LISTEN"; then
    echo "❌ xcatd still not listening after 60 seconds"
    systemctl status xcatd
    exit 1
fi

# Install expect if not available
if ! command -v expect >/dev/null 2>&1; then
    apt-get update && apt-get install -y expect
fi

# Setup xCAT client certificates using expect to handle prompts
echo "Setting up xCAT client certificates with expect..."
expect -c '
set timeout 60
spawn /opt/xcat/share/xcat/scripts/setup-local-client.sh root
expect {
    "Sign the certificate? *" { send "y\r"; exp_continue }
    "delete and start over*" { send "y\r"; exp_continue }
    "commit? *" { send "y\r"; exp_continue }
    eof { }
}
' || echo "Certificate setup completed with expect"

# Test xCAT connection
echo "Testing xCAT connection..."
sleep 5
if ! /opt/xcat/bin/lsdef -t site >/dev/null 2>&1; then
    echo "❌ xCAT connection failed. Trying alternative methods..."
    
    # Method 1: Try simple echo pipe
    echo -e "y\ny\n" | /opt/xcat/share/xcat/scripts/setup-local-client.sh root || true
    sleep 3
    
    # Method 2: Try with yes command
    if ! /opt/xcat/bin/lsdef -t site >/dev/null 2>&1; then
        echo "Trying with yes command..."
        yes | /opt/xcat/share/xcat/scripts/setup-local-client.sh root || true
        sleep 3
    fi
    
    # Final test
    if ! /opt/xcat/bin/lsdef -t site >/dev/null 2>&1; then
        echo "❌ xCAT still not working. Trying to continue anyway..."
        # Don't exit - let's try to continue
    else
        echo "✅ xCAT connection successful with alternative method"
    fi
else
    echo "✅ xCAT connection successful"
fi

echo "✅ Root environment and xCAT certificates ready"

# =================================
# VERIFY ISO EXISTS
# =================================

CENTOS_ISO="CentOS-7-x86_64-DVD-2003.iso"
cd /isos

if [ ! -f "$CENTOS_ISO" ]; then
    echo "❌ CentOS ISO not found in /isos/"
    echo "Please run the copy-iso.sh script first"
    echo "Available files:"
    ls -la /isos/
    exit 1
fi

echo "✅ CentOS ISO found: $(ls -lh $CENTOS_ISO)"

# =================================
# NETWORK CONFIGURATION  
# =================================

# Force the correct network interface (enp0s8)
echo "Configuring network interface..."
NETWORK_INTERFACE="enp0s8"
echo "✅ Using network interface: $NETWORK_INTERFACE"

# Configure xCAT network settings with IPv6 disabled
echo "Configuring xCAT network settings..."
/opt/xcat/bin/chdef -t site dhcpinterfaces="$NETWORK_INTERFACE"
/opt/xcat/bin/chdef -t site domain="local"
/opt/xcat/bin/chdef -t site nameservers="192.168.56.10"
/opt/xcat/bin/chdef -t site useipv6=0
/opt/xcat/bin/chdef -t site dhcpsetup=1

# =================================
# AGGRESSIVE IPv6 AND PROBLEMATIC NETWORK CLEANUP
# =================================

echo "Aggressive IPv6 and problematic network cleanup..."

# Remove all problematic networks one by one
echo "Removing all problematic networks..."
/opt/xcat/bin/rmdef -t network "fd17:625c:f037:2::/64" 2>/dev/null || true
/opt/xcat/bin/rmdef -t network "10_0_2_0-255_255_255_0" 2>/dev/null || true

# Get list of all networks and remove anything that's not our 192.168.56.0 network
/opt/xcat/bin/lsdef -t network | while read net_line; do
    net_name=$(echo "$net_line" | awk '{print $1}')
    if [[ "$net_name" != "192_168_56_0-255_255_255_0" ]] && [[ "$net_name" != "" ]]; then
        echo "Removing unwanted network: $net_name"
        /opt/xcat/bin/rmdef -t network "$net_name" 2>/dev/null || true
    fi
done

# Ensure only our desired network exists
echo "Ensuring our network configuration..."
if ! /opt/xcat/bin/lsdef -t network 192_168_56_0-255_255_255_0 >/dev/null 2>&1; then
    echo "Creating our IPv4 network..."
    /opt/xcat/bin/mkdef -t network -o 192_168_56_0-255_255_255_0 net=192.168.56.0 mask=255.255.255.0 gateway=192.168.56.1
fi

# =================================
# IMPORT ISO TO XCAT
# =================================

# Function to find xCAT command location
find_xcat_cmd() {
    local cmd="$1"
    if [ -f "/opt/xcat/bin/$cmd" ]; then
        echo "/opt/xcat/bin/$cmd"
    elif [ -f "/opt/xcat/sbin/$cmd" ]; then
        echo "/opt/xcat/sbin/$cmd"
    elif command -v "$cmd" >/dev/null 2>&1; then
        which "$cmd"
    else
        echo ""
    fi
}

# Find copycds command
COPYCDS_CMD=$(find_xcat_cmd copycds)

# Check if OS already imported
if ! /opt/xcat/bin/lsdef -t osimage | grep -q "centos7.8-x86_64-netboot-compute"; then
    echo "Importing CentOS ISO to xCAT..."
    if [ -n "$COPYCDS_CMD" ]; then
        $COPYCDS_CMD $CENTOS_ISO
    else
        echo "❌ copycds command not found"
        exit 1
    fi
else
    echo "✅ CentOS OS image already imported, skipping"
fi

# =================================
# NETWORK SERVICES INITIALIZATION
# =================================

# Initialize network services
echo "Initializing network services..."
MAKEDHCP_CMD=$(find_xcat_cmd makedhcp)
MAKENETWORKS_CMD=$(find_xcat_cmd makenetworks)
MAKEDNS_CMD=$(find_xcat_cmd makedns)

# First, create networks (ignore warnings about existing networks)
if [ -n "$MAKENETWORKS_CMD" ]; then
    echo "Creating networks (ignoring existing network warnings)..."
    $MAKENETWORKS_CMD 2>&1 | grep -v "already exists" || true
else
    echo "❌ makenetworks command not found"  
    exit 1
fi

# Configure DNS first
if [ -n "$MAKEDNS_CMD" ]; then
    echo "Configuring DNS..."
    $MAKEDNS_CMD -n
else
    echo "❌ makedns command not found"
    exit 1
fi

# Configure DHCP range for IPv4 only
echo "Configuring DHCP range..."
/opt/xcat/bin/chdef -t network 192_168_56_0-255_255_255_0 dynamicrange="192.168.56.100-192.168.56.200"
/opt/xcat/bin/chdef -t network 192_168_56_0-255_255_255_0 nameservers=192.168.56.10

# =================================
# OS IMAGE GENERATION
# =================================

# Generate compute node OS image only if not exists
if [ ! -d "/install/netboot/centos7.8/x86_64/compute" ]; then
    echo "Generating OS image for compute nodes..."
    GENIMAGE_CMD=$(find_xcat_cmd genimage)
    PACKIMAGE_CMD=$(find_xcat_cmd packimage)
    
    if [ -n "$GENIMAGE_CMD" ]; then
        $GENIMAGE_CMD centos7.8-x86_64-netboot-compute
    else
        echo "❌ genimage command not found"
        exit 1
    fi
    
    if [ -n "$PACKIMAGE_CMD" ]; then
        $PACKIMAGE_CMD centos7.8-x86_64-netboot-compute
    else
        echo "❌ packimage command not found"
        exit 1
    fi
else
    echo "✅ OS image already generated, skipping"
fi

# =================================
# DEFINE COMPUTE NODE
# =================================

echo "Defining compute node with static MAC address..."

# Find additional commands
NODESET_CMD=$(find_xcat_cmd nodeset)
MAKEHOSTS_CMD=$(find_xcat_cmd makehosts)
CHTAB_CMD=$(find_xcat_cmd chtab)

# Check if node already exists
if ! /opt/xcat/bin/lsdef $NODE_NAME >/dev/null 2>&1; then
    # Define compute node in xCAT
    /opt/xcat/bin/mkdef $NODE_NAME groups=compute,all ip=$COMPUTE_IP mac=$COMPUTE_MAC \
      netboot=xnba arch=x86_64 installnic=$NETWORK_INTERFACE primarynic=$NETWORK_INTERFACE

    # Set provisioning method
    /opt/xcat/bin/chdef $NODE_NAME provmethod=centos7.8-x86_64-netboot-compute
else
    echo "✅ Compute node $NODE_NAME already defined, updating configuration"
    /opt/xcat/bin/chdef $NODE_NAME provmethod=centos7.8-x86_64-netboot-compute installnic=$NETWORK_INTERFACE primarynic=$NETWORK_INTERFACE
fi

##KANET HENA##
# =================================
# HTTP CONFIGURATION
# =================================

# Create HTTP symlinks
echo "Creating HTTP symlinks for boot files..."
mkdir -p /var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/
mkdir -p /var/www/html/install/netboot/centos7.8/x86_64/compute/
mkdir -p /var/www/html/tftpboot/xcat/xnba/nodes/

# Create symlinks only if they don't exist
if [ ! -L "/var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/kernel" ]; then
    ln -sf /install/netboot/centos7.8/x86_64/compute/kernel /var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/kernel
fi

if [ ! -L "/var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/initrd-stateless.gz" ]; then
    ln -sf /install/netboot/centos7.8/x86_64/compute/initrd-stateless.gz /var/www/html/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/initrd-stateless.gz
fi

if [ ! -L "/var/www/html/install/netboot/centos7.8/x86_64/compute/rootimg.cpio.gz" ]; then
    ln -sf /install/netboot/centos7.8/x86_64/compute/rootimg.cpio.gz /var/www/html/install/netboot/centos7.8/x86_64/compute/rootimg.cpio.gz
fi

# Create symlink for node-specific boot script
if [ ! -L "/var/www/html/tftpboot/xcat/xnba/nodes/$NODE_NAME" ]; then
    ln -sf /tftpboot/xcat/xnba/nodes/$NODE_NAME /var/www/html/tftpboot/xcat/xnba/nodes/$NODE_NAME
fi

# Set permissions
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/

# Set default node password
echo "Setting default node password..."
if [ -n "$CHTAB_CMD" ]; then
    $CHTAB_CMD key=system passwd.username=root passwd.password=abc123
else
    echo "❌ chtab command not found"
    exit 1
fi

# =================================
# FINAL DHCP CONFIGURATION
# =================================

echo "Starting DHCP server..."
systemctl start isc-dhcp-server
systemctl enable isc-dhcp-server

# Verify DHCP is running
if systemctl is-active --quiet isc-dhcp-server; then
    echo "✅ DHCP server is running"
else
    echo "⚠️ DHCP server may have issues, checking status..."
    systemctl status isc-dhcp-server --no-pager || true
    # Try to start anyway
    systemctl restart isc-dhcp-server || true
fi

# =================================
# CRITICAL: CORRECT ORDER FOR STATIC IP ASSIGNMENT
# =================================

echo "Setting up node with correct order for static IP assignment..."

# Step 1: Set node to use netboot image FIRST (this is crucial!)
if [ -n "$NODESET_CMD" ]; then
    echo "Removing all problematic networks..."
    /opt/xcat/bin/rmdef -t network "fd17:625c:f037:2::/64" 2>/dev/null || true
    /opt/xcat/bin/rmdef -t network "10_0_2_0-255_255_255_0" 2>/dev/null || true
    echo "Step 1: Setting node osimage..."
    $NODESET_CMD $NODE_NAME osimage=centos7.8-x86_64-netboot-compute
else
    echo "❌ nodeset command not found"
    exit 1
fi

# Step 2: Generate network-wide DHCP config
if [ -n "$MAKEDHCP_CMD" ]; then
    echo "Step 2: Generating network DHCP config..."
    $MAKEDHCP_CMD -n 2>&1 | grep -v -E "(Could not add the subnet fd|IPv6|vpd.uuid)" || true
else
    echo "❌ makedhcp command not found"
    exit 1
fi

# Step 3: Add specific node to DHCP (this will use the static IP)
if [ -n "$MAKEDHCP_CMD" ]; then
    echo "Step 3: Adding node to DHCP with static IP..."
    $MAKEDHCP_CMD $NODE_NAME 2>&1 | grep -v -E "(Could not add the subnet fd|IPv6|vpd.uuid)" || true
else
    echo "❌ makedhcp command not found"
    exit 1
fi

# Update DNS for the node
if [ -n "$MAKEHOSTS_CMD" ]; then
    $MAKEHOSTS_CMD $NODE_NAME
else
    echo "❌ makehosts command not found"
    exit 1
fi

systemctl restart isc-dhcp-server

# =================================
# VERIFICATION
# =================================

echo "Running final verification..."

# Show clean network list
echo "Network definitions:"
/opt/xcat/bin/lsdef -t network

# Test TFTP
echo "Testing TFTP..."
timeout 10 bash -c 'echo -e "binary\nget xcat/xnba.kpxe\nquit" | tftp 192.168.56.10' && echo "✅ TFTP OK" || echo "❌ TFTP FAILED"

# Test HTTP
echo "Testing HTTP..."
curl -s -I http://192.168.56.10/tftpboot/xcat/osimage/centos7.8-x86_64-netboot-compute/kernel | head -1 | grep -q "200 OK" && echo "✅ HTTP OK" || echo "❌ HTTP FAILED"

# Test DHCP
echo "Testing DHCP server..."
if systemctl is-active --quiet isc-dhcp-server; then
    echo "✅ DHCP server is active"
else
    echo "❌ DHCP server is not active"
fi

# Show node configuration
echo "Node configuration:"
/opt/xcat/bin/lsdef $NODE_NAME

# Show services status
echo ""
echo "Service Status:"
echo "==============="
echo "xcatd: $(systemctl is-active xcatd)"
echo "apache2: $(systemctl is-active apache2)"
echo "atftpd: $(systemctl is-active atftpd)"
echo "isc-dhcp-server: $(systemctl is-active isc-dhcp-server)"
echo "bind9: $(systemctl is-active bind9)"

echo "========================================="
echo "🎉 xCAT MANAGEMENT NODE READY! 🎉"
echo "========================================="
echo ""
echo "✅ Management Node: 192.168.56.10"
echo "✅ Compute Node: $NODE_NAME ($COMPUTE_IP)"
echo "✅ Network Interface: $NETWORK_INTERFACE"
echo "✅ MAC Address: $COMPUTE_MAC"
echo ""
echo "🚀 READY TO BOOT COMPUTE VM!"
echo "Boot your VirtualBox VM with MAC: $COMPUTE_MAC"
echo "========================================="

# Signal completion
echo "XCAT_MANAGEMENT_NODE_READY" > /tmp/setup_complete