#!/bin/bash
# This script collects the hardware side of the audit.
# it gathers cpu, memory, storage, network, and board details,
# so the reports can show the machine layout in short and full forms.

# This first part keeps small network helpers together.
# it finds the main route information used in summaries,
# so later functions do not repeat the same commands.
primary_interface() {
    ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
}
primary_ipv4() {
    ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}'
}

default_gateway() {
    ip route 2>/dev/null | awk '/^default/ {print $3; exit}'
}


# This second part collects the detailed hardware sections.
# it prints each area in a readable block,
# so the full report stays organized instead of one long dump.
get_cpu() {
    echo "=== CPU ==="

    if command -v lscpu >/dev/null 2>&1; then
        lscpu | grep -E "Model name|Architecture|CPU\\(s\\)|Thread\\(s\\) per core|Core\\(s\\) per socket|Socket\\(s\\)|Virtualization"
    else
        echo "Model        : $(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo)"
        echo "CPU(s)       : $(nproc 2>/dev/null)"
        echo "Architecture : $(uname -m)"
    fi

    echo "Load Avg     : $(cut -d ' ' -f1-3 /proc/loadavg)"
}
get_gpu() {
    echo "=== GPU ==="
    if command -v lspci >/dev/null 2>&1; then
        lspci | grep -iE "vga|3d|display" | cut -d ":" -f3- | sed 's/^ */- /' || echo "No GPU detected"
    else
        echo "[!] lspci not available"
    fi
}
get_ram() {
    echo "=== MEMORY ==="
    free -h | awk 'NR==1 || /^Mem:/ || /^Swap:/'
}

get_disk() {
    echo "=== STORAGE ==="
    echo "-- Block Devices --"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | awk 'NR==1 || $3 != "loop"'
    echo ""
    echo "-- Mounted Filesystems --"
    df -hT -x tmpfs -x devtmpfs -x squashfs -x efivarfs 2>/dev/null
}
get_network() {
    echo "=== NETWORK ==="

    
    local PRIMARY_IFACE PRIMARY_IP GATEWAY
    PRIMARY_IFACE=$(primary_interface 2>/dev/null || echo "N/A")
    PRIMARY_IP=$(primary_ipv4 2>/dev/null || echo "N/A")
    GATEWAY=$(default_gateway 2>/dev/null || echo "N/A")

    echo "Primary Interface : $PRIMARY_IFACE"
    echo "Primary IPv4      : $PRIMARY_IP"
    echo "Default Gateway   : $GATEWAY"

    echo ""
    echo "-- Active Interfaces --"
    ip -o -4 addr show up scope global 2>/dev/null \
        | awk '{print $2 ":", $4}' || echo "N/A"

    echo ""
    echo "-- MAC Addresses --"

    for iface in /sys/class/net/*; do
        name=$(basename "$iface")
        mac=$(cat "$iface/address" 2>/dev/null)

        # skip invalid entries
        [ -z "$mac" ] && continue 

        printf "%-18s %s\n" "$name:" "$mac"
    done
}
get_motherboard() {
    echo "=== MOTHERBOARD / BIOS ==="

    echo "Vendor      : $(cat /sys/class/dmi/id/board_vendor 2>/dev/null || echo N/A)"
    echo "Product     : $(cat /sys/class/dmi/id/board_name 2>/dev/null || echo N/A)"
    echo "Version     : $(cat /sys/class/dmi/id/board_version 2>/dev/null || echo N/A)"

    echo ""
    echo "=== BIOS ==="
    echo "Vendor      : $(cat /sys/class/dmi/id/bios_vendor 2>/dev/null || echo N/A)"
    echo "Version     : $(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo N/A)"
    echo "Date        : $(cat /sys/class/dmi/id/bios_date 2>/dev/null || echo N/A)"
}

get_usb() {
    echo "=== USB DEVICES ==="
    if command -v lsusb >/dev/null 2>&1; then
        local USB_COUNT
        USB_COUNT=$(lsusb 2>/dev/null | wc -l)
        echo "Detected Devices     : ${USB_COUNT:-0}"
        echo ""
        lsusb 2>/dev/null | head -10
    else
        echo "[!] lsusb not available"
    fi
}


# This last part prepares the report entry points.
# it builds the short summary and the full hardware report,
# so report.sh can call one simple function for each mode.
hw_summary() {
    local MEMORY_TOTAL
    local MEMORY_USED
    local MEMORY_AVAILABLE
    local ROOT_USAGE
    local GPU_NAME
    local PRIMARY_IFACE
    local PRIMARY_IP_ADDR

    MEMORY_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
    MEMORY_USED=$(free -h | awk '/Mem:/ {print $3}')
    MEMORY_AVAILABLE=$(free -h | awk '/Mem:/ {print $7}')

    ROOT_USAGE=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')

    GPU_NAME=$(lspci 2>/dev/null | grep -i "vga\|display" | cut -d: -f3 | sed 's/^ *//' | head -1)

    PRIMARY_IFACE=$(primary_interface)
    PRIMARY_IP_ADDR=$(primary_ipv4)

    echo "=== HARDWARE SUMMARY ==="
    echo "CPU        : $(lscpu 2>/dev/null | awk -F: '/Model name/ {print $2; exit}' || echo N/A)"
    echo "Cores      : $(nproc 2>/dev/null || echo N/A)"
    echo "Load Avg   : $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo N/A)"
    echo "Memory     : ${MEMORY_USED:-N/A} used / ${MEMORY_TOTAL:-N/A} total / ${MEMORY_AVAILABLE:-N/A} available"
    echo "Root Disk  : ${ROOT_USAGE:-N/A}"
    echo "GPU        : ${GPU_NAME:-N/A}"
    echo "Network    : ${PRIMARY_IFACE:-N/A} ${PRIMARY_IP_ADDR:-N/A}"
}
hw_full() {
    get_cpu
    echo ""
    get_gpu
    echo ""
    get_ram
    echo ""
    get_disk
    echo ""
    get_network
    echo ""
    get_motherboard
    echo ""
    get_usb
}
