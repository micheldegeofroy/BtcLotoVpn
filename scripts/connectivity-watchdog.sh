#!/bin/bash
# connectivity-watchdog.sh - Auto-recover from network issues
# Run via cron every 5 minutes or systemd timer

LOG="/var/log/connectivity-watchdog.log"
TELEGRAM_CHECK="api.telegram.org"
MAX_FAILURES=3

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"
}

# Test basic connectivity
test_connectivity() {
    # Try to reach Telegram API (what the bot needs)
    if curl -s --max-time 10 "https://${TELEGRAM_CHECK}" >/dev/null 2>&1; then
        return 0
    fi

    # Try Google DNS
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Clean up stale VPN routes
cleanup_stale_routes() {
    log "Cleaning up stale VPN routes..."

    # Remove OpenVPN routes if OpenVPN is not running
    if ! pgrep -x openvpn >/dev/null; then
        if ip route | grep -q "via 10.8.0"; then
            log "Removing stale OpenVPN routes (OpenVPN not running)"
            ip route del 0.0.0.0/1 via 10.8.0.5 dev tun0 2>/dev/null
            ip route del 128.0.0.0/1 via 10.8.0.5 dev tun0 2>/dev/null
            ip link set tun0 down 2>/dev/null
            return 0
        fi
    fi

    # Check for any dead tun interfaces with routes
    for tun in tun0 tun1 tun2; do
        if ip route | grep -q "dev $tun" && ! ip link show "$tun" 2>/dev/null | grep -q "UP"; then
            log "Removing routes for down interface $tun"
            ip route flush dev "$tun" 2>/dev/null
        fi
    done

    return 0
}

# Restart bot if needed
restart_bot_if_needed() {
    if systemctl is-active --quiet btcloto; then
        # Check if bot is actually working (not in error loop)
        if journalctl -u btcloto --since "2 min ago" --no-pager 2>/dev/null | grep -q "Failed to get updates"; then
            log "Bot appears stuck, restarting..."
            systemctl restart btcloto
            return 0
        fi
    fi
    return 1
}

# Main logic
main() {
    if test_connectivity; then
        # All good, exit silently
        exit 0
    fi

    log "Connectivity check FAILED"

    # Try cleanup
    cleanup_stale_routes
    sleep 2

    # Test again
    if test_connectivity; then
        log "Connectivity RESTORED after route cleanup"
        restart_bot_if_needed
        exit 0
    fi

    # Still failing - try restarting network
    log "Still no connectivity, restarting networking..."
    systemctl restart networking 2>/dev/null || true
    sleep 5

    if test_connectivity; then
        log "Connectivity RESTORED after network restart"
        restart_bot_if_needed
        exit 0
    fi

    log "ERROR: Could not restore connectivity"
    exit 1
}

main
