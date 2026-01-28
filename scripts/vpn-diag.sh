#!/bin/bash
# vpn-diag.sh - VPN connectivity diagnostics
# Usage: vpn-diag.sh [target] or vpn-diag.sh --all

set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default test target
TARGET="${1:-ifconfig.co}"

ok() { echo -e "${GREEN}OK${NC} $1"; }
fail() { echo -e "${RED}FAIL${NC} $1"; }
warn() { echo -e "${YELLOW}WARN${NC} $1"; }

# Get country from IP
get_country() {
    local ip="$1"
    curl -s --max-time 3 "http://ip-api.com/line/${ip}?fields=country,countryCode" 2>/dev/null | tr '\n' ' '
}

# Test a single connection
test_connection() {
    local name="$1"
    local proxy="$2"  # empty for direct, or "socks5://127.0.0.1:PORT"

    echo "=== $name ==="

    local curl_opts="--max-time 10 -s"
    [ -n "$proxy" ] && curl_opts="$curl_opts -x $proxy"

    # 1. Get IP
    local ip=$(curl $curl_opts https://ifconfig.co 2>/dev/null)
    if [ -z "$ip" ]; then
        fail "Cannot connect"
        echo
        return 1
    fi

    # 2. Get country
    local country=$(get_country "$ip")
    ok "IP: $ip ($country)"

    # 3. Timing breakdown
    local timing=$(curl $curl_opts -w 'DNS:%{time_namelookup} TCP:%{time_connect} TLS:%{time_appconnect} Total:%{time_total}' -o /dev/null https://ifconfig.co 2>/dev/null)
    echo "   $timing"

    # 4. Ping test (only for direct)
    if [ -z "$proxy" ]; then
        if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
            ok "Ping: working"
        else
            warn "Ping: blocked (normal for Tor)"
        fi
    fi

    echo
    return 0
}

# Test VPN proxy availability
test_proxy() {
    local name="$1"
    local port="$2"

    if ss -tlnp 2>/dev/null | grep -q ":$port"; then
        if curl -x socks5://127.0.0.1:$port -s --max-time 5 https://ifconfig.co &>/dev/null; then
            ok "$name (port $port): working"
            return 0
        else
            warn "$name (port $port): listening but not connecting"
            return 1
        fi
    else
        fail "$name (port $port): not running"
        return 1
    fi
}

# Quick status check
quick_check() {
    echo "========================================"
    echo "   VPN DIAGNOSTIC - $(date '+%Y-%m-%d %H:%M')"
    echo "========================================"
    echo

    # Current hotspot VPN
    local current_vpn=$(cat /run/hotspot.vpn 2>/dev/null || echo "none")
    echo "Hotspot VPN mode: $current_vpn"
    echo

    # Test direct connection
    echo "--- Direct Connection ---"
    local direct_ip=$(curl -s --max-time 5 https://ifconfig.co 2>/dev/null)
    if [ -n "$direct_ip" ]; then
        local country=$(get_country "$direct_ip")
        ok "Direct: $direct_ip ($country)"
    else
        fail "Direct: no connection"
    fi

    # DNS test
    if nslookup google.com &>/dev/null; then
        ok "DNS: working"
    else
        fail "DNS: not resolving"
    fi

    # Ping test
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        ok "Ping: working"
    else
        warn "Ping: blocked"
    fi

    echo
    echo "--- VPN Proxies ---"
    test_proxy "Hysteria" 1080
    test_proxy "Outline" 1081
    test_proxy "Xray" 1082
    test_proxy "Tor" 9050

    echo
    echo "--- Services ---"
    for svc in hysteria-client outline xray tor@default openvpn@client; do
        if systemctl is-active --quiet $svc 2>/dev/null; then
            ok "$svc: running"
        else
            echo "   $svc: stopped"
        fi
    done

    # tun interfaces
    echo
    echo "--- TUN Interfaces ---"
    ip -br addr show type tun 2>/dev/null || echo "   No TUN interfaces"

    # tun2socks
    if pgrep -a tun2socks &>/dev/null; then
        ok "tun2socks: $(pgrep -a tun2socks | awk '{print $NF}')"
    else
        echo "   tun2socks: not running"
    fi
}

# Full test of all VPNs
full_test() {
    quick_check

    echo
    echo "========================================"
    echo "   FULL VPN TESTS"
    echo "========================================"
    echo

    test_connection "Direct (no VPN)" ""

    # Test each available proxy
    ss -tlnp 2>/dev/null | grep -q ":1080" && test_connection "Hysteria (QUIC)" "socks5://127.0.0.1:1080"
    ss -tlnp 2>/dev/null | grep -q ":1081" && test_connection "Outline (Shadowsocks)" "socks5://127.0.0.1:1081"
    ss -tlnp 2>/dev/null | grep -q ":1082" && test_connection "Xray (VLESS)" "socks5://127.0.0.1:1082"
    ss -tlnp 2>/dev/null | grep -q ":9050" && test_connection "Tor" "socks5://127.0.0.1:9050"

    # Test tun1 if exists
    if ip link show tun1 &>/dev/null; then
        echo "=== Hotspot routing (tun1) ==="
        local tun_ip=$(curl -s --max-time 10 --interface tun1 https://ifconfig.co 2>/dev/null)
        if [ -n "$tun_ip" ]; then
            local country=$(get_country "$tun_ip")
            ok "tun1: $tun_ip ($country)"
        else
            fail "tun1: not routing"
        fi
        echo
    fi
}

# Simulate hotspot client experience
hotspot_test() {
    echo "========================================"
    echo "   HOTSPOT CLIENT TEST"
    echo "========================================"
    echo

    local vpn_mode=$(cat /run/hotspot.vpn 2>/dev/null || echo "unknown")
    local gateway=$(grep HOTSPOT_GATEWAY /etc/btcloto/hotspot.conf 2>/dev/null | cut -d= -f2 || echo "192.168.50.1")

    echo "VPN Mode: $vpn_mode"
    echo "Gateway: $gateway"
    echo

    # Check hotspot is running
    echo -n "1. Hotspot running: "
    if [ -f /run/hostapd.pid ] && pgrep -F /run/hostapd.pid &>/dev/null; then
        ok "hostapd active"
    else
        fail "hostapd not running"
        return 1
    fi

    # Check DHCP
    echo -n "2. DHCP server: "
    if pgrep -x dnsmasq &>/dev/null; then
        ok "dnsmasq active"
    else
        fail "dnsmasq not running"
    fi

    # Check connected clients
    echo -n "3. Connected clients: "
    local clients=$(cat /var/lib/misc/dnsmasq.leases 2>/dev/null | wc -l)
    echo "$clients device(s)"

    # DNS resolution (what clients use - via gateway IP)
    echo -n "4. DNS resolution: "
    local gw_ip=$(echo "$gateway" | tr -d '"')
    if dig +short +timeout=3 @${gw_ip} google.com 2>/dev/null | grep -q .; then
        ok "working (via $gw_ip)"
    elif nslookup google.com ${gw_ip} 2>/dev/null | grep -q Address; then
        ok "working (via $gw_ip)"
    elif curl -s --max-time 5 https://google.com &>/dev/null; then
        ok "working (curl test)"
    else
        fail "not resolving"
    fi

    # Test based on VPN mode
    echo -n "5. Client routing: "
    case "$vpn_mode" in
        tor)
            # Tor uses transparent proxy
            if ss -tlnp | grep -q ":9040"; then
                ok "TransPort 9040 listening"
            else
                fail "TransPort not listening"
            fi
            ;;
        hysteria|outline|xray)
            # These use tun2socks
            if ip link show tun1 &>/dev/null; then
                local tun_ip=$(curl -s --max-time 10 --interface tun1 https://ifconfig.co 2>/dev/null)
                if [ -n "$tun_ip" ]; then
                    local country=$(get_country "$tun_ip")
                    ok "tun1 -> $tun_ip ($country)"
                else
                    fail "tun1 not routing traffic"
                fi
            else
                fail "tun1 interface missing"
            fi
            ;;
        openvpn)
            if ip link show tun0 &>/dev/null; then
                ok "tun0 interface up"
            else
                fail "tun0 interface missing"
            fi
            ;;
        none|*)
            ok "direct NAT"
            ;;
    esac

    # Test actual website access (simulates client)
    echo -n "6. Website access: "
    case "$vpn_mode" in
        tor)
            # Can't easily test transparent proxy from Pi
            warn "manual test required (connect phone)"
            ;;
        hysteria|outline|xray)
            if curl -s --max-time 10 --interface tun1 -o /dev/null -w '%{http_code}' https://google.com 2>/dev/null | grep -q "200\|301\|302"; then
                ok "HTTPS working"
            else
                fail "HTTPS not working"
            fi
            ;;
        *)
            if curl -s --max-time 10 -o /dev/null -w '%{http_code}' https://google.com 2>/dev/null | grep -q "200\|301\|302"; then
                ok "HTTPS working"
            else
                fail "HTTPS not working"
            fi
            ;;
    esac

    # Ping test (won't work for Tor)
    echo -n "7. Ping (8.8.8.8): "
    case "$vpn_mode" in
        tor)
            warn "N/A (Tor = TCP only)"
            ;;
        hysteria|outline|xray)
            if ping -c 1 -W 3 -I tun1 8.8.8.8 &>/dev/null; then
                ok "working"
            else
                warn "blocked (some VPNs don't pass ICMP)"
            fi
            ;;
        *)
            if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
                ok "working"
            else
                fail "not working"
            fi
            ;;
    esac

    echo
    echo "--- Summary ---"
    local exit_ip=""
    case "$vpn_mode" in
        hysteria|outline|xray)
            exit_ip=$(curl -s --max-time 10 --interface tun1 https://ifconfig.co 2>/dev/null)
            ;;
        *)
            exit_ip=$(curl -s --max-time 10 https://ifconfig.co 2>/dev/null)
            ;;
    esac

    if [ -n "$exit_ip" ]; then
        local country=$(get_country "$exit_ip")
        echo "Hotspot clients will see: $exit_ip ($country)"
    else
        echo "Hotspot clients: NO INTERNET"
    fi
}

