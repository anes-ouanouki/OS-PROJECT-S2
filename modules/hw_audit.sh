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
    local primary_iface primary_ip gateway
    local iface
    local name
    local mac

    echo "=== NETWORK ==="

    primary_iface=$(primary_interface 2>/dev/null || echo "N/A")
    primary_ip=$(primary_ipv4 2>/dev/null || echo "N/A")
    gateway=$(default_gateway 2>/dev/null || echo "N/A")

    echo "Primary Interface : $primary_iface"
    echo "Primary IPv4      : $primary_ip"
    echo "Default Gateway   : $gateway"
    echo
    echo "-- Active Interfaces --"
    ip -o -4 addr show up scope global 2>/dev/null | awk '{print $2 ":", $4}' || echo "N/A"
    echo
    echo "-- MAC Addresses --"

    for iface in /sys/class/net/*; do
        name=$(basename "$iface")
        mac=$(cat "$iface/address" 2>/dev/null)
        [ -n "$mac" ] || continue
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
    local usb_count

    echo "=== USB DEVICES ==="
    if command -v lsusb >/dev/null 2>&1; then
        usb_count=$(lsusb 2>/dev/null | wc -l)
        echo "Detected Devices     : ${usb_count:-0}"
        echo
        lsusb 2>/dev/null | head -10
    else
        echo "[!] lsusb not available"
    fi
}


# This last part prepares the report entry points.
# it builds the short summary and the full hardware report,
# so report.sh can call one simple function for each mode.
hw_summary() {
    local memory_total
    local memory_used
    local memory_available
    local root_usage
    local gpu_name
    local primary_iface
    local primary_ip_addr

    memory_total=$(free -h | awk '/Mem:/ {print $2}')
    memory_used=$(free -h | awk '/Mem:/ {print $3}')
    memory_available=$(free -h | awk '/Mem:/ {print $7}')
    root_usage=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')
    gpu_name=$(lspci 2>/dev/null | grep -iE "vga|display" | cut -d: -f3 | sed 's/^ *//' | head -1)
    primary_iface=$(primary_interface)
    primary_ip_addr=$(primary_ipv4)

    echo "=== HARDWARE SUMMARY ==="
    echo "CPU        : $(lscpu 2>/dev/null | awk -F: '/Model name/ {print $2; exit}' || echo N/A)"
    echo "Cores      : $(nproc 2>/dev/null || echo N/A)"
    echo "Load Avg   : $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo N/A)"
    echo "Memory     : ${memory_used:-N/A} used / ${memory_total:-N/A} total / ${memory_available:-N/A} available"
    echo "Root Disk  : ${root_usage:-N/A}"
    echo "GPU        : ${gpu_name:-N/A}"
    echo "Network    : ${primary_iface:-N/A} ${primary_ip_addr:-N/A}"
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
