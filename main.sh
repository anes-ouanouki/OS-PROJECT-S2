#!/bin/bash
# This is the main file of the project.
# it loads the config and all modules first, then it lets the user
# run the audit from the menu or from command line options.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# This first part is the setup side.
# it finds where the project is, loads the config file,
# and also brings in all the module files the script needs.
if [ -f "$SCRIPT_DIR/config.cfg" ]; then
    source "$SCRIPT_DIR/config.cfg"
else
    echo "[!] config.cfg not found, using defaults"
    REPORT_DIR="$SCRIPT_DIR/reports"
    LOG_DIR="$SCRIPT_DIR/logs"
    RECIPIENT_EMAIL=""
    MSMTP_ACCOUNT="gmail"
    REMOTE_USER=""
    REMOTE_HOST=""
    REMOTE_REPORT_DIR=""
    CPU_ALERT_THRESHOLD=80
    DISK_ALERT_THRESHOLD=90
    RAM_ALERT_THRESHOLD=85
    MAX_PROCESS_DISPLAY=20
fi

# This helper makes config paths safe to use from anywhere.
# it turns relative paths into project paths,
# so menu actions and cron jobs still find the right files.
project_path() {
    local PATH_VALUE=$1

    if [ -z "$PATH_VALUE" ]; then
        return 1
    fi

    case "$PATH_VALUE" in
        /*) printf '%s\n' "$PATH_VALUE" ;;
        ./*) printf '%s\n' "$SCRIPT_DIR/${PATH_VALUE#./}" ;;
        *) printf '%s\n' "$SCRIPT_DIR/$PATH_VALUE" ;;
    esac
}

# This next part normalizes the main folders and loads every module.
# it keeps the shared paths absolute inside the script,
# so reports, logs, email, and remote actions use the same locations.
REPORT_DIR=$(project_path "${REPORT_DIR:-reports}")
LOG_DIR=$(project_path "${LOG_DIR:-logs}")

for MODULE in hw_audit sw_audit report email remote alerts logger; do
    MODULE_PATH="$SCRIPT_DIR/modules/${MODULE}.sh"
    if [ -f "$MODULE_PATH" ]; then
        source "$MODULE_PATH"
    else
        echo "[!] Missing module: ${MODULE}.sh"
    fi
done

# Once everything is loaded we prepare the runtime state.
# it starts the logger and also repairs old latest_* report links,
# so the project does not keep broken symbolic links around.
init_logger

if declare -F repair_report_symlinks >/dev/null 2>&1; then
    repair_report_symlinks
fi

# This part is just for how things look on screen.
# it keeps some colors and the banner so the menu looks nicer
# and not too plain when the script starts.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[1;34m'
NC='\033[0m'

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ███████╗██╗   ██╗███████╗     █████╗ ██╗   ██╗██████╗ ██╗████████╗"
    echo "  ██╔════╝╚██╗ ██╔╝██╔════╝    ██╔══██╗██║   ██║██╔══██╗██║╚══██╔══╝"
    echo "  ███████╗ ╚████╔╝ ███████╗    ███████║██║   ██║██║  ██║██║   ██║   "
    echo "  ╚════██║  ╚██╔╝  ╚════██║    ██╔══██║██║   ██║██║  ██║██║   ██║   "
    echo "  ███████║   ██║   ███████║    ██║  ██║╚██████╔╝██████╔╝██║   ██║   "
    echo "  ╚══════╝   ╚═╝   ╚══════╝    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝   ╚═╝  "
    echo -e "${NC}"
    echo -e "  ${YELLOW}Linux System Audit & Monitoring Tool${NC}"
    echo -e "  ${BLUE}NSCS OS2 Mini-Project | $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "  Host: $(hostname) | User: $(whoami)"
    echo ""
}

section() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

# This section is for the main ways the project can run.
# it shows the local actions like reports, email, alerts, and logs,
# so the user can drive the project from one menu.
run_auto() {
    log_event "CRON_START" "Automated audit started"

    section "AUTO AUDIT: $(date)"

    echo "[*] Generating short report..."
    generate_short_txt
    generate_short_html

    echo "[*] Generating full report..."
    generate_full_txt
    generate_full_html

    if [ -n "$RECIPIENT_EMAIL" ]; then
        echo "[*] Sending email report..."
        send_report "$REPORT_DIR/latest_short.txt" "$RECIPIENT_EMAIL" "Short Report"
    fi

    check_alerts

    log_event "CRON_DONE" "Automated audit completed"
    echo "[+] Auto audit done. Reports in: $REPORT_DIR"
}

main_menu() {
    while true; do
        print_banner

        echo -e "  ${GREEN}MAIN MENU${NC}"
        echo "  ─────────────────────────────────────"
        echo "  1) Generate Short Report"
        echo "  2) Generate Full Report"
        echo "  3) Generate ALL Reports (txt + html)"
        echo "  ─────────────────────────────────────"
        echo "  4) Send Report via Email"
        echo "  5) Remote Monitoring"
        echo "  ─────────────────────────────────────"
        echo "  6) Check Resource Alerts"
        echo "  7) Verify Report Integrity"
        echo "  8) Compare Two Reports"
        echo "  ─────────────────────────────────────"
        echo "  9) Configure Email (setup guide)"
        echo " 10) View Logs"
        echo " 11) Setup Cron Job"
        echo "  ─────────────────────────────────────"
        echo "  0) Exit"
        echo ""
        read -rp "  Choose option [0-11]: " CHOICE

        case $CHOICE in
            1)
                section "SHORT REPORT"
                generate_short_txt
                generate_short_html
                log_event "REPORT_SHORT" "Generated"
                read -rp "Press Enter to continue..."
                ;;
            2)
                section "FULL REPORT"
                generate_full_txt
                generate_full_html
                log_event "REPORT_FULL" "Generated"
                read -rp "Press Enter to continue..."
                ;;
            3)
                section "GENERATING ALL REPORTS"
                generate_short_txt
                generate_short_html
                generate_full_txt
                generate_full_html
                log_event "REPORT_ALL" "Generated"
                echo ""
                echo -e "${GREEN}[+] All reports saved in: $REPORT_DIR${NC}"
                read -rp "Press Enter to continue..."
                ;;
            4)
                section "EMAIL REPORT"
                echo "Available reports:"
                ls "$REPORT_DIR"/*.txt 2>/dev/null | head -10 || echo "(none found)"
                echo ""
                read -rp "Enter report file path (or press Enter for latest short): " RFILE
                RFILE=${RFILE:-"$REPORT_DIR/latest_short.txt"}
                read -rp "Recipient email [${RECIPIENT_EMAIL}]: " REMAIL
                REMAIL=${REMAIL:-$RECIPIENT_EMAIL}
                send_report "$RFILE" "$REMAIL" "Audit Report"
                read -rp "Press Enter to continue..."
                ;;
            5)
                remote_menu
                ;;
            6)
                section "RESOURCE ALERTS"
                check_alerts
                read -rp "Press Enter to continue..."
                ;;
            7)
                section "VERIFY INTEGRITY"
                echo "Available reports:"
                ls "$REPORT_DIR"/*.sha256 2>/dev/null || echo "(no hashes found)"
                echo ""
                read -rp "Enter report file to verify: " VFILE
                verify_report "$VFILE"
                read -rp "Press Enter to continue..."
                ;;
            8)
                section "COMPARE REPORTS"
                read -rp "Enter first report file : " F1
                read -rp "Enter second report file: " F2
                compare_reports "$F1" "$F2"
                read -rp "Press Enter to continue..."
                ;;
            9)
                section "EMAIL CONFIGURATION"
                configure_email
                read -rp "Press Enter to continue..."
                ;;
           10)
                section "AUDIT LOGS"
                show_log 50
                read -rp "Press Enter to continue..."
                ;;
           11)
                section "CRON JOB SETUP"
                setup_cron
                read -rp "Press Enter to continue..."
                ;;
            0)
                echo ""
                echo -e "${YELLOW}[*] Exiting sys_audit. Bye!${NC}"
                log_event "EXIT" "User exited menu"
                exit 0
                ;;
            *)
                echo -e "${RED}[!] Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# This extra menu is only for the remote features.
# it keeps those options in their own place
# so the main menu does not get too crowded.
remote_menu() {
    while true; do
        print_banner
        echo -e "  ${GREEN}REMOTE MONITORING${NC}"
        echo "  ─────────────────────────────────────"
        echo "  1) Send Report to Remote Server"
        echo "  2) Pull Audit from Remote Machine"
        echo "  3) Live Monitor Remote Machine"
        echo "  4) Setup SSH Key Authentication"
        echo "  0) Back to Main Menu"
        echo ""
        read -rp "  Choose option [0-4]: " RCHOICE

        case $RCHOICE in
            1)
                section "SEND TO REMOTE"
                read -rp "Report file [latest_short.txt]: " RF
                RF=${RF:-"$REPORT_DIR/latest_short.txt"}
                read -rp "Remote user [${REMOTE_USER}]: " RU
                RU=${RU:-$REMOTE_USER}
                read -rp "Remote host [${REMOTE_HOST}]: " RH
                RH=${RH:-$REMOTE_HOST}
                remote_send_report "$RF" "$RU" "$RH"
                read -rp "Press Enter to continue..."
                ;;
            2)
                section "REMOTE AUDIT PULL"
                read -rp "Remote user [${REMOTE_USER}]: " RU
                RU=${RU:-$REMOTE_USER}
                read -rp "Remote host [${REMOTE_HOST}]: " RH
                RH=${RH:-$REMOTE_HOST}
                remote_pull_audit "$RU" "$RH"
                read -rp "Press Enter to continue..."
                ;;
            3)
                section "LIVE MONITOR"
                read -rp "Remote user [${REMOTE_USER}]: " RU
                RU=${RU:-$REMOTE_USER}
                read -rp "Remote host [${REMOTE_HOST}]: " RH
                RH=${RH:-$REMOTE_HOST}
                read -rp "Refresh interval in seconds [5]: " INTV
                INTV=${INTV:-5}
                remote_watch "$RU" "$RH" "$INTV"
                ;;
            4)
                section "SSH KEY SETUP"
                read -rp "Remote user [${REMOTE_USER}]: " RU
                RU=${RU:-$REMOTE_USER}
                read -rp "Remote host [${REMOTE_HOST}]: " RH
                RH=${RH:-$REMOTE_HOST}
                setup_ssh_keys "$RU" "$RH"
                read -rp "Press Enter to continue..."
                ;;
            0) return ;;
            *)
                echo -e "${RED}[!] Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# This last helper is for cron setup.
# it shows a ready line for automatic running
# and can add it if the user wants that.
setup_cron() {
    echo "Current crontab:"
    crontab -l 2>/dev/null || echo "(empty)"
    echo ""
    echo "Recommended cron entry (daily at 04:00 AM):"
    echo ""
    echo "  0 4 * * * ${SCRIPT_DIR}/main.sh --auto >> ${LOG_DIR}/cron.log 2>&1"
    echo ""
    read -rp "Add this cron entry? [y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        (crontab -l 2>/dev/null; echo "0 4 * * * ${SCRIPT_DIR}/main.sh --auto >> ${LOG_DIR}/cron.log 2>&1") | crontab -
        echo -e "${GREEN}[+] Cron job added successfully${NC}"
        echo ""
        echo "Verify with: crontab -l"
        log_event "CRON_SETUP" "Daily cron job configured"
    else
        echo "[i] Cron job not added"
    fi
}

# This is where the script decides what mode to start with.
# it checks the first argument and chooses the right entry point,
# so the same script works for menu mode and automation too.
case "${1:-}" in
    --auto)
        run_auto
        ;;
    --short)
        init_logger
        generate_short_txt
        generate_short_html
        ;;
    --full)
        init_logger
        generate_full_txt
        generate_full_html
        ;;
    --help|-h)
        echo "Usage: $0 [--auto|--short|--full|--help]"
        echo "  (no args)  : Interactive menu"
        echo "  --auto     : Run full automated audit (used by cron)"
        echo "  --short    : Generate short report only"
        echo "  --full     : Generate full report only"
        ;;
    *)
        main_menu
        ;;
esac
