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
# it keeps the event type, time, host, and message together,
# so later log review stays simple.
log_event() {
    local EVENT_TYPE=${1:-"INFO"}
    local MESSAGE=${2:-""}
    local TIMESTAMP
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[${TIMESTAMP}] [${EVENT_TYPE}] $(hostname) : ${MESSAGE}" >> "$LOG_FILE" 2>/dev/null
}

# This part deals with the log if it gets too big.
# instead of letting it grow forever, it moves the old one away
# and keeps the recent logging easier to manage.
rotate_log() {
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi

    local SIZE_MB
    SIZE_MB=$(du -m "$LOG_FILE" 2>/dev/null | cut -f1)

    if [ "${SIZE_MB:-0}" -ge "${MAX_LOG_SIZE_MB}" ]; then
        local ARCHIVE="${LOG_FILE}.$(date +%Y%m%d_%H%M%S).bak"
        mv "$LOG_FILE" "$ARCHIVE"
        echo "[*] Log rotated: $ARCHIVE"
        log_event "LOG_ROTATED" "Previous log archived to $ARCHIVE"
    fi
}

# This last helper shows the newest lines from the log.
# it gives the menu a simple way to read recent activity,
# so the user does not need to open the file manually.
show_log() {
    local LINES=${1:-50}
    if [ -f "$LOG_FILE" ]; then
        echo "=== Last $LINES log entries ==="
        tail -n "$LINES" "$LOG_FILE"
    else
        echo "[i] No log file found: $LOG_FILE"
    fi
}
