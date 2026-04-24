# sys_audit - Linux System Audit and Monitoring Tool

**NSCS OS2 Mini-Project Part 1**

This project is a Bash-based system audit tool for Linux. It can generate short and full reports, save them as text and HTML, verify report integrity with SHA-256, send reports by email, copy reports to a remote host over SSH, and watch remote machines in real time.

---

## Project Structure

```text
sys_audit/
|- main.sh                  # Main entry point and menu
|- config.cfg               # Paths, email settings, remote settings, thresholds
|- modules/
|  |- hw_audit.sh           # Hardware information collection
|  |- sw_audit.sh           # Software and OS information collection
|  |- report.sh             # Report generation, hashes, latest links
|  |- email.sh              # Email delivery with attachments
|  |- remote.sh             # SSH transfer, remote snapshot, live watch
|  |- alerts.sh             # CPU, RAM, and disk threshold alerts
|  `- logger.sh             # Shared logging and log rotation
|- reports/                 # Generated reports and latest links
`- logs/                    # Runtime logs
```

---

## Main Features

- Short and full audit reports in `.txt` and `.html`
- Stable `latest_*` symbolic links for the newest reports
- SHA-256 hash file for every generated report
- Report integrity verification from the menu
- Report comparison with `diff`
- Email delivery with the report attached
- Optional `.sha256` attachment for email and remote copy
- Remote report transfer over SSH/SCP
- Remote quick audit snapshot
- Remote live monitoring loop
- Resource alerts for CPU, RAM, and disk usage
- Log rotation when the log file gets too large

---

## Installation

### 1. Extract or clone the project

```bash
cd ~
# If you received a zip:
unzip sys_audit.zip
cd sys_audit
```

### 2. Make scripts executable

```bash
chmod +x main.sh modules/*.sh
```

### 3. Install dependencies

```bash
# Core tools
sudo apt update
sudo apt install util-linux procps iproute2 net-tools lsb-release coreutils findutils

# Hardware information
sudo apt install usbutils pciutils dmidecode

# Email delivery
sudo apt install msmtp msmtp-mta

# Remote features
sudo apt install openssh-client

# Optional but useful
sudo apt install file
```

Notes:
- `dmidecode` gives more hardware detail when the script is run as root.
- `file` is optional. It helps email attachments get a better MIME type, but the project still works without it.

---

## Configuration

Edit `config.cfg` before using email, remote transfer, or custom paths:

```bash
nano config.cfg
```

Main values to update:

- `REPORT_DIR` and `LOG_DIR` for output locations
- `RECIPIENT_EMAIL` and `MSMTP_ACCOUNT` for email delivery
- `REMOTE_USER`, `REMOTE_HOST`, and `REMOTE_REPORT_DIR` for SSH transfer
- `CPU_ALERT_THRESHOLD`, `RAM_ALERT_THRESHOLD`, and `DISK_ALERT_THRESHOLD` for alerts

---

## How to Run

### Interactive menu

```bash
./main.sh
```

### Command line modes

```bash
./main.sh --short    # Generate short text and short HTML reports
./main.sh --full     # Generate full text and full HTML reports
./main.sh --auto     # Generate all reports, send email if configured, check alerts
./main.sh --help
```

---

## Report Behavior

Reports are saved in `./reports/` with names like:

```text
short_hostname_YYYYMMDD_HHMMSS.txt
short_hostname_YYYYMMDD_HHMMSS.html
full_hostname_YYYYMMDD_HHMMSS.txt
full_hostname_YYYYMMDD_HHMMSS.html
```

For easier automation, the newest reports are also available through stable symbolic links:

```text
reports/latest_short.txt
reports/latest_short.html
reports/latest_full.txt
reports/latest_full.html
```

Each generated report also creates:

```text
report_name.ext.sha256
```

The hash file is portable because it stores the report basename instead of a full absolute path. That makes verification easier after the report is copied somewhere else.

### Report content

- Short reports give a quick overview of hardware, software, uptime, services, and top listening ports.
- Full reports keep more detail but avoid very noisy sections like a full installed-package dump.
- HTML reports use the same report content in a simple page layout.

### Integrity verification

Use the menu option:

```text
7) Verify Report Integrity
```

The project also repairs older broken `latest_*` report links automatically when it starts.

---

## Email Delivery

The email feature sends the chosen report as an attachment instead of placing the entire report inside the mail body. When a matching `.sha256` file exists, it is attached too.

### Configure msmtp

Create `~/.msmtprc`:

```text
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
    password       YOUR_GMAIL_APP_PASSWORD
(you can gmail app password  by going to app passwords and copying 16 letter code )
account default : gmail
```

Set the required permissions:

```bash
chmod 600 ~/.msmtprc
```

Quick test:

```bash
echo "Test email" | msmtp --account=gmail your_email@gmail.com
```

After that, update `RECIPIENT_EMAIL` in `config.cfg`.

---

## Remote Monitoring and Transfer

### Send a report to a remote machine

Menu path:

```text
5) Remote Monitoring
1) Send Report to Remote Server
```

Behavior:

- Resolves the chosen report path
- Creates the remote report directory if needed
- Copies the report with `scp`
- Copies the matching `.sha256` file too when it exists

### Pull a remote snapshot

Menu path:

```text
5) Remote Monitoring
2) Pull Audit from Remote Machine
```

This gives a short remote summary with:

- hostname and OS
- uptime
- current CPU load
- memory usage
- disk usage
- listening ports
- active users

### Live remote watch

Menu path:

```text
5) Remote Monitoring
3) Live Monitor Remote Machine
```

This refreshes the remote host snapshot every few seconds until you stop it with `Ctrl+C`.

### SSH key setup

Menu path:

```text
5) Remote Monitoring
4) Setup SSH Key Authentication
```

The project uses an `ed25519` SSH key when it generates one automatically.

Manual equivalent:

```bash
ssh-keygen -t ed25519
ssh-copy-id user@remote_host
```

---

## Cron Automation

The menu includes a cron helper:

```text
11) Setup Cron Job
```

Default suggested entry:

```text
0 4 * * * /full/path/to/sys_audit/main.sh --auto >> /full/path/to/sys_audit/logs/cron.log 2>&1
```

You can also add it manually with:

```bash
crontab -e
```

And verify with:

```bash
crontab -l
```

---

## Security Notes

- SSH key-based access is used for remote monitoring and transfer
- No password is stored directly in the scripts
- `msmtp` config should be protected with `chmod 600`
- Report integrity is checked with `sha256sum`
- `config.cfg` should not be committed to a public repository if it contains real personal settings

---

## Authors

- Student: ouanouki anes
- School: National School of Cybersecurity (NSCS)
- Course: OS2 - Academic Year 2025/2026
- Teacher: Dr. BENTRAD Sassi
