#!/bin/bash
# This script handles sending reports by email.
# it resolves the report path, builds the message, and attaches the files,
# so the receiver gets the report in a cleaner way than plain text dumps.

# This first part checks the tools needed for email delivery.
# it makes sure the mail command and attachment encoder exist,
# so the send step fails early with a clear message when needed.
check_email_deps() {
    if ! command -v msmtp >/dev/null 2>&1; then
        echo "[!] msmtp is not installed."
        echo "[i] Install with: sudo apt install msmtp msmtp-mta"
        return 1
    fi

    if ! command -v base64 >/dev/null 2>&1; then
        echo "[!] base64 is not available."
        return 1
    fi

    return 0
}

# This helper resolves report paths before we try to attach anything.
# it uses the report module when available,
# so symbolic links and relative names still work correctly.

resolve_email_report_file() {
    if declare -F resolve_report_file >/dev/null 2>&1; then
        resolve_report_file "$1"
        return $?
    fi

    [ -f "$1" ] && printf '%s\n' "$1" #doesnt resolve, just checks if the file exists and returns the path
}


# This helper chooses the attachment content type.
# it keeps text and html reports readable to mail clients,
# so the receiver sees the right file type automatically.
attachment_mime_type() {
    local file_path="$1"

    [ -f "$file_path" ] || return 1

    if command -v file >/dev/null 2>&1; then
        file --brief --mime-type "$file_path" 2>/dev/null || echo "application/octet-stream"
    else
        echo "application/octet-stream"
    fi
}


# This main function builds the email and sends the attachments.
# it attaches the report file and also the hash file when present,
# so the receiver can open the report and verify it later.

send_report(){
    local REPORT_INPUT=$1
    local RECIPIENT=${2:-$RECIPIENT_EMAIL}
    local REPORT_TYPE=${3:-"Audit Report"}
    local REPORT_FILE
    local HASH_FILE
    local REPORT_NAME
    local HASH_NAME
    local SUBJECT
    local BODY
    local BOUNDARY
    local REPORT_MIME
    local HASH_MIME

    if [ -z "$REPORT_INPUT" ]; then
        echo "[!] No report file specified"
        return 1
    fi

    REPORT_FILE=$(resolve_email_report_file "$REPORT_INPUT") || {
        echo "[!] Report file not found: $REPORT_INPUT"
        return 1
    }

    if [ -z "$RECIPIENT" ]; then
        echo "[!] No recipient email configured"
        return 1
    fi

    check_email_deps || return 1

    HASH_FILE="${REPORT_FILE}.sha256"
    REPORT_NAME=$(basename "$REPORT_FILE")
    HASH_NAME=$(basename "$HASH_FILE")
    REPORT_MIME=$(attachment_mime_type "$REPORT_FILE")
    HASH_MIME=$(attachment_mime_type "$HASH_FILE")
    SUBJECT="[sys_audit] ${REPORT_TYPE} - $(hostname) - $(date '+%Y-%m-%d %H:%M')"

    BODY=$(cat <<EOF
Automated system audit report attached.

Host   : $(hostname)
Date   : $(date '+%Y-%m-%d %H:%M:%S')
Type   : $REPORT_TYPE
Report : $REPORT_NAME
EOF
)

    BOUNDARY="====sys_audit_$(date +%s)_$$===="

    echo "[*] Sending email to: $RECIPIENT"
    echo "[*] Resolved report   : $REPORT_FILE"

    # This block builds a multipart email with real attachments.
    # it keeps the mail body short and puts the files in attachments,
    # so long reports do not flood the message content itself.
    {
        echo "To: $RECIPIENT"
        echo "Subject: $SUBJECT"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary=\"$BOUNDARY\""
        echo ""
        echo "--$BOUNDARY"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo "Content-Transfer-Encoding: 8bit"
        echo ""
        printf '%s\n' "$BODY"
        echo ""
        echo "--$BOUNDARY"
        echo "Content-Type: $REPORT_MIME; name=\"$REPORT_NAME\""
        echo "Content-Transfer-Encoding: base64"
        echo "Content-Disposition: attachment; filename=\"$REPORT_NAME\""
        echo ""
        base64 -w 76 "$REPORT_FILE"

        if [ -f "$HASH_FILE" ]; then
            echo ""
            echo "--$BOUNDARY"
            echo "Content-Type: $HASH_MIME; name=\"$HASH_NAME\""
            echo "Content-Transfer-Encoding: base64"
            echo "Content-Disposition: attachment; filename=\"$HASH_NAME\""
            echo ""
            base64 -w 76 "$HASH_FILE"
        fi

        echo ""
        echo "--$BOUNDARY--"
    } | msmtp --account="$MSMTP_ACCOUNT" "$RECIPIENT" 2>&1
    if [ $? -eq 0 ]; then
        echo "[+] Email sent successfully to: $RECIPIENT"
        echo "[+] Attached report       : $REPORT_NAME"
        if [ -f "$HASH_FILE" ]; then
            echo "[+] Attached hash        : $HASH_NAME"
        fi
        log_event "EMAIL_SENT" "Report: $REPORT_FILE -> $RECIPIENT"
    else
        echo "[!] Email sending failed"
        log_event "EMAIL_FAILED" "Report: $REPORT_FILE -> $RECIPIENT"
        return 1
    fi
}


# This last part prints the setup guide for msmtp.
# it shows the config template and the important permissions,
# so the user can prepare email delivery without opening the script.
configure_email() {
    echo "============================================================"
    echo "  EMAIL CONFIGURATION GUIDE (msmtp + Gmail)"
    echo "============================================================"
    echo ""
    echo "1. Install msmtp:"
    echo "   sudo apt install msmtp msmtp-mta"
    echo ""
    echo "2. Create config file: ~/.msmtprc"
    echo "   (or /etc/msmtprc for system-wide)"
    echo ""
    echo "3. Add the following content:"
    echo ""
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
