#!/bin/bash
set -e  # Exit on error
# ###############################
# Execute basic install
# ###############################

# GitHub token for private repo access
# Generate at: https://github.com/settings/tokens (needs 'repo' scope)
# Set before running: export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: GITHUB_TOKEN not set"
    echo "Generate a token at: https://github.com/settings/tokens"
    echo "Then run: export GITHUB_TOKEN='ghp_your_token_here'"
    exit 1
fi

# Function for authenticated GitHub downloads
gh_download() {
    local url="$1"
    local output="$2"
    curl -H "Authorization: token $GITHUB_TOKEN" -L -o "$output" "$url"
}

# Capture the start time (example)
START_TIME=$(date +%s)

# Define the log file and create it (or touch it if exists)
LOGFILE="/home/pi/loginstall.txt"
touch "$LOGFILE"

# Function to log messages with timestamp
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

echo "################################################################################"
echo "Set Privileges for www-data"
echo "################################################################################"

# Ensure the script is run as root.
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root."
    exit 1
fi

# Add www-data to the sudo group.
usermod -a -G sudo www-data

log_message "Added www-data to the sudo group"
echo "✅ Added www-data to the sudo group"

# Configure passwordless sudo for www-data.
# Create a sudoers file specifically for www-data in /etc/sudoers.d/
SUDOERS_FILE="/etc/sudoers.d/www-data-nopasswd"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "www-data ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"

    log_message "Configured passwordless sudo for www-data"
    echo "✅ Configured passwordless sudo for www-data"
else
    log_message "Passwordless sudo for www-data is already configured"
    echo "✅ Passwordless sudo for www-data is already configured"
fi

echo "################################################################################"
echo "Create botdata and chat_ids files"
echo "################################################################################"

sudo touch botdata.txt
sudo touch chat_ids.txt
sudo touch tails.txt

log_message "Create botdata and chat_ids files successful"
echo "✅  Create botdata and chat_ids files successful"

echo "################################################################################"
echo "Set Values"
echo "################################################################################"

# Ask user input (no defaults)
read -p "What is your Telegram Chat ID: " chat_id
read -p "What is your Telegram Bot Token: " token
read -p "What is your BTC Wallet Public Address: " btcaddress
read -p "What is your Blockonomics.co API Key: " apikey
read -p "What is your Tailscale Key: " tailskey  
read -p "What is your Public SSH Key: " sshkey

# Store values in files
echo "$chat_id" | sudo tee chat_ids.txt botdata.txt > /dev/null
echo "$token" | sudo tee -a botdata.txt > /dev/null
echo "$btcaddress" | sudo tee -a botdata.txt > /dev/null
echo "$apikey" | sudo tee -a botdata.txt > /dev/null
echo "$tailskey" | sudo tee tails.txt > /dev/null

# Read stored values
ID=$(sed -n '1p' botdata.txt)
TOKEN=$(sed -n '2p' botdata.txt)
ADD=$(sed -n '3p' botdata.txt)
API=$(sed -n '4p' botdata.txt)
AUTH=$(head -n 1 tails.txt) 

# Print stored values
echo "Your Telegram Admin Chat ID is: $ID"
echo "Your Telegram Bot Token is: $TOKEN"
echo "Your Wallet Public Address is: $ADD"
echo "Your Blockonomics API Key is: $API"
echo "Your Tailscale Key is: $AUTH"

log_message "Setting Bot Token, Chat ID, BTC Address, API key, and Tailscale Key successful"
echo "✅ Setting Bot Token, Chat ID, BTC Address, API key, and Tailscale Key successful"

echo "################################################################################"
echo "Fix Language Local"
echo "################################################################################"

sudo touch /etc/environment

sudo echo "LANGUAGE=en_US" | sudo tee -a /etc/environment
sudo echo "LC_ALL=en_US" | sudo tee -a /etc/environment
sudo echo "LANG=en_US" | sudo tee -a /etc/environment
sudo echo "LC_TYPE=en_US" | sudo tee -a /etc/environment

