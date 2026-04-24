#!/bin/bash
# This script is for the logging part of the project.
# it keeps track of stuff that happens while the audit is running,
# so later we can look back and see what was going on.

LOG_FILE="${LOG_DIR:-./logs}/sys_audit.log"
MAX_LOG_SIZE_MB=10

# This part sets up the log place and also lets the other modules
# save messages in one file so everything stays together.
init_logger() {
    mkdir -p "${LOG_DIR:-./logs}" 2>/dev/null
    rotate_log
}

# This helper writes one line in the common log format.
# it keeps all info in one place
# so later log review stays simple.
log_event() {
    local event_type=${1:-"INFO"}
    local message=${2:-""}
    local timestamp

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${event_type}] $(hostname) : ${message}" >> "$LOG_FILE" 2>/dev/null
}

# This part deals with the log if it gets too big.
# instead of letting it grow forever, it moves the old one away
# and keeps the recent logging easier to manage.
rotate_log() {
    local size_mb
    local archive

    [ -f "$LOG_FILE" ] || return

    size_mb=$(du -m "$LOG_FILE" 2>/dev/null | cut -f1)
    if [ "${size_mb:-0}" -ge "$MAX_LOG_SIZE_MB" ]; then
        archive="${LOG_FILE}.$(date +%Y%m%d_%H%M%S).bak"
        mv "$LOG_FILE" "$archive"
        echo "[*] Log rotated: $archive"
        log_event "LOG_ROTATED" "Previous log archived to $archive"
    fi
}

show_log() {
    local lines=${1:-50}

    if [ -f "$LOG_FILE" ]; then
        echo "=== Last $lines log entries ==="
        tail -n "$lines" "$LOG_FILE"
    else
        echo "[i] No log file found: $LOG_FILE"
    fi
}
