set -e

CENTOS_ISO="CentOS-7-x86_64-DVD-2003.iso"

echo "========================================="
echo "Copying CentOS ISO to xCAT VM"
echo "========================================="

# Check if ISO exists on host
if [ ! -f "$CENTOS_ISO" ]; then
    echo "❌ $CENTOS_ISO not found in current directory"
    echo "Downloading CentOS ISO..."
    wget https://ftp.iij.ad.jp/pub/linux/centos-vault/7.8.2003/isos/x86_64/$CENTOS_ISO
fi

echo "✅ ISO found: $(ls -lh $CENTOS_ISO)"

# Check if VM is running
if ! vagrant status | grep -q "running"; then
    echo "❌ VM is not running. Run 'vagrant up' first."
    exit 1
fi

echo "📡 Copying ISO to VM..."

# Method 1: Copy to tmp first, then move
echo "Step 1: Copying to /tmp..."
scp -P $(vagrant ssh-config | grep Port | awk '{print $2}') \
    -i $(vagrant ssh-config | grep IdentityFile | awk '{print $2}' | tr -d '"') \
    -o StrictHostKeyChecking=no \
    $CENTOS_ISO vagrant@127.0.0.1:/tmp/

echo "Step 2: Moving to /isos with sudo..."
vagrant ssh -c "sudo mkdir -p /isos"
vagrant ssh -c "sudo mv /tmp/$CENTOS_ISO /isos/"
vagrant ssh -c "sudo chown root:root /isos/$CENTOS_ISO"
vagrant ssh -c "sudo chmod 644 /isos/$CENTOS_ISO"

echo "✅ ISO copied successfully"

# Verify the copy
echo "📋 Verifying ISO in VM..."
vagrant ssh -c "ls -lh /isos/$CENTOS_ISO"

echo "========================================="
echo "🎯 ISO COPY COMPLETE!"
echo "========================================="
echo ""
echo "📋 NEXT STEP:"
echo "Run phase 2: vagrant provision --provision-with phase2-copy,phase2-chmod,phase2-run"
echo "========================================="