sudo rm /etc/default/locale
sudo touch /etc/default/locale

sudo echo "LANG=en_US.UTF-8" | sudo tee -a /etc/default/locale
sudo echo "LC_CTYPE=en_US.UTF-8" | sudo tee -a /etc/default/locale
sudo echo "LC_MESSAGES=en_US.UTF-8" | sudo tee -a /etc/default/locale
sudo echo "LC_ALL=en_US.UTF-8" | sudo tee -a /etc/default/locale

sudo localedef -f UTF-8 -i en_US en_US.UTF-8 

sudo sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
sudo sed -i 's/en_GB.UTF-8 UTF-8/# en_GB.UTF-8 UTF-8/g' /etc/locale.gen

log_message "Fixing Language Local successful"
echo "✅ Fixing Language Local successful"

echo "################################################################################"
echo "Secure SSH for target user"
echo "################################################################################"

# Set non-interactive mode to avoid prompts during package updates
export DEBIAN_FRONTEND=noninteractive

# Force dpkg to use default configuration options (keep the local version)
echo "force-confdef" | sudo tee /etc/dpkg/dpkg.cfg.d/99forceconf > /dev/null
echo "force-confold" | sudo tee -a /etc/dpkg/dpkg.cfg.d/99forceconf > /dev/null

# Define the target user and its home directory (modify if needed)
TARGET_USER="pi"
TARGET_HOME=$(eval echo "~$TARGET_USER")

# Define your public key.
PUBKEY='$sshkey'
# Ensure the target user's .ssh directory exists with proper permissions.
SSH_DIR="$TARGET_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    # Ensure ownership is set to the target user.
    sudo chown -R "$TARGET_USER":"$TARGET_USER" "$SSH_DIR"
fi

# Append the public key if it is not already in authorized_keys.
if [ -f "$AUTH_KEYS" ]; then
    if grep -Fxq "$PUBKEY" "$AUTH_KEYS"; then
        echo "Public key already exists in authorized_keys."
    else
        echo "$PUBKEY" >> "$AUTH_KEYS"
        echo "Public key added to authorized_keys."
    fi
else
    echo "$PUBKEY" > "$AUTH_KEYS"
    echo "authorized_keys file created and public key added."
fi

chmod 600 "$AUTH_KEYS"
sudo chown "$TARGET_USER":"$TARGET_USER" "$AUTH_KEYS"

# Update /etc/ssh/sshd_config non-interactively (this applies systemwide)
SSHD_CONFIG="/etc/ssh/sshd_config"

# Ensure PubkeyAuthentication is enabled
if grep -Ei "^#?PubkeyAuthentication" "$SSHD_CONFIG" > /dev/null; then
    sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
    echo "PubkeyAuthentication set to yes in $SSHD_CONFIG."
else
    echo "PubkeyAuthentication yes" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    echo "PubkeyAuthentication added to $SSHD_CONFIG."
fi

# Disable password authentication
if grep -Ei "^#?PasswordAuthentication" "$SSHD_CONFIG" > /dev/null; then
    sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
    echo "PasswordAuthentication set to no in $SSHD_CONFIG."
else
    echo "PasswordAuthentication no" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    echo "PasswordAuthentication disabled in $SSHD_CONFIG."
fi

# Restart SSH service to apply changes
if command -v systemctl > /dev/null; then
    sudo systemctl restart sshd
else
    sudo service ssh restart
fi

log_message "SSH public key configuration complete for user $TARGET_USER"
echo "✅ SSH public key configuration complete for user $TARGET_USER"

echo "################################################################################"
echo "Apt Update & Upgrade & Install jq, python3, git, and pip"
echo "################################################################################"

# Set environment variables in the current shell
export DEBIAN_FRONTEND=noninteractive
export UCF_FORCE_CONFFOLD=1

