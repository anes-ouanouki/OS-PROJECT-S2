#!/bin/bash
# This script handles sending reports by email.
# it resolves the report path, builds the message, and attaches the files,
# so the receiver gets the report in a cleaner way than plain text dumps.

# This first part checks the tools needed for email delivery.
# it makes sure the mail command and attachment encoder exist,
# so the send step fails early with a clear message when needed.
check_email_deps() {
    if ! command -v msmtp >/dev/null 2>&1; then
        echo "[!] msmtp is not installed"
        echo "[i] Install with: sudo apt install msmtp msmtp-mta"
        return 1
    fi

    if ! command -v base64 >/dev/null 2>&1; then
        echo "[!] base64 is not available"
        return 1
    fi
}
# This helper chooses the attachment content type.
# it keeps text and html reports readable to mail clients,
# so the receiver sees the right file type automatically.
attachment_mime_type() {
    local file_path=$1

    [ -f "$file_path" ] || return 1

    if command -v file >/dev/null 2>&1; then
        file --brief --mime-type "$file_path" 2>/dev/null || echo "application/octet-stream"
    else
        echo "application/octet-stream"
    fi
}

send_report() {
    local report_input=$1
    local recipient=${2:-$RECIPIENT_EMAIL}
    local report_type=${3:-"Audit Report"}
    local report_file
    local hash_file
    local report_name
    local hash_name
    local subject
    local body
    local boundary
    local report_mime
    local hash_mime

    if [ -z "$report_input" ]; then
        echo "[!] No report file specified"
        return 1
    fi

    report_file=$(resolve_report_file "$report_input") || {
        echo "[!] Report file not found: $report_input"
        return 1
    }

    if [ -z "$recipient" ]; then
        echo "[!] No recipient email configured"
        return 1
    fi

    check_email_deps || return 1

    hash_file="${report_file}.sha256"
    report_name=$(basename "$report_file")
    hash_name=$(basename "$hash_file")
    report_mime=$(attachment_mime_type "$report_file")
    if [ -f "$hash_file" ]; then
        hash_mime=$(attachment_mime_type "$hash_file")
    fi

    subject="[sys_audit] ${report_type} - $(hostname) - $(date '+%Y-%m-%d %H:%M')"
    body=$(cat <<EOF
System audit report attached.

Host   : $(hostname)
Date   : $(date '+%Y-%m-%d %H:%M:%S')
Type   : $report_type
Report : $report_name
EOF
)
    boundary="====sys_audit_$(date +%s)_$$===="

    echo "[*] Sending email to: $recipient"
    echo "[*] Report: $report_file"
    
    # This block builds a multipart email with real attachments.
    # it keeps the mail body short and puts the files in attachments,
    # so long reports do not flood the message content itself.
    {
        echo "To: $recipient"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary=\"$boundary\""
        echo
        echo "--$boundary"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo "Content-Transfer-Encoding: 8bit"
        echo
        printf '%s\n' "$body"
        echo
        echo "--$boundary"
        echo "Content-Type: $report_mime; name=\"$report_name\""
        echo "Content-Transfer-Encoding: base64"
        echo "Content-Disposition: attachment; filename=\"$report_name\""
        echo
        base64 -w 76 "$report_file"

        if [ -f "$hash_file" ]; then
            echo
            echo "--$boundary"
            echo "Content-Type: $hash_mime; name=\"$hash_name\""
            echo "Content-Transfer-Encoding: base64"
            echo "Content-Disposition: attachment; filename=\"$hash_name\""
            echo
            base64 -w 76 "$hash_file"
        fi

        echo
        echo "--$boundary--"
    } | msmtp --account="$MSMTP_ACCOUNT" "$recipient" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "[+] Email sent to: $recipient"
        log_event "EMAIL_SENT" "Report: $report_file -> $recipient"
    else
        echo "[!] Email sending failed"
        log_event "EMAIL_FAILED" "Report: $report_file -> $recipient"
        return 1
    fi
}


# This last part prints the setup guide for msmtp.
# it shows the config template and the important permissions,
# so the user can prepare email delivery without opening the script.
configure_email() {
    echo "============================================================"
    echo "EMAIL CONFIGURATION GUIDE"
    echo "============================================================"
    echo
    echo "1. Install msmtp:"
    echo "   sudo apt install msmtp msmtp-mta"
    echo
    echo "2. Create ~/.msmtprc and add:"
    echo
    cat <<'CONF'
# ~/.msmtprc
defaults
    auth           on
    tls            on
    tls_trust_file /etc/ssl/certs/ca-certificates.crt
    logfile        ~/.msmtp.log

account gmail
    host           smtp.gmail.com
    port           587
    from           your_email@gmail.com
    user           your_email@gmail.com
    password       YOUR_APP_PASSWORD_HERE

account default : gmail
CONF
    echo ""
    echo "4. Set permissions (REQUIRED - msmtp refuses world-readable configs):"
    echo "   chmod 600 ~/.msmtprc"
    echo ""
    echo "5. Gmail: Create App Password at:"
    echo "   https://myaccount.google.com/apppasswords"
    echo "   (Requires 2-Step Verification enabled)"
    echo ""
    echo "6. Test:"
    echo "   echo 'Test email' | msmtp --account=gmail your_email@gmail.com"
    echo ""
    echo "7. Update config.cfg with your RECIPIENT_EMAIL"
    echo "============================================================"
}
