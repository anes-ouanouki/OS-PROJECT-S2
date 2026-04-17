#!/bin/bash
# This script collects the software side of the audit.
# it gathers os, packages, users, services, and active ports,
# so the reports can describe how the system is running.

# This first part keeps the repeated lookup helpers in one place.
# it answers the common questions like os name and package count,
# so the report sections can stay shorter and easier to follow.
os_name() {
    local NAME

    NAME=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2; exit}' /etc/os-release 2>/dev/null)
    printf '%s\n' "${NAME:-$(uname -s)}"
}

package_manager_name() {
    if command -v dpkg >/dev/null 2>&1; then
        echo "dpkg"
    elif command -v rpm >/dev/null 2>&1; then
        echo "rpm"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo "unknown"
    fi
}
installed_package_count() {
    if command -v dpkg >/dev/null 2>&1; then
        dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l

    elif command -v rpm >/dev/null 2>&1; then
        rpm -qa 2>/dev/null | wc -l

    elif command -v pacman >/dev/null 2>&1; then
        pacman -Q 2>/dev/null | wc -l

    else
        echo "N/A"
    fi
}

running_service_count() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | wc -l
    else
        echo "N/A"
    fi
}

# This second part prints the full software sections.
# it breaks the audit into smaller readable blocks,
# so the full report stays organized and easier to scan.
get_os() {
    echo "=== OPERATING SYSTEM ==="
    echo "OS Name             : $(os_name || uname -s)"
    echo "Kernel              : $(uname -r)"
    echo "Architecture        : $(uname -m)"
    echo "Hostname            : $(hostname)"
    echo "Uptime              : $(uptime -p 2>/dev/null || uptime)"
    echo "Timezone            : $(timedatectl 2>/dev/null | awk -F': ' '/Time zone/{print $2; exit}' || cat /etc/timezone 2>/dev/null || echo N/A)"
    echo "Package Manager     : $(package_manager_name)"
    echo "Installed Packages  : $(installed_package_count)"
}


get_packages() {
    local PKG_MANAGER
    PKG_MANAGER=$(package_manager_name)

    echo "=== PACKAGE OVERVIEW ==="
    echo "Package Manager     : $PKG_MANAGER"
    echo "Installed Packages  : $(installed_package_count)"
    echo ""
    echo "-- Key Tools Snapshot --"

    case "$PKG_MANAGER" in
        dpkg)
            for PKG in openssh-client openssh-server curl git python3 msmtp ufw apache2 nginx docker.io; do
                dpkg -s "$PKG" >/dev/null 2>&1 && printf "%-18s installed\n" "$PKG"
            done
            ;;
        rpm)
            for PKG in openssh curl git python3 msmtp firewalld httpd nginx docker; do
                rpm -q "$PKG" >/dev/null 2>&1 && printf "%-18s installed\n" "$PKG"
            done
            ;;
        pacman)
            for PKG in openssh curl git python msmtp ufw apache nginx docker; do
                pacman -Q "$PKG" >/dev/null 2>&1 && printf "%-18s installed\n" "$PKG"
            done
            ;;
        *)
            echo "[i] No package snapshot available"
            ;;
    esac
}

get_users() {
    echo "=== USER ACTIVITY ==="

    echo "-- Logged-in Sessions --"
    who 2>/dev/null || echo "(none)"

    echo
    echo "-- Recent Logins --"
    last -n 5 2>/dev/null | sed '/wtmp begins/d'

}

get_services() {
    echo "=== RUNNING SERVICES ==="
    if command -v systemctl >/dev/null 2>&1; then
        echo "Total Running        : $(running_service_count)"
        echo ""
        systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | \
            awk 'NR<=15 {printf "%-40s %s\n", $1, $4}'
    elif command -v service >/dev/null 2>&1; then
        service --status-all 2>/dev/null | grep "+" | head -15
    else
        echo "[!] systemctl/service not available"
    fi
}

get_processes() {
    echo "=== TOP PROCESSES ==="
    ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | awk 'NR==1 || NR<=11'
}

get_ports() {
    echo "=== LISTENING PORTS ==="
    ss -tuln 2>/dev/null | awk 'NR==1 || /LISTEN|UNCONN/' | head -15 || echo "ss not available"
}

get_firewall() {
    echo "=== FIREWALL STATUS ==="
    if command -v ufw >/dev/null 2>&1; then
        ufw status 2>/dev/null || echo "[!] ufw requires root"
    elif command -v iptables >/dev/null 2>&1; then
        iptables -S 2>/dev/null | awk '$1 == "-P" {printf "%-12s %s\n", $2 ":", $3}' || echo "[!] iptables requires root"
    else
        echo "[!] No firewall tool detected"
    fi
}

get_cron() {
    echo "=== SCHEDULED TASKS ==="
    echo "-- Current User Crontab --"
    crontab -l 2>/dev/null || echo "(none)"
    echo ""
    echo "-- System Cron Directories --"
    for CRON_DIR in /etc/cron.d /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
        if [ -d "$CRON_DIR" ]; then
            printf "%-18s %s entries\n" "$(basename "$CRON_DIR"):" "$(find "$CRON_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)"
        fi
    done
}

# This last part prepares the summary and full entry points.
# it gives report.sh one short function for each output style,
# so the report builder does not need to know the internal details.
sw_summary() {
    echo "=== SOFTWARE SUMMARY ==="
    echo "OS          : $(os_name || uname -s)"
    echo "Kernel      : $(uname -r)"
    echo "Uptime      : $(uptime -p 2>/dev/null || uptime)"
    echo "Packages    : $(installed_package_count) installed via $(package_manager_name)"
    echo "Sessions    : $(who 2>/dev/null | wc -l) active"
    echo "Services    : $(running_service_count) running"
    echo "Top Ports   :"
    ss -tuln 2>/dev/null | awk 'NR>1 && /LISTEN|UNCONN/ {print "  - " $1 " " $5}' | head -5
}

sw_full() {
    get_os
    echo ""
    get_packages
    echo ""
    get_users
    echo ""
    get_services
    echo ""
    get_processes
    echo ""
    get_ports
    echo ""
    get_firewall
    echo ""
    get_cron
}
