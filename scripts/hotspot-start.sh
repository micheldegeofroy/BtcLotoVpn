#!/bin/bash
# hotspot-start.sh - Start WiFi hotspot with VPN routing
# Part of BTCLOTO - Bitcoin Solo Miner

set -e

# Load configuration
CONFIG_FILE="/etc/btcloto/hotspot.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Defaults
HOTSPOT_SSID="${HOTSPOT_SSID:-BTCLOTO-VPN}"
HOTSPOT_PASSWORD="${HOTSPOT_PASSWORD:-btclotovpn}"
HOTSPOT_CHANNEL="${HOTSPOT_CHANNEL:-6}"
HOTSPOT_GATEWAY="${HOTSPOT_GATEWAY:-192.168.50.1}"
HOTSPOT_DHCP_START="${HOTSPOT_DHCP_START:-192.168.50.10}"
HOTSPOT_DHCP_END="${HOTSPOT_DHCP_END:-192.168.50.100}"
HOTSPOT_VPN="${HOTSPOT_VPN:-none}"
AP_INTERFACE="${AP_INTERFACE:-wlan0}"

LOG_FILE="/var/log/hotspot.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Check for internet uplink
if ! /usr/local/bin/hotspot-check-uplink.sh; then
    log "ERROR: No internet uplink available"
    exit 1
fi

log "Starting WiFi hotspot..."

# Stop any existing services
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true

# Kill any existing processes
killall hostapd 2>/dev/null || true
killall dnsmasq 2>/dev/null || true

# Disable NetworkManager control of wlan0 (if NetworkManager is running)
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    nmcli device set "$AP_INTERFACE" managed no 2>/dev/null || true
fi

# Bring down the interface
ip link set "$AP_INTERFACE" down 2>/dev/null || true

# Wait for interface to go down
sleep 1

# Set interface to AP mode
iw dev "$AP_INTERFACE" set type __ap 2>/dev/null || true

# Bring up the interface
ip link set "$AP_INTERFACE" up

# Assign IP address to the AP interface
ip addr flush dev "$AP_INTERFACE"
ip addr add "$HOTSPOT_GATEWAY/24" dev "$AP_INTERFACE"

# Generate hostapd config
mkdir -p /etc/hostapd
cat > /etc/hostapd/hostapd.conf << EOF
interface=$AP_INTERFACE
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=$HOTSPOT_CHANNEL
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$HOTSPOT_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# Generate dnsmasq config for DHCP
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/hotspot.conf << EOF
interface=$AP_INTERFACE
bind-interfaces
dhcp-range=$HOTSPOT_DHCP_START,$HOTSPOT_DHCP_END,255.255.255.0,24h
dhcp-option=option:router,$HOTSPOT_GATEWAY
dhcp-option=option:dns-server,$HOTSPOT_GATEWAY
server=8.8.8.8
server=1.1.1.1
log-dhcp
log-facility=$LOG_FILE
EOF

# Start dnsmasq for DHCP
dnsmasq -C /etc/dnsmasq.d/hotspot.conf --pid-file=/run/dnsmasq-hotspot.pid

# Start hostapd
hostapd -B /etc/hostapd/hostapd.conf -P /run/hostapd.pid
sleep 2

# Check if hostapd started successfully
if ! pgrep -x hostapd > /dev/null; then
    log "ERROR: hostapd failed to start"
    exit 1
fi

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Clear existing iptables rules for hotspot
iptables -t nat -D POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -j MASQUERADE 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$AP_INTERFACE" -p tcp -j REDIRECT --to-ports 9040 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$AP_INTERFACE" -p tcp -j REDIRECT --to-ports 12345 2>/dev/null || true

# Determine uplink interface
UPLINK=""
if ip link show eth0 &>/dev/null && ip addr show eth0 | grep -q "inet "; then
    UPLINK="eth0"
elif ip link show wlan1 &>/dev/null && ip addr show wlan1 | grep -q "inet "; then
    UPLINK="wlan1"
fi

