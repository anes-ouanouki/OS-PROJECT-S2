#!/bin/bash
# This script watches the main resource thresholds.
# it measures cpu, ram, and disk usage,
# so the project can warn the user before things get too high.

# This first part collects the raw usage values.
# it keeps each metric in a small helper,
# so the alert check stays easier to read.
cpu_busy_time() {
    awk '/^cpu /{print $2+$3+$4+$6+$7+$8; exit}' /proc/stat
}

cpu_idle_time() {
    awk '/^cpu /{print $5; exit}' /proc/stat
}

get_cpu_usage() {
    local cpu1 idle1 cpu2 idle2 diff_cpu diff_idle total_diff

    cpu1=$(cpu_busy_time)
    idle1=$(cpu_idle_time)
    sleep 1
    cpu2=$(cpu_busy_time)
    idle2=$(cpu_idle_time)

    diff_cpu=$((cpu2 - cpu1))
    diff_idle=$((idle2 - idle1))
    total_diff=$((diff_cpu + diff_idle))

    if [ "$total_diff" -eq 0 ]; then
        echo "0"
    else
        echo $((diff_cpu * 100 / total_diff))
    fi
}

get_ram_usage() {
    local total used

    total=$(free | awk '/^Mem:/{print $2}')
    used=$(free | awk '/^Mem:/{print $3}')
    echo $((used * 100 / total))
}

get_disk_usage() {
    df / | awk 'NR==2 {print int($5)}'
}


# This section compares the live values with configured limits.
# it prints the current numbers and triggers alerts when needed,
# so the user can see both the status and the reason for a warning.

check_alerts() {
    local alert_triggered=0
    local cpu_usage
    local ram_usage
    local disk_usage

    echo "[*] Checking system thresholds..."

    cpu_usage=$(get_cpu_usage)
    CPU_ALERT_THRESHOLD=${CPU_ALERT_THRESHOLD:-80}
    echo "    CPU Usage  : ${cpu_usage}% (threshold: ${CPU_ALERT_THRESHOLD}%)"
    if [ "$cpu_usage" -gt "$CPU_ALERT_THRESHOLD" ]; then
        echo "[!] ALERT: CPU usage is ${cpu_usage}%"
        send_alert "CPU_HIGH" "CPU usage at ${cpu_usage}% on $(hostname)"
        log_event "ALERT_CPU" "CPU at ${cpu_usage}%"
        alert_triggered=1
    fi

    ram_usage=$(get_ram_usage)
    RAM_ALERT_THRESHOLD=${RAM_ALERT_THRESHOLD:-85}
    echo "    RAM Usage  : ${ram_usage}% (threshold: ${RAM_ALERT_THRESHOLD}%)"
    if [ "$ram_usage" -gt "$RAM_ALERT_THRESHOLD" ]; then
        echo "[!] ALERT: RAM usage is ${ram_usage}%"
        send_alert "RAM_HIGH" "RAM usage at ${ram_usage}% on $(hostname)"
        log_event "ALERT_RAM" "RAM at ${ram_usage}%"
        alert_triggered=1
    fi

    disk_usage=$(get_disk_usage)
    DISK_ALERT_THRESHOLD=${DISK_ALERT_THRESHOLD:-90}
    echo "    Disk Usage : ${disk_usage}% (threshold: ${DISK_ALERT_THRESHOLD}%)"
    if [ "$disk_usage" -gt "$DISK_ALERT_THRESHOLD" ]; then
        echo "[!] ALERT: Disk usage is ${disk_usage}%"
        send_alert "DISK_HIGH" "Disk usage at ${disk_usage}% on $(hostname)"
        log_event "ALERT_DISK" "Disk at ${disk_usage}%"
        alert_triggered=1
    fi

    if [ "$alert_triggered" -eq 0 ]; then
        echo "    All metrics are within thresholds."
    fi
}

# This last part sends the alert mail when email is configured.
# it keeps the message simple and readable,
# so the warning can be understood fast from the inbox.
send_alert() {
    local alert_type=$1
    local message=$2

    if [ -z "$RECIPIENT_EMAIL" ]; then
        echo "[!] No recipient email configured for alerts"
        return 1
    fi

    if ! command -v msmtp >/dev/null 2>&1; then
        echo "[!] msmtp not available, cannot send alert"
        return 1
    fi

    {
        echo "To: $RECIPIENT_EMAIL"
        echo "Subject: [sys_audit] ALERT: ${alert_type} on $(hostname)"
        echo
        echo "SYSTEM ALERT"
        echo "============"
        echo "Host    : $(hostname)"
        echo "Date    : $(date)"
        echo "Alert   : $alert_type"
        echo "Message : $message"
    } | msmtp --account="$MSMTP_ACCOUNT" "$RECIPIENT_EMAIL" >/dev/null 2>&1

    echo "[+] Alert email sent: $alert_type"
}