# Use sudo with -E to preserve the environment variables
sudo -E apt update && \
sudo -E apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

sudo -E apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    python3 python3-pip jq pip git acl

log_message "Apt Update & Upgrade, Install jq, python3, git & pip successful"
echo "✅ Apt Update & Upgrade, Install jq, python3, git & pip successful"

echo "################################################################################"
echo "Mount SSD"
echo "################################################################################"

# Check if the partition /dev/sda2 exists as a block device.
if [ ! -b /dev/sda2 ]; then
  echo "❌ Error: SSD (/dev/sda2) not detected. Please check the SSD connection."
  echo "Press Enter once the issue is resolved to continue..."
  read -r
fi

# Check if /dev/sda2 is mounted and unmount it if necessary.
if mount | grep -q "/dev/sda2"; then
  echo "Partition /dev/sda2 is currently mounted. Unmounting..."
  sudo umount /dev/sda2
fi

# Format /dev/sda2 with ext4 (Warning: this erases all data on the partition)
echo "Formatting /dev/sda2 with ext4..."
sudo mkfs.ext4 -F /dev/sda2

# Create the mount point directory
echo "Creating mount point at /mnt/hdd..."
sudo mkdir -p /mnt/hdd

# Mount the partition
echo "Mounting /dev/sda2 to /mnt/hdd..."
sudo mount /dev/sda2 /mnt/hdd

# Add entry to /etc/fstab for automatic mounting on boot
echo "Adding entry to /etc/fstab if not already present..."
if ! grep -q "/dev/sda2[[:space:]]\+/mnt/hdd" /etc/fstab; then
  echo "/dev/sda2   /mnt/hdd   ext4   defaults,noatime   0   2" | sudo tee -a /etc/fstab
else
  echo "Entry for /dev/sda2 already exists in /etc/fstab"
fi

log_message "Mount SSD successful"
echo "✅ Mount SSD successful"

echo "################################################################################"
echo "Install Tailscale"
echo "################################################################################"

# Update package lists
#sudo apt update
# Install iptables dependency before installing Tailscale
sudo apt install -y iptables
# Download and install Tailscale package
sudo wget -O tailscale_1.80.0_armhf.deb "https://github.com/micheldegeofroy/Tailscale/raw/refs/heads/main/tailscale_1.80.0_armhf.deb"
sudo dpkg -i tailscale_1.80.0_armhf.deb
# Fix any missing dependencies
sudo apt install -f -y
# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
# Start and enable Tailscale (corrected syntax)
sudo tailscale up --advertise-exit-node --authkey="tskey-auth-$AUTH"
sudo systemctl enable --now tailscaled

log_message "Your Raspberry Pi is now connected to Tailscale with IP: $TAILSCALE_IP"
echo "✅ Your Raspberry Pi is now connected to Tailscale with IP: $TAILSCALE_IP"

#sudo systemctl status tailscaled
#https://login.tailscale.com/

echo "################################################################################"
echo "Install Bitcoind"
echo "################################################################################"

# Download and extract Bitcoin Core tarball
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/main/bitcoin-27.0-aarch64-linux-gnu.tar.gz" "bitcoin-27.0-aarch64-linux-gnu.tar.gz" && sudo tar -xzvf bitcoin-27.0-aarch64-linux-gnu.tar.gz