# Configure VPN routing
case "$HOTSPOT_VPN" in
    tor)
        log "Configuring Tor transparent proxy..."
        TORRC_CHANGED=false
        # Ensure Tor has TransPort and DNSPort configured
        if ! grep -q "TransPort 0.0.0.0:9040" /etc/tor/torrc 2>/dev/null; then
            echo -e "\n# Transparent proxy for hotspot\nTransPort 0.0.0.0:9040\nDNSPort 0.0.0.0:5353" >> /etc/tor/torrc
            TORRC_CHANGED=true
        fi
        # Disable Socks5Proxy if present (allows direct Tor connections)
        if grep -q "^Socks5Proxy" /etc/tor/torrc 2>/dev/null; then
            sed -i 's/^Socks5Proxy/#Socks5Proxy/' /etc/tor/torrc
            TORRC_CHANGED=true
        fi
        # Restart Tor if config changed
        if [ "$TORRC_CHANGED" = true ]; then
            systemctl restart tor@default 2>/dev/null || systemctl restart tor 2>/dev/null || true
            sleep 10
        fi
        # Check if Tor is running and start if not
        if ! systemctl is-active --quiet tor@default 2>/dev/null && ! systemctl is-active --quiet tor 2>/dev/null; then
            log "WARNING: Tor is not running. Starting Tor..."
            systemctl start tor@default 2>/dev/null || systemctl start tor 2>/dev/null || true
            sleep 10
        fi
        # Transparent proxy through Tor (port 9040 - TransPort)
        iptables -t nat -A PREROUTING -i "$AP_INTERFACE" -p tcp --syn -j REDIRECT --to-ports 9040
        # DNS through Tor (port 5353)
        iptables -t nat -A PREROUTING -i "$AP_INTERFACE" -p udp --dport 53 -j REDIRECT --to-ports 5353
        ;;
    hysteria)
        log "Configuring Hysteria2 proxy routing via tun2socks..."
        # Check if Hysteria is running
        if ! systemctl is-active --quiet hysteria 2>/dev/null; then
            log "WARNING: Hysteria is not running. Starting Hysteria..."
            systemctl start hysteria 2>/dev/null || true
            sleep 3
        fi
        # Kill any existing tun2socks
        killall tun2socks 2>/dev/null || true
        # Create tun1 interface for tun2socks
        ip tuntap del mode tun dev tun1 2>/dev/null || true
        ip tuntap add mode tun dev tun1
        ip addr add 10.0.0.1/24 dev tun1
        ip link set dev tun1 up
        # Disable rp_filter for tun1
        sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
        sysctl -w net.ipv4.conf.tun1.rp_filter=0 >/dev/null
        # Start tun2socks connecting to Hysteria SOCKS5
        nohup /usr/local/bin/tun2socks -device tun1 -proxy socks5://127.0.0.1:1080 >/dev/null 2>&1 &
        sleep 2
        # Configure policy routing for hotspot subnet
        ip rule del from "${HOTSPOT_GATEWAY%.*}.0/24" table 100 2>/dev/null || true
        ip rule add from "${HOTSPOT_GATEWAY%.*}.0/24" table 100
        ip route del default table 100 2>/dev/null || true
        ip route add default dev tun1 table 100
        # Add local routes to table 100 so DNS stays local
        ip route add "${HOTSPOT_GATEWAY%.*}.0/24" dev "$AP_INTERFACE" table 100 2>/dev/null || true
        ip route add 192.168.1.0/24 dev eth0 table 100 2>/dev/null || true
        # Add fwmark routing
        ip rule del fwmark 100 table 100 2>/dev/null || true
        ip rule add fwmark 100 table 100
        # Mark packets from hotspot interface (except DNS)
        iptables -t mangle -A PREROUTING -i "$AP_INTERFACE" -p udp --dport 53 -j ACCEPT
        iptables -t mangle -A PREROUTING -i "$AP_INTERFACE" -p tcp --dport 53 -j ACCEPT
        iptables -t mangle -A PREROUTING -i "$AP_INTERFACE" -j MARK --set-mark 100
        # Add masquerade for tun1
        iptables -t nat -A POSTROUTING -o tun1 -j MASQUERADE
        ;;
    outline)
        log "Configuring Outline proxy routing via tun2socks..."
        if ! systemctl is-active --quiet outline 2>/dev/null; then
            systemctl start outline 2>/dev/null || true
            sleep 3
        fi
        # Kill any existing redsocks (doesn't work well with Shadowsocks)
        killall redsocks 2>/dev/null || true
        # Kill any existing tun2socks
        killall tun2socks 2>/dev/null || true
        # Create tun1 interface for tun2socks
        ip tuntap del mode tun dev tun1 2>/dev/null || true
        ip tuntap add mode tun dev tun1
        ip addr add 10.0.0.1/24 dev tun1
        ip link set dev tun1 up
        # Start tun2socks connecting to Outline SOCKS5
        nohup /usr/local/bin/tun2socks -device tun1 -proxy socks5://127.0.0.1:1081 >/dev/null 2>&1 &
        sleep 2
        # Configure policy routing for hotspot subnet
        ip rule del from "${HOTSPOT_GATEWAY%.*}.0/24" table 100 2>/dev/null || true
        ip rule add from "${HOTSPOT_GATEWAY%.*}.0/24" table 100
        ip route del default table 100 2>/dev/null || true
        ip route add default dev tun1 table 100
        # Add local routes to table 100 so DNS stays local
        ip route add "${HOTSPOT_GATEWAY%.*}.0/24" dev "$AP_INTERFACE" table 100 2>/dev/null || true
        ip route add 192.168.1.0/24 dev eth0 table 100 2>/dev/null || true
        # Add masquerade for tun1
        iptables -t nat -A POSTROUTING -o tun1 -j MASQUERADE
        ;;
    xray)
        log "Configuring Xray proxy routing via tun2socks..."
        if ! systemctl is-active --quiet xray 2>/dev/null; then
            log "WARNING: Xray is not running. Starting Xray..."
            systemctl start xray 2>/dev/null || true
            sleep 3
        fi
        # Kill any existing tun2socks
        killall tun2socks 2>/dev/null || true
        # Create tun1 interface for tun2socks
        ip tuntap del mode tun dev tun1 2>/dev/null || true
        ip tuntap add mode tun dev tun1
        ip addr add 10.0.0.1/24 dev tun1
        ip link set dev tun1 up
        # Disable rp_filter for tun1
        sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
        sysctl -w net.ipv4.conf.tun1.rp_filter=0 >/dev/null
        # Start tun2socks connecting to Xray SOCKS5 (port 1082)
        nohup /usr/local/bin/tun2socks -device tun1 -proxy socks5://127.0.0.1:1082 >/dev/null 2>&1 &
        sleep 2
        # Configure policy routing for hotspot subnet
        ip rule del from "${HOTSPOT_GATEWAY%.*}.0/24" table 100 2>/dev/null || true
        ip rule add from "${HOTSPOT_GATEWAY%.*}.0/24" table 100
        ip route del default table 100 2>/dev/null || true
        ip route add default dev tun1 table 100
        # Add local routes to table 100 so DNS stays local
        ip route add "${HOTSPOT_GATEWAY%.*}.0/24" dev "$AP_INTERFACE" table 100 2>/dev/null || true
        ip route add 192.168.1.0/24 dev eth0 table 100 2>/dev/null || true
        # Add fwmark routing
        ip rule del fwmark 100 table 100 2>/dev/null || true
        ip rule add fwmark 100 table 100
        # Mark packets from hotspot interface (except DNS)
        iptables -t mangle -A PREROUTING -i "$AP_INTERFACE" -p udp --dport 53 -j ACCEPT
        iptables -t mangle -A PREROUTING -i "$AP_INTERFACE" -p tcp --dport 53 -j ACCEPT
        iptables -t mangle -A PREROUTING -i "$AP_INTERFACE" -j MARK --set-mark 100
        # Add masquerade for tun1
        iptables -t nat -A POSTROUTING -o tun1 -j MASQUERADE
        ;;
    openvpn)
        log "Configuring OpenVPN routing..."
        # Start OpenVPN if not running
        if ! pgrep -x openvpn > /dev/null; then
            log "Starting OpenVPN..."
            systemctl start openvpn-client@client 2>/dev/null || systemctl start openvpn@client 2>/dev/null || true
            sleep 5
        fi
        # NAT through tun0 interface
        if ip link show tun0 &>/dev/null; then
            # Disable rp_filter for tun0
            sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
            sysctl -w net.ipv4.conf.tun0.rp_filter=0 >/dev/null
            iptables -t nat -A POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -o tun0 -j MASQUERADE
            # Add FORWARD rules for tun0
            iptables -A FORWARD -i "$AP_INTERFACE" -o tun0 -j ACCEPT
            iptables -A FORWARD -i tun0 -o "$AP_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
        else
            log "WARNING: tun0 interface not found, falling back to direct NAT"
            iptables -t nat -A POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -o "$UPLINK" -j MASQUERADE
        fi
        ;;
    wireguard)
        log "Configuring WireGuard routing..."
        # Start WireGuard if not running
        if ! ip link show wg0 &>/dev/null; then
            log "Starting WireGuard..."
            wg-quick up wg0 2>/dev/null || systemctl start wg-quick@wg0 2>/dev/null || true
            sleep 3
        fi
        # NAT through wg0 interface
        if ip link show wg0 &>/dev/null; then
            sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
            sysctl -w net.ipv4.conf.wg0.rp_filter=0 >/dev/null
            iptables -t nat -A POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -o wg0 -j MASQUERADE
            iptables -A FORWARD -i "$AP_INTERFACE" -o wg0 -j ACCEPT
            iptables -A FORWARD -i wg0 -o "$AP_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
        else
            log "WARNING: wg0 interface not found, falling back to direct NAT"
            iptables -t nat -A POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -o "$UPLINK" -j MASQUERADE
        fi
        ;;
    none|*)
        log "Configuring direct NAT (no VPN)..."
        # Direct NAT through uplink interface
        if [ -n "$UPLINK" ]; then
            iptables -t nat -A POSTROUTING -s "${HOTSPOT_GATEWAY%.*}.0/24" -o "$UPLINK" -j MASQUERADE
        else
            log "WARNING: No uplink interface found"
        fi
        ;;
esac

# Allow forwarding between interfaces
iptables -A FORWARD -i "$AP_INTERFACE" -j ACCEPT
iptables -A FORWARD -o "$AP_INTERFACE" -j ACCEPT

# Save state
echo "RUNNING" > /run/hotspot.state
echo "$HOTSPOT_SSID" > /run/hotspot.ssid
echo "$HOTSPOT_VPN" > /run/hotspot.vpn

log "Hotspot started successfully"
log "SSID: $HOTSPOT_SSID"
log "Gateway: $HOTSPOT_GATEWAY"
log "VPN: $HOTSPOT_VPN"

exit 0
