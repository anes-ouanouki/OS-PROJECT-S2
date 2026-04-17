#!/bin/bash
# This script watches the main resource thresholds.
# it measures cpu, ram, and disk usage,
# so the project can warn the user before things get too high.

# This first part collects the raw usage values.
# it keeps each metric in a small helper,
# so the alert check stays easier to read.



get_cpu_usage() {
    local CPU1 IDLE1 CPU2 IDLE2
    CPU1=$(cat /proc/stat | grep '^cpu ' | awk '{print $2+$3+$4+$6+$7+$8}')
    IDLE1=$(cat /proc/stat | grep '^cpu ' | awk '{print $5}')
    sleep 1
    CPU2=$(cat /proc/stat | grep '^cpu ' | awk '{print $2+$3+$4+$6+$7+$8}')
    IDLE2=$(cat /proc/stat | grep '^cpu ' | awk '{print $5}')   
    local DIFF_CPU=$(( CPU2 - CPU1 ))
    local DIFF_IDLE=$(( IDLE2 - IDLE1 ))
    local TOTAL_DIFF=$(( DIFF_CPU + DIFF_IDLE ))
    if [ "$TOTAL_DIFF" -eq 0 ]; then
        echo "0"
    else
        local CPU_USAGE=$(( DIFF_CPU * 100 / TOTAL_DIFF ))
        echo "$CPU_USAGE"
    fi
}
get_ram_usage() {
    local TOTAL USED
    TOTAL=$(free | awk '/^Mem:/{print $2}')
    USED=$(free | awk '/^Mem:/{print $3}')
    echo $(( USED * 100 / TOTAL ))
}
get_disk_usage() {
    df / | awk 'NR==2{print int($5)}'
}


# This section compares the live values with configured limits.
# it prints the current numbers and triggers alerts when needed,
# so the user can see both the status and the reason for a warning.

check_alerts() {
    local ALERT_TRIGGERED=0

    echo "[*] Checking system thresholds..."

    local CPU_USAGE
    CPU_USAGE=$(get_cpu_usage)
    CPU_ALERT_THRESHOLD=${CPU_ALERT_THRESHOLD:-80}
    echo "    CPU Usage  : ${CPU_USAGE}% (threshold: ${CPU_ALERT_THRESHOLD}%)"
    if [ "$CPU_USAGE" -gt "$CPU_ALERT_THRESHOLD" ]; then
        echo "[!] ALERT: CPU usage is ${CPU_USAGE}% (above ${CPU_ALERT_THRESHOLD}%)"
        send_alert "CPU_HIGH" "CPU usage at ${CPU_USAGE}% on $(hostname)"
        log_event "ALERT_CPU" "CPU at ${CPU_USAGE}%"
        ALERT_TRIGGERED=1
    fi
    local RAM_USAGE
    RAM_USAGE=$(get_ram_usage)
    RAM_ALERT_THRESHOLD=${RAM_ALERT_THRESHOLD:-85}
    echo "    RAM Usage  : ${RAM_USAGE}% (threshold: ${RAM_ALERT_THRESHOLD}%)"
    if [ "$RAM_USAGE" -gt "$RAM_ALERT_THRESHOLD" ]; then
        echo "[!] ALERT: RAM usage is ${RAM_USAGE}% (above ${RAM_ALERT_THRESHOLD}%)"
        send_alert "RAM_HIGH" "RAM usage at ${RAM_USAGE}% on $(hostname)"
        log_event "ALERT_RAM" "RAM at ${RAM_USAGE}%"
        ALERT_TRIGGERED=1
    fi
    local DISK_USAGE
    DISK_USAGE=$(get_disk_usage)
    DISK_ALERT_THRESHOLD=${DISK_ALERT_THRESHOLD:-90}
    echo "    Disk Usage : ${DISK_USAGE}% (threshold: ${DISK_ALERT_THRESHOLD}%)"
    if [ "$DISK_USAGE" -gt "$DISK_ALERT_THRESHOLD" ]; then
        echo "[!] ALERT: Disk usage is ${DISK_USAGE}% (above ${DISK_ALERT_THRESHOLD}%)"
        send_alert "DISK_HIGH" "Disk usage at ${DISK_USAGE}% on $(hostname)"
        log_event "ALERT_DISK" "Disk at ${DISK_USAGE}%"
        ALERT_TRIGGERED=1
    fi
    if [ "$ALERT_TRIGGERED" -eq 0 ]; then
        echo "    All metrics are within thresholds."
    fi
}

# This last part sends the alert mail when email is configured.
# it keeps the message simple and readable,
# so the warning can be understood fast from the inbox.
send_alert() {
    local ALERT_TYPE=$1
    local MESSAGE=$2

    if [ -z "$RECIPIENT_EMAIL" ]; then
        echo "[!] No recipient email configured for alerts"
        return 1
    fi

    if ! command -v msmtp &>/dev/null; then
        echo "[!] msmtp not available, cannot send alert"
        return 1
    fi
    {
        echo "To: $RECIPIENT_EMAIL"
        echo "Subject: [sys_audit] ALERT: ${ALERT_TYPE} on $(hostname)"
        echo ""
        echo "SYSTEM ALERT"
        echo "============"
        echo "Host    : $(hostname)"
        echo "Date    : $(date)"
        echo "Alert   : $ALERT_TYPE"
        echo "Message : $MESSAGE"
    } | msmtp --account="$MSMTP_ACCOUNT" "$RECIPIENT_EMAIL" 2>/dev/null

    echo "[+] Alert email sent: $ALERT_TYPE"
}