# Move Bitcoin binaries to /usr/local/bin
sudo mv bitcoin-27.0/bin/* /usr/local/bin/

# Create data directory on /mnt/hdd and download bitcoin.conf into it
mkdir -p /mnt/hdd/.bitcoin
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/bitcoin.conf" "/mnt/hdd/.bitcoin/bitcoin.conf"

# Create symlink for default Bitcoin data directory
ln -s /mnt/hdd/.bitcoin ~/.bitcoin

log_message "Bitcoin Install successful"
echo "✅ Bitcoin Install successful"

echo "################################################################################"
echo "Creating bitcoind systemd service file"
echo "################################################################################"

# Create the systemd service file using a here document
sudo tee /etc/systemd/system/bitcoind.service > /dev/null << 'EOF'
[Unit]
Description=Bitcoin Daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/bitcoind -daemon -datadir=/mnt/hdd/.bitcoin
ExecStop=/usr/local/bin/bitcoin-cli -datadir=/mnt/hdd/.bitcoin stop
User=root
Group=root
Type=forking
PIDFile=/mnt/hdd/.bitcoin/bitcoind.pid
Restart=on-failure
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to pick up the new service
sudo systemctl enable bitcoind.service
sudo systemctl daemon-reload

log_message "bitcoind systemd service created and systemd reloaded"
echo "✅ bitcoind systemd service created and systemd reloaded"

echo "################################################################################"
echo "Install BFGminer"
echo "################################################################################"

# Ensure the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo or run as root."
    exit 1
fi

# Update the package list and install required dependencies
echo "Updating package list and installing required dependencies..."
apt-get update
apt-get install -y build-essential automake autoconf libtool pkg-config libcurl4-openssl-dev libncurses5-dev git libevent-dev
sudo apt-get install libjansson-dev

# Clone the BFGMiner repository into /root/bfgminer
echo "Cloning BFGMiner repository into /bfgminer..."
git clone https://github.com/luke-jr/bfgminer.git bfgminer
cd bfgminer || exit 1

# Store the bfgminer directory path in a variable so we can come back to it
PROJECT_DIR="$(pwd)"

# Configure git to use https:// instead of git://
echo "Configuring Git to use https:// instead of git://"
git config --global url."https://".insteadOf git://

# Run autogen.sh to generate necessary files
echo "Running autogen.sh to generate necessary files..."
./autogen.sh

# Move to /tmp to download uthash headers
echo "Downloading uthash headers..."
cd /tmp || exit 1
wget https://raw.githubusercontent.com/troydhanson/uthash/v2.3.0/src/utlist.h
cp utlist.h /usr/local/include/utlist.h

wget https://raw.githubusercontent.com/troydhanson/uthash/v2.3.0/src/uthash.h
cp uthash.h /usr/local/include/uthash.h

# Return to the bfgminer directory using the stored path
echo "Returning to bfgminer directory..."
cd "$PROJECT_DIR" || exit 1

# Run configure with the necessary flags
echo "Running configure..."
./configure --enable-cpumining CPPFLAGS="-I/usr/local/include"

# Build and install BFGMiner
echo "Building and installing BFGMiner..."
make
make install

cd ../

log_message "BFGMiner installation complete!"
echo "✅ BFGMiner installation complete!"

# Create the start_bfgminer.sh script
cat << 'EOF' | sudo tee /usr/local/bin/start_bfgminer.sh >/dev/null
#!/bin/bash
# start_bfgminer.sh
# This script waits until bitcoind is running and fully synchronized,
# then starts bfgminer for solo CPU mining using cookie-based RPC authentication.

# Configuration
DATADIR="/mnt/hdd/.bitcoin"
COOKIEFILE="${DATADIR}/.cookie"
BITCOIN_CLI="/usr/local/bin/bitcoin-cli"
BFGMINER="/usr/local/bin/bfgminer"
RPC_URL="http://127.0.0.1:8332"
SYNC_THRESHOLD=0.999  # Adjust sync threshold if needed

# NEW LINE: Parse your watch-only address (3rd line in botdata.txt)
WATCH_ONLY_ADDR=$(sed -n '3p' /home/pi/botdata.txt)

echo "Checking if bitcoind is running and synced..."
while true; do
    sync=$(sudo "$BITCOIN_CLI" -datadir="$DATADIR" -rpccookiefile="$COOKIEFILE" getblockchaininfo 2>/dev/null | jq -r '.verificationprogress')
    if [ -n "$sync" ] && [ "$sync" != "null" ]; then
        if (( $(echo "$sync >= $SYNC_THRESHOLD" | bc -l) )); then
            echo "bitcoind is synced (verificationprogress=$sync)"
            break
        else
            echo "bitcoind sync in progress (verificationprogress=$sync)"
        fi
    else
        echo "bitcoind not responding yet"
    fi
    sleep 30
done

echo "Starting bfgminer for solo CPU mining..."
echo "Using watch-only address: $WATCH_ONLY_ADDR"
RPC_USER=$(sudo cat "$COOKIEFILE" | cut -d':' -f1)
RPC_PASS=$(sudo cat "$COOKIEFILE" | cut -d':' -f2)
sudo "$BFGMINER" --cpu -a sha256d -o "$RPC_URL" -u "$RPC_USER" -p "$RPC_PASS" \
     --coinbase-addr="$WATCH_ONLY_ADDR"    
EOF

# Make the shell script executable
sudo chmod +x /usr/local/bin/start_bfgminer.sh

# Create the systemd service unit file
cat << 'EOF' | sudo tee /etc/systemd/system/bfgminer.service >/dev/null
[Unit]
Description=BFGMiner Solo CPU Mining Service
After=bitcoind.service
Wants=bitcoind.service

[Service]
Type=simple
ExecStart=/usr/local/bin/start_bfgminer.sh
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo apt-get update
sudo apt-get install bc

# Reload systemd daemon, enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable bfgminer.service
sudo systemctl start bfgminer.service

log_message "BFGMiner service created and started"
echo "✅ BFGMiner service created and started"

echo "################################################################################"
echo "Web Interface"
echo "################################################################################"

sudo apt install php -y
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/index.php" "/var/www/html/index.php"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/miner.php" "/var/www/html/miner.php"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/favicon.ico" "/var/www/html/favicon.ico"

log_message "Bitcoin Install successful"
echo "✅ Bitcoin Install successful"

echo "################################################################################"
echo "Disable Swap"
echo "################################################################################"

sudo swapoff --all
sudo apt remove dphys-swapfile -y

# Mask the RPi swap loop service to prevent /var/swap recreation
sudo systemctl mask rpi-setup-loop@var-swap.service 2>/dev/null || true

# Detach any loop devices using swap
sudo /sbin/losetup -D 2>/dev/null || true

# Delete swap file if exists
sudo rm -f /var/swap

log_message "Disabling Swap successful"
echo "✅ Disabling Swap successful"

echo "################################################################################"
echo "Install Speed Test"
echo "################################################################################"

sudo wget -O /usr/local/bin/speedtest-cli https://raw.githubusercontent.com/micheldegeofroy/speedtest-cli/master/speedtest.py
sudo chmod a+x /usr/local/bin/speedtest-cli

log_message "Install of speedtest-cli successful"
echo "✅ Install of speedtest-cli successful"

echo "################################################################################"
echo "Install WiFi Hotspot (hostapd, dnsmasq, redsocks)"
echo "################################################################################"

# Install required packages for WiFi hotspot
sudo -E apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    hostapd dnsmasq redsocks iw

# Stop and disable default services (we manage them manually)
sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable hostapd 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true

# Create hotspot scripts directory
sudo mkdir -p /etc/btcloto

# Download hotspot scripts from repo
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/main/scripts/hotspot-start.sh" "/usr/local/bin/hotspot-start.sh"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/main/scripts/hotspot-stop.sh" "/usr/local/bin/hotspot-stop.sh"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/main/scripts/hotspot-check-uplink.sh" "/usr/local/bin/hotspot-check-uplink.sh"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/main/configs/hotspot.conf.default" "/etc/btcloto/hotspot.conf"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/main/hotspot.service" "/etc/systemd/system/hotspot.service"

# Make scripts executable
sudo chmod +x /usr/local/bin/hotspot-start.sh
sudo chmod +x /usr/local/bin/hotspot-stop.sh
sudo chmod +x /usr/local/bin/hotspot-check-uplink.sh

# Reload systemd (but don't enable hotspot by default)
sudo systemctl daemon-reload

log_message "WiFi Hotspot installation successful"
echo "✅ WiFi Hotspot installation successful"

echo "################################################################################"
echo "Install VPN Clients (Hysteria, Xray, Shadowsocks, tun2socks)"
echo "################################################################################"

# Install shadowsocks-libev (for Outline VPN)
sudo -E apt install -y shadowsocks-libev

# Create config directories
sudo mkdir -p /etc/hysteria
sudo mkdir -p /usr/local/etc/xray
sudo mkdir -p /etc/shadowsocks-libev

# Install tun2socks (for routing hotspot traffic through SOCKS proxies)
echo "Installing tun2socks..."
TUN2SOCKS_VERSION="2.5.2"
TUN2SOCKS_URL="https://github.com/xjasonlyu/tun2socks/releases/download/v${TUN2SOCKS_VERSION}/tun2socks-linux-arm64.zip"
curl -L -o /tmp/tun2socks.zip "$TUN2SOCKS_URL"
unzip -o /tmp/tun2socks.zip -d /tmp/
sudo mv /tmp/tun2socks-linux-arm64 /usr/local/bin/tun2socks
sudo chmod +x /usr/local/bin/tun2socks
rm /tmp/tun2socks.zip

# Install Hysteria2 client
echo "Installing Hysteria2..."
bash -c "$(curl -fsSL https://get.hy2.sh/)" || {
    # Fallback: manual install
    HYSTERIA_URL="https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-arm64"
    sudo curl -L -o /usr/local/bin/hysteria "$HYSTERIA_URL"
    sudo chmod +x /usr/local/bin/hysteria
}

# Install Xray
echo "Installing Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install || {
    # Fallback: manual install
    XRAY_VERSION="1.8.24"
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-arm64-v8a.zip"
    curl -L -o /tmp/xray.zip "$XRAY_URL"
    unzip -o /tmp/xray.zip -d /tmp/xray/
    sudo mv /tmp/xray/xray /usr/local/bin/xray
    sudo chmod +x /usr/local/bin/xray
    rm -rf /tmp/xray /tmp/xray.zip
}

# Download default client configs
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/dev/configs/hysteria-client.yaml" "/etc/hysteria/config.yaml"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/dev/configs/xray-client.json" "/usr/local/etc/xray/config.json"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/dev/configs/outline-client.json" "/etc/shadowsocks-libev/outline.json"

# Fix permissions
sudo chmod 644 /etc/hysteria/config.yaml
sudo chmod 644 /usr/local/etc/xray/config.json
sudo chmod 644 /etc/shadowsocks-libev/outline.json

# Create systemd services for VPN clients
cat << 'EOF' | sudo tee /etc/systemd/system/hysteria-client.service
[Unit]
Description=Hysteria2 Client
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' | sudo tee /etc/systemd/system/outline.service
[Unit]
Description=Outline VPN Client (Shadowsocks)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ss-local -c /etc/shadowsocks-libev/outline.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Download vpn-diag diagnostic script
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/dev/scripts/vpn-diag.sh" "/usr/local/bin/vpn-diag"
sudo chmod +x /usr/local/bin/vpn-diag

# Reload systemd
sudo systemctl daemon-reload

# Enable VPN services (but don't start - user configures first)
sudo systemctl enable hysteria-client 2>/dev/null || true
sudo systemctl enable outline 2>/dev/null || true
sudo systemctl enable xray 2>/dev/null || true

log_message "VPN Clients installation successful"
echo "✅ VPN Clients installation successful"

echo "################################################################################"
echo "Install Connectivity Watchdog (auto-recovery from network issues)"
echo "################################################################################"

# Download connectivity watchdog script
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/dev/scripts/connectivity-watchdog.sh" "/usr/local/bin/connectivity-watchdog.sh"
sudo chmod +x /usr/local/bin/connectivity-watchdog.sh

# Create systemd service
cat << 'EOF' | sudo tee /etc/systemd/system/connectivity-watchdog.service
[Unit]
Description=Connectivity Watchdog - Auto-recover from network issues
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/connectivity-watchdog.sh
EOF

# Create systemd timer (runs every 5 minutes)
cat << 'EOF' | sudo tee /etc/systemd/system/connectivity-watchdog.timer
[Unit]
Description=Run connectivity watchdog every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
sudo systemctl daemon-reload
sudo systemctl enable --now connectivity-watchdog.timer

log_message "Connectivity Watchdog installation successful"
echo "✅ Connectivity Watchdog installation successful"

echo "################################################################################"
echo "Install watchdog"
echo "################################################################################"

sudo echo "#Watchdog On" | sudo tee -a /boot/config.txt
sudo echo "dtparam=watchdog=on" | sudo tee -a /boot/config.txt

sudo apt install watchdog -y
sudo echo "watchdog-device = /dev/watchdog" | sudo tee -a /etc/watchdog.conf
sudo echo "watchdog-timeout = 15" | sudo tee -a /etc/watchdog.conf
sudo echo "max-load-1 = 24" | sudo tee -a /etc/watchdog.conf

sudo systemctl enable watchdog
sudo systemctl start watchdog

log_message "Install Install watchdog successful"
echo "✅ Install Install watchdog successful"

echo "################################################################################"
echo "Stop IPV6"
echo "################################################################################"

echo net.ipv6.conf.all.disable_ipv6=1 | sudo tee /etc/sysctl.d/disable-ipv6.conf
sysctl --system
sudo sed -i -e 's/$/ipv6.disable=1/' /boot/cmdline.txt

log_message "Stopping IPV6 successful"
echo "✅ Stopping IPV6 successful"

echo "################################################################################"
echo "Disable BT"
echo "################################################################################"

sudo echo "# Disable Bluetooth" | sudo tee -a /boot/config.txt
sudo echo "dtoverlay=disable-bt" | sudo tee -a /boot/config.txt
sudo systemctl disable hciuart.service 
sudo systemctl disable bluetooth.service

log_message "Disablling BT successful"
echo "✅ Disablling BT successful"

#echo "################################################################################"
#echo "Install mymacchanger"
#echo "################################################################################"

#sudo wget "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/mymacchanger.py" -P /home/pi/
#sudo wget "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/mymacchanger.service" -P /etc/systemd/system/
#sudo chmod +x /home/pi/mymacchanger.py

#log_message "Installing mymacchanger successful"
#echo "✅ Installing mymacchanger successful"

echo "################################################################################"
echo "Install telegram bot"
echo "################################################################################"

sudo pip install mnemonic bip32utils --break-system-packages
sudo pip install bitcoin --break-system-packages
sudo pip install requests --break-system-packages
sudo pip3 install python-telegram-bot==13.15 --upgrade --break-system-packages
sudo pip install telepot --break-system-packages
sudo pip install RPi.GPIO --break-system-packages

sudo mkdir /home/pi/Bots/
sudo echo "0,0" | sudo tee /home/pi/Bots/btcbalance.txt

gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/script.py" "script.py"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/Bot.py" "/home/pi/Bots/Bot.py"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/walletcheck.py" "/home/pi/Bots/walletcheck.py"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/bot.service" "/etc/systemd/system/bot.service"
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/wallet.service" "/etc/systemd/system/wallet.service"

# Read the first, second and third line of the botdata.txt file
replace_value1=$(head -n 1 botdata.txt)
replace_value2=$(tail -n +2 botdata.txt | head -n 1)
replace_value3=$(tail -n +3 botdata.txt | head -n 1)
replace_value4=$(tail -n +4 botdata.txt | head -n 1)

# Replace the target value in the Bot.py script with the replacement values from botdata.txt
sed -i "s/replacewithyourapikey/$replace_value4/g" /home/pi/Bots/Bot.py 
sed -i "s/replacewithyourbottoken/$replace_value2/g" /home/pi/Bots/Bot.py  
sed -i "s/replacewithadminchatid/$replace_value1/g" /home/pi/Bots/Bot.py 
sed -i "s/1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa/$replace_value3/g" /home/pi/Bots/Bot.py 

# Replace the target value in the walletcheck.py script with the replacement values from botdata.txt
sed -i "s/replacewithyourapikey/$replace_value4/g" /home/pi/Bots/walletcheck.py 
sed -i "s/replacewithyourbottoken/$replace_value2/g" /home/pi/Bots/walletcheck.py 
sed -i "s/replacewithadminchatid/$replace_value1/g" /home/pi/Bots/walletcheck.py 
sed -i "s/1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa/$replace_value3/g" /home/pi/Bots/walletcheck.py 

# Replace the target value in the script.py script with the replacement values from botdata.txt
sed -i "s/replacewithyourbottoken/$replace_value2/g" /home/pi/script.py

sudo python3 script.py
sudo rm -r script.py

# Confirm that the replacement has been made
echo "The Admin User Chat ID, Bot Token and BTC address have been set in script.py & Bot.py & walletcheck.py files."

sudo systemctl enable bot.service
sudo systemctl start bot.service
sudo systemctl enable wallet.service
sudo systemctl start wallet.service

log_message "Installing telegram bot successful"
echo "✅ Installing telegram bot successful"

echo "################################################################################"
echo "SSH Custom Login Splash Screen"
echo "################################################################################"

sudo rm -r /etc/motd
gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/motd" "/etc/motd"

log_message "Installing SSH Custom Login Splash Screen successful"
echo "✅ Installing SSH Custom Login Splash Screen successful"

echo "################################################################################"
echo "SSH Welcome Interface"
echo "################################################################################"

mkdir -p /etc/update-motd.d/

gh_download "https://raw.githubusercontent.com/micheldegeofroy/Lotominer/master/ssh-welcome" "/etc/update-motd.d/ssh-welcome"
sudo chmod +x /etc/update-motd.d/ssh-welcome

log_message "Installing SSH Welcome Interface successful"
echo "✅ Installing SSH Welcome Interface successful"

echo "################################################################################"
echo "Final Reboot & Clean Up"
echo "################################################################################"

# Uncomment and adjust the following line if you need to enable a service
# sudo systemctl enable mymacchanger.service

#Remove index.html
sudo rm /var/www/html/index.html

#Fix for permissions needed
sudo setfacl -m u:www-data:--x /home/pi

#fix for bug RU rejected
sudo iw reg set US

# Clean up apt packages
sudo apt purge -y
sudo apt autoremove -y
sudo apt clean
sudo apt autoclean -y

# Remove leftover installation packages
echo "Deleting the install scripts..."
sudo rm -f bitcoin-27.0-aarch64-linux-gnu.tar.gz tailscale_1.80.0_armhf.deb install.sh

log_message "Final Reboot & Clean Up successful"
echo "✅ Final Reboot & Clean Up successful"
# Capture the end time
END_TIME=$(date +%s)

# Calculate the execution time in seconds
EXECUTION_TIME=$((END_TIME - START_TIME))

# Convert seconds to hours, minutes, and seconds
HOURS=$((EXECUTION_TIME / 3600))
MINUTES=$(( (EXECUTION_TIME % 3600) / 60 ))
SECONDS=$((EXECUTION_TIME % 60))

# Format the output
echo "Execution time: ${HOURS} hr/s ${MINUTES} min/s ${SECONDS} sec/s"

echo "################################################################################"
echo "Script execution time: $EXECUTION_TIME seconds."
echo "################################################################################"
log_message "Installation script completed in $EXECUTION_TIME seconds"
# Schedule a reboot in 60 seconds (runs in the background)
(sleep 60 && sudo reboot) &

sudo journalctl -p err -b
