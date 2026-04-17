#!/bin/bash
# This script handles the remote side of the project.
# it sends reports, pulls quick snapshots, and watches another host,
# so the audit can work across machines with ssh tools.

# This first part checks the ssh tools and resolves report paths.
# it keeps the transfer functions smaller and safer,
# so path and dependency checks are done in one place first.
check_ssh_deps() {
    if ! command -v ssh >/dev/null 2>&1; then
        echo "[!] ssh is not installed"
        return 1
    fi

    if ! command -v scp >/dev/null 2>&1; then
        echo "[!] scp is not installed"
        return 1
    fi

    return 0
}
resolve_remote_report_file() {
    if type resolve_report_file >/dev/null 2>&1; then
        resolve_report_file "$1"
    elif [ -f "$1" ]; then
        echo "$1"
    fi
}
quote_remote_path() {
    echo "$1" | sed "s/'/'\\\\''/g"
}

# This section sends the chosen report to another machine.
# it creates the remote folder, copies the report, and also copies the hash,
# so the remote side receives both the file and its integrity check.
remote_send_report() {
    local file
    file=$(resolve_remote_report_file "$1") || {
        echo "[!] Invalid report file"
        return 1
    }

    local user=${2:-$REMOTE_USER}
    local host=${3:-$REMOTE_HOST}
    local dir=${4:-$REMOTE_REPORT_DIR}

    [ -z "$user" ] || [ -z "$host" ] || [ -z "$dir" ] && {
        echo "[!] Missing remote config"
        return 1
    }

    check_ssh_deps || return 1

    local hash="${file}.sha256"
    local qdir
    qdir=$(quote_remote_path "$dir")

    echo "[*] Sending → $user@$host:$dir"

    # this part will create directory
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        "$user@$host" "mkdir -p -- '$qdir'" || {
        echo "[!] Remote mkdir failed"
        return 1
    }

    # this part will send the main file
    scp -p -o ConnectTimeout=10 \
        "$file" "$user@$host:'$qdir/$(basename "$file")'" || {
        echo "[!] File transfer failed"
        return 1
    }

    # this part will send the hash if it exists
    if [ -f "$hash" ]; then
        scp -p -o ConnectTimeout=10 \
            "$hash" "$user@$host:'$qdir/$(basename "$hash")'" || {
            echo "[!] Hash transfer failed"
            return 1
        }
    fi

    echo "[+] Done"
}


# This part pulls a small live snapshot from the remote host.
# it only asks for the main operating and resource details,
# so the result stays useful without becoming too long.
remote_pull_audit() {
    local user=${1:-$REMOTE_USER}
    local host=${2:-$REMOTE_HOST}

    [ -z "$user" ] || [ -z "$host" ] && {
        echo "[!] Missing remote config"
        return 1
    }

    check_ssh_deps || return 1

    echo "[*] Pulling audit from $user@$host"
    echo

    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        "$user@$host" 'bash -s' <<'EOF'
echo "=== REMOTE MACHINE AUDIT ==="
echo "Hostname : $(hostname)"
echo "Date     : $(date '+%F %T')"
echo "OS       : $(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2);print $2;exit}' /etc/os-release 2>/dev/null || uname -s)"
echo "Kernel   : $(uname -r)"
echo "Uptime   : $(uptime -p 2>/dev/null || uptime)"
echo "IP       : $(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')"

echo
echo "=== RESOURCES ==="
echo "Load     : $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
free -h | awk 'NR==1 || /^Mem:/ || /^Swap:/'

echo
echo "Disk"
df -hT -x tmpfs -x devtmpfs -x squashfs -x efivarfs 2>/dev/null

echo
echo "Ports"
ss -tuln 2>/dev/null | head -15

echo
echo "Users"
who 2>/dev/null || echo "(none)"
EOF

    if ssh_exit=$?; [ $ssh_exit -ne 0 ]; then
        echo "[!] SSH failed"
        return 1
    fi

    echo
    echo "[+] Audit done"
}

# This helper guides the user through ssh key setup.
# it creates an ed25519 key when needed and copies the public part,
# so passwordless access is easier to enable from the project menu.

setup_ssh_keys() {
    local user=${1:-$REMOTE_USER}
    local host=${2:-$REMOTE_HOST}
    local key="$HOME/.ssh/id_ed25519"

    [ -z "$user" ] || [ -z "$host" ] && {
        echo "[!] Missing remote config"
        return 1
    }

    command -v ssh-copy-id >/dev/null || {
        echo "[!] ssh-copy-id not installed"
        return 1
    }

    # this part will generate key if missing
    if [ ! -f "$key" ]; then
        echo "[*] Generating SSH key..."
        ssh-keygen -t ed25519 -C "audit@$(hostname)" -f "$key" -N "" || return 1
    fi

    echo "[*] Installing key → $user@$host"

    if ssh-copy-id -i "$key.pub" "$user@$host"; then
        echo "[+] SSH auth ready (no password needed)"
    else
        echo "[!] Failed. Manual fallback:"
        echo "cat $key.pub"
        echo "# paste into ~/.ssh/authorized_keys on remote"
        return 1
    fi
}

# This last part keeps watching the remote host in a loop.
# it refreshes the most useful resource data every few seconds,
# so the user can follow the machine in near real time.

remote_watch() {
    local user=${1:-$REMOTE_USER}
    local host=${2:-$REMOTE_HOST}
    local interval=${3:-5}

    [ -z "$user" ] || [ -z "$host" ] && {
        echo "[!] Missing remote config"
        return 1
    }

    check_ssh_deps || return 1

    echo "[*] Watching $user@$host (every ${interval}s)"
    echo "Press Ctrl+C to stop"
    echo

    while :; do
        clear
        echo "=== $user@$host | $(date '+%F %T') ==="

        if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
            "$user@$host" 'bash -s' <<'EOF'
echo "CPU Load"
cut -d' ' -f1-3 /proc/loadavg

echo
echo "Memory"
free -h | awk 'NR==1 || /^Mem:/ || /^Swap:/'

echo
echo "Disk"
df -hT -x tmpfs -x devtmpfs -x squashfs -x efivarfs

echo
echo "Top Processes"
ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | head -6
EOF
        then
            echo
            echo "[!] Connection lost"
        fi

        sleep "$interval"
    done
}