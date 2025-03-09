#!/bin/bash

set -eu -o pipefail

LOG_DIRECTORY="/data/backup_logs"
TIMESTAMP=$(date +%Y%m%d%H%M)
BACKUP_LOG_STDERR="${LOG_DIRECTORY}/backup_${TIMESTAMP}.stderr.log"
BACKUP_LOG_STDOUT="${LOG_DIRECTORY}/backup_${TIMESTAMP}.stdout.log"
LOG_RETENTION_DAYS=365
WEEKLY_REPORT_DAY="Sunday"
LOCK_FILE="/var/lock/backup_script.lock"

check_required_vars() {
    local missing_vars=()
    for var in \
        HEALTHCHECKS_URL \
        RESTIC_REPOSITORY \
        RESTIC_PASSWORD \
        SMTP_SERVER \
        SMTP_PORT \
        SMTP_USE_TLS \
        SMTP_USER \
        SMTP_PASSWORD \
        EMAIL_TO \
        EMAIL_FROM \
        ; do
        if [ -z "${!var+x}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo "Error: Missing required environment variables: ${missing_vars[*]}" >&2
        send_ping "/fail"
        exit 1
    fi
}

check_dependencies() {
    local missing_deps=()
    for cmd in restic pg_dumpall curl gzip df find flock; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if ! command -v mail >/dev/null 2>&1 && ! command -v msmtp >/dev/null 2>&1; then
        missing_deps+=("mail or msmtp")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        send_ping "/fail"
        exit 1
    fi
}

send_ping() {
    local status="$1"
    curl -fsS -m 10 --retry 3 "${HEALTHCHECKS_URL}${status}" > /dev/null 2>&1 || true
}

send_email() {
    local subject="$1"
    local body="$2"
    local temp_file

    temp_file=$(mktemp)

    {
        echo "Subject: $subject"
        echo "From: Backup System <${EMAIL_FROM}>"
        echo "To: ${EMAIL_TO}"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } > "$temp_file"

    if command -v msmtp >/dev/null 2>&1; then
        msmtp --host="$SMTP_SERVER" \
              --port="$SMTP_PORT" \
              --auth=on \
              --user="$SMTP_USER" \
              --passwordeval="echo $SMTP_PASSWORD" \
              $([ "$SMTP_USE_TLS" = "yes" ] && echo "--tls=on" || echo "--tls=off") \
              --from="$EMAIL_FROM" \
              -- "$EMAIL_TO" < "$temp_file" || echo "Failed to send email with msmtp" >> "$BACKUP_LOG_STDERR"
    elif command -v mail >/dev/null 2>&1; then
        mail -t < "$temp_file" || echo "Failed to send email with mail command" >> "$BACKUP_LOG_STDERR"
    else
        echo "No email sending mechanism available" >> "$BACKUP_LOG_STDERR"
    fi

    rm -f "$temp_file"
}

handle_failure() {
    local error_message="$1"
    local command="$2"
    local exit_code="${3:-$?}"
    local log_content=""
    if [ -f "${BACKUP_LOG_STDERR}" ]; then
        log_content=$(cat "${BACKUP_LOG_STDERR}")
    fi

    local email_body="Backup failed with the following error:
${error_message}

Failed command:
${command}

Error log contents:
${log_content}

Timestamp: ${TIMESTAMP}"

    send_email "Backup Failure Alert" "${email_body}"
    send_ping "/fail"
    exit "$exit_code"
}

rotate_logs() {
    echo "Starting log rotation..." >> "${BACKUP_LOG_STDOUT}"
    find "${LOG_DIRECTORY}" -name "backup_*.log" -type f -mtime +"${LOG_RETENTION_DAYS}" -delete 2>> "${BACKUP_LOG_STDERR}" || true
    find "${LOG_DIRECTORY}" -name "backup_*.log" -type f -mtime +1 -not -name "*.gz" -exec gzip {} \; 2>> "${BACKUP_LOG_STDERR}" || true
    echo "Log rotation completed" >> "${BACKUP_LOG_STDOUT}"
}

send_weekly_report() {
    local current_day=$(date +%A)

    if [ "$current_day" = "$WEEKLY_REPORT_DAY" ]; then
        local success_count=$(find "${LOG_DIRECTORY}" -name "backup_*.stdout.log*" -type f -mtime -7 | wc -l)
        local error_count=$(find "${LOG_DIRECTORY}" -name "backup_*.stderr.log*" -type f -mtime -7 -not -size 0 | wc -l)
        local latest_snapshot=$(restic -r "${RESTIC_REPOSITORY}" snapshots --latest 1 2>> "${BACKUP_LOG_STDERR}" || echo "Unable to retrieve snapshot information")
        local disk_usage=$(df -h /data | tail -n 1)

        local email_body="Weekly Backup Report

Backup Summary:
- Total backups run: ${success_count}
- Backups with errors: ${error_count}

Latest Snapshot Information:
${latest_snapshot}

Disk Usage:
${disk_usage}"

        send_email "Weekly Backup Success Report" "${email_body}"
    fi
}

cleanup() {
    if [ "${1:-}" != "success" ]; then
        send_ping "/fail"
    else
        send_ping ""
    fi
    trap - EXIT INT TERM
}

main() {
    trap 'cleanup' EXIT
    trap 'cleanup; exit 1' INT TERM
    send_ping "/start"
    mkdir -p "${LOG_DIRECTORY}"
    chmod 750 "${LOG_DIRECTORY}"
    echo "### START backup from: ${TIMESTAMP} ###" >> "${BACKUP_LOG_STDOUT}"
    check_dependencies
    check_required_vars
    rotate_logs

    if ! restic -r "${RESTIC_REPOSITORY}" snapshots 2>> "${BACKUP_LOG_STDERR}"; then
        echo "Initializing restic repository..." >> "${BACKUP_LOG_STDOUT}"
        restic -r "${RESTIC_REPOSITORY}" init 2>> "${BACKUP_LOG_STDERR}" || handle_failure "Failed to initialize restic repository" "restic init"
    fi

    echo "Starting restic backup..." >> "${BACKUP_LOG_STDOUT}"
    CMD="restic -r ${RESTIC_REPOSITORY} backup /data"
    eval "$CMD" 2>> "${BACKUP_LOG_STDERR}" || handle_failure "Failed to backup with restic" "$CMD"

    echo "Managing restic snapshots..." >> "${BACKUP_LOG_STDOUT}"
    CMD="restic -r ${RESTIC_REPOSITORY} forget --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 10"
    eval "$CMD" 2>> "${BACKUP_LOG_STDERR}" || handle_failure "Failed to forget with restic" "$CMD"

    echo "Pruning restic repository..." >> "${BACKUP_LOG_STDOUT}"
    CMD="restic -r ${RESTIC_REPOSITORY} prune --max-unused=10%"
    eval "$CMD" 2>> "${BACKUP_LOG_STDERR}" || handle_failure "Failed to prune with restic" "$CMD"

    echo "### STOP backup from: ${TIMESTAMP} ###" >> "${BACKUP_LOG_STDOUT}"

    send_weekly_report
    cleanup "success"
}

mkdir -p "$(dirname "$LOCK_FILE")"
(
    flock -n 200 || {
        echo "ERROR: Another backup process is already running. Exiting." >&2
        exit 1
    }
    main
) 200>"$LOCK_FILE"

exit 0