# TLS diagnostics for a specific host
tls_diag() {
    local host="$1"
    local port="${2:-443}"

    echo "=== TLS Diagnostics: $host:$port ==="

    # TCP test
    echo -n "TCP connect: "
    if timeout 5 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        ok ""
    else
        fail "(port closed or filtered)"
        return 1
    fi

    # TLS test
    echo -n "TLS handshake: "
    local tls_result=$(timeout 5 openssl s_client -connect "$host:$port" </dev/null 2>&1)
    if echo "$tls_result" | grep -q "CONNECTED"; then
        ok ""
        echo "$tls_result" | grep -E "Protocol|Cipher|Verify" | head -3 | sed 's/^/   /'
    else
        fail ""
        echo "$tls_result" | grep -i error | head -3 | sed 's/^/   /'
    fi

    # HTTP test
    echo -n "HTTPS request: "
    local http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://$host:$port" 2>/dev/null)
    if [ "$http_code" -gt 0 ] 2>/dev/null; then
        ok "HTTP $http_code"
    else
        fail "timeout or blocked"
    fi
}

# Main
case "${1:-}" in
    --all|-a)
        full_test
        ;;
    --hotspot|-h)
        hotspot_test
        ;;
    --tls)
        shift
        tls_diag "${1:-YOUR_SERVER_IP}" "${2:-443}"
        ;;
    --help)
        echo "Usage: vpn-diag [option]"
        echo
        echo "Options:"
        echo "  (none)       Quick status check"
        echo "  --all        Full test of all VPNs"
        echo "  --hotspot    Test from hotspot client perspective"
        echo "  --tls HOST [PORT]  TLS diagnostics for specific host"
        echo "  --help       Show this help"
        ;;
    *)
        quick_check
        ;;
esac
