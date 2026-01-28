#!/bin/bash
# hotspot-stop.sh - Stop WiFi hotspot and cleanup
# Part of BTCLOTO - Bitcoin Solo Miner

LOG_FILE="/var/log/hotspot.log"
CONFIG_FILE="/etc/btcloto/hotspot.conf"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

HOTSPOT_GATEWAY="${HOTSPOT_GATEWAY:-192.168.50.1}"
AP_INTERFACE="${AP_INTERFACE:-wlan0}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

log "Stopping WiFi hotspot..."

# Stop hostapd
if [ -f /run/hostapd.pid ]; then
    kill $(cat /run/hostapd.pid) 2>/dev/null || true
    rm -f /run/hostapd.pid
fi
killall hostapd 2>/dev/null || true

# Stop dnsmasq (hotspot instance)
if [ -f /run/dnsmasq-hotspot.pid ]; then
    kill $(cat /run/dnsmasq-hotspot.pid) 2>/dev/null || true
    rm -f /run/dnsmasq-hotspot.pid
fi
# Only kill dnsmasq if it's our hotspot instance
pkill -f "dnsmasq.*hotspot" 2>/dev/null || true

# Stop redsocks if running
pkill redsocks 2>/dev/null || true

# Stop tun2socks and cleanup tun1 interface
pkill tun2socks 2>/dev/null || true
ip rule del from "${HOTSPOT_GATEWAY%.*}.0/24" table 100 2>/dev/null || true
ip route del default table 100 2>/dev/null || true
ip tuntap del mode tun dev tun1 2>/dev/null || true

# Clean up iptables rules
iptables -t nat -D POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -o eth0 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -o wlan1 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -o tun0 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -o tun1 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$AP_INTERFACE" -p tcp -j REDIRECT --to-ports 9040 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$AP_INTERFACE" -p tcp -j REDIRECT --to-ports 12345 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$AP_INTERFACE" -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$AP_INTERFACE" -p tcp --syn -j REDIRECT --to-ports 9040 2>/dev/null || true

# Remove forwarding rules
iptables -D FORWARD -i "$AP_INTERFACE" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -o "$AP_INTERFACE" -j ACCEPT 2>/dev/null || true

# Bring down the AP interface
ip addr flush dev "$AP_INTERFACE" 2>/dev/null || true
ip link set "$AP_INTERFACE" down 2>/dev/null || true

# Reset to managed mode
iw dev "$AP_INTERFACE" set type managed 2>/dev/null || true

# Re-enable NetworkManager control if running
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    nmcli device set "$AP_INTERFACE" managed yes 2>/dev/null || true
fi

# Bring interface back up for normal WiFi
ip link set "$AP_INTERFACE" up 2>/dev/null || true

# Remove config files
rm -f /etc/hostapd/hostapd.conf
rm -f /etc/dnsmasq.d/hotspot.conf

# Clear state
rm -f /run/hotspot.state
rm -f /run/hotspot.ssid
rm -f /run/hotspot.vpn

log "Hotspot stopped successfully"

exit 0
