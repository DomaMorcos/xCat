set -e  # Exit on any error

# Predefined compute node details
COMPUTE_IP="192.168.56.6"
COMPUTE_MAC="08:00:27:AB:CD:EF"
NODE_NAME="computenode"

echo "========================================="
echo "xCAT Phase 1: Base Setup (No ISO)"
echo "========================================="

# Update system
echo "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y software-properties-common wget curl yum rpm

# =================================
# xCAT INSTALLATION
# =================================

echo "Setting up xCAT directories..."
mkdir -p /home/vagrant/xcat
cd /home/vagrant/xcat

# Download xcat-core only if not exists
XCAT_CORE_FILE="xcat-core-2.16.5-ubuntu.tar.bz2"
if [ ! -f "$XCAT_CORE_FILE" ]; then
    echo "Downloading xcat-core (~30MB)..."
    wget --progress=bar:force --timeout=0 --tries=0 --retry-connrefused --waitretry=30 http://xcat.org/files/xcat/xcat-core/2.16.x_Ubuntu/xcat-core/$XCAT_CORE_FILE
    echo "✅ xcat-core download completed"
else
    echo "✅ xcat-core archive already exists, skipping download"
fi

# Extract only if directory doesn't exist
if [ ! -d "xcat-core" ]; then
    echo "Extracting xcat-core..."
    tar jxf $XCAT_CORE_FILE
else
    echo "✅ xcat-core directory already exists, skipping extraction"
fi

# Configure xcat-core repo
echo "Configuring xcat-core repository..."
cd xcat-core
./mklocalrepo.sh
cd ..

# Download xcat-dep only if not exists
XCAT_DEP_FILE="xcat-dep-2.16.5-ubuntu.tar.bz2"
if [ ! -f "$XCAT_DEP_FILE" ]; then
    echo "Downloading xcat-dep (~2MB)..."
    wget --progress=bar:force --timeout=0 --tries=0 --retry-connrefused --waitretry=30 https://xcat.org/files/xcat/xcat-dep/2.x_Ubuntu/$XCAT_DEP_FILE
    echo "✅ xcat-dep download completed"
else
    echo "✅ xcat-dep archive already exists, skipping download"
fi

# Extract only if directory doesn't exist
if [ ! -d "xcat-dep" ]; then
    echo "Extracting xcat-dep..."
    tar jxf $XCAT_DEP_FILE
else
    echo "✅ xcat-dep directory already exists, skipping extraction"
fi

# Configure xcat-dep repo
echo "Configuring xcat-dep repository..."
cd xcat-dep
./mklocalrepo.sh
cd ..

# Create xCAT repositories
echo "Creating xCAT repositories..."
tee /etc/apt/sources.list.d/xcat-core.list << EOF
deb [arch=amd64 trusted=yes] file:///home/vagrant/xcat/xcat-core bionic main
EOF

tee /etc/apt/sources.list.d/xcat-dep.list << EOF
deb [arch=amd64 trusted=yes] file:///home/vagrant/xcat/xcat-dep bionic main
EOF

# Add Ubuntu repositories
echo "Adding Ubuntu repositories..."
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main" -y
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates main" -y
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe" -y
add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates universe" -y

# Install xCAT
echo "Installing xCAT..."
apt-get clean all
apt-get update
apt-get install -y xcat

# Source xCAT environment for current session
echo "Configuring xCAT environment..."
source /etc/profile.d/xcat.sh
export PATH=/opt/xcat/bin:/opt/xcat/sbin:$PATH

# Wait for xCAT daemon to start
echo "Waiting for xCAT daemon..."
sleep 20

# Start xCAT daemon if not running
systemctl start xcatd || true
sleep 10

# Verify xCAT installation
echo "Verifying xCAT installation..."
/opt/xcat/bin/lsxcatd -a || echo "lsxcatd not yet ready"

# =================================
# PREPARE FOR ISO COPY
# =================================

echo "Creating ISO directory..."
mkdir -p /isos
chmod 755 /isos

# =================================
# TFTP CONFIGURATION
# =================================

echo "Fixing TFTP configuration..."
sed -i 's|TFTP_DIRECTORY="/var/lib/tftpboot"|TFTP_DIRECTORY="/tftpboot"|' /etc/default/tftpd-hpa
systemctl restart tftpd-hpa
sleep 5

echo "========================================="
echo "🎯 PHASE 1 COMPLETE!"
echo "========================================="
echo ""
echo "✅ xCAT installed and configured"
echo "✅ ISO directory created: /isos"
echo "✅ Ready for ISO copy"
echo ""
echo "📋 NEXT STEPS:"
echo "1. On host machine, run: ./copy-iso.sh"
echo "2. Then run: vagrant provision --provision-with shell"
echo "   OR run: vagrant ssh -c 'sudo /tmp/bootstrap-phase2.sh'"
echo "========================================="

# Save environment for phase 2
echo "COMPUTE_IP=$COMPUTE_IP" > /tmp/xcat-env
echo "COMPUTE_MAC=$COMPUTE_MAC" >> /tmp/xcat-env  
echo "NODE_NAME=$NODE_NAME" >> /tmp/xcat-env
echo "PHASE1_COMPLETE" > /tmp/phase1_done