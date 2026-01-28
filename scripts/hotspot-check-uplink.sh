#!/bin/bash
# hotspot-check-uplink.sh - Verify internet uplink is available
# Part of BTCLOTO - Bitcoin Solo Miner
# Returns 0 if uplink is available, 1 otherwise

# Check for Ethernet connection (eth0)
check_eth0() {
    if ip link show eth0 &>/dev/null; then
        if ip addr show eth0 | grep -q "inet "; then
            # Test connectivity
            if ping -I eth0 -c 1 -W 2 8.8.8.8 &>/dev/null; then
                echo "eth0"
                return 0
            fi
        fi
    fi
    return 1
}

# Check for USB WiFi adapter (wlan1)
check_wlan1() {
    if ip link show wlan1 &>/dev/null; then
        if ip addr show wlan1 | grep -q "inet "; then
            # Test connectivity
            if ping -I wlan1 -c 1 -W 2 8.8.8.8 &>/dev/null; then
                echo "wlan1"
                return 0
            fi
        fi
    fi
    return 1
}

# Check for USB Ethernet adapter (common names)
check_usb_eth() {
    for iface in enx* usb0 eth1; do
        if ip link show "$iface" &>/dev/null 2>&1; then
            if ip addr show "$iface" | grep -q "inet "; then
                if ping -I "$iface" -c 1 -W 2 8.8.8.8 &>/dev/null; then
                    echo "$iface"
                    return 0
                fi
            fi
        fi
    done
    return 1
}

# Main check
main() {
    # Try each interface in order of preference
    if UPLINK=$(check_eth0); then
        echo "Uplink: $UPLINK (Ethernet)"
        exit 0
    fi

    if UPLINK=$(check_wlan1); then
        echo "Uplink: $UPLINK (USB WiFi)"
        exit 0
    fi

    if UPLINK=$(check_usb_eth); then
        echo "Uplink: $UPLINK (USB Ethernet)"
        exit 0
    fi

    echo "No uplink available"
    echo "Hotspot requires Ethernet or USB WiFi adapter for internet"
    exit 1
}

main
