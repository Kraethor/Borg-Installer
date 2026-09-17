#!/bin/bash
#
# borg-install.sh — sets up BorgBackup on a Linux host, backing up to a
# BorgBackup repo on a remote NFS share (e.g. a Synology NAS), with a daily
# cron job and log rotation-friendly logging.
#
# =============================================================================
# BEFORE YOU RUN THIS: edit the values in the CONFIGURATION block below.
#
#   BORG_PASSPHRASE   Passphrase that encrypts the Borg repo. Pick a strong,
#                      unique one and store it somewhere safe (password
#                      manager). Anyone with this passphrase AND access to the
#                      repo can read every backup. Losing it makes every
#                      backup permanently unrecoverable — there is no reset.
#   NFS_SERVER         Hostname or IP of the NFS server (e.g. your NAS).
#   NFS_DIRECTORY      Exported NFS path on that server (e.g. /volume1/backups).
#   REPO_MOUNT          Local mount point for the NFS share. Default /mnt/backup
#                       is fine for most setups.
#   KEEP_DAILY/WEEKLY/MONTHLY   Retention policy passed to `borg prune`.
#   BACKUP_PATHS        Directories to back up.
#   EXCLUDE_PATTERNS    Paths to exclude from the backup.
#
# The script refuses to run until every placeholder below has been replaced.
# =============================================================================

set -euo pipefail

# === Configuration — EDIT THESE ===
BORG_PASSPHRASE='<PASSPHRASE>'
NFS_SERVER='<NFS_SERVER_NAME>'
NFS_DIRECTORY='<NFS_DIRECTORY>'
REPO_MOUNT="/mnt/backup"

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6

BACKUP_PATHS=(
  /etc
  /home
  /usr/local
  /var/log
)

EXCLUDE_PATTERNS=(
  '/home/*/.cache'
  '/var/log/journal'
)

# === Placeholder guard — do not remove ===
for placeholder in "$BORG_PASSPHRASE" "$NFS_SERVER" "$NFS_DIRECTORY"; do
  if [[ "$placeholder" == \<*\> ]]; then
    echo "Error: you must edit the CONFIGURATION block at the top of this script" >&2
    echo "before running it. Found unedited placeholder: $placeholder" >&2
    exit 1
  fi
done

# === Derived values ===
REPO_PATH="${REPO_MOUNT}/$(hostname)"
BACKUP_SCRIPT="/usr/local/bin/backup-$(hostname).sh"
LOGFILE="/var/log/backup-$(hostname).log"

# === Ensure Required Packages are Installed ===
echo "Installing required packages..."
sudo apt-get update
sudo apt-get install -y borgbackup nfs-common

# === Ensure Mount Point Exists ===
echo "Ensuring mount point exists..."
sudo mkdir -p "$REPO_MOUNT"

# === Add NFS Entry to /etc/fstab if Missing ===
FSTAB_LINE="${NFS_SERVER}:${NFS_DIRECTORY} ${REPO_MOUNT} nfs4 defaults 0 0"

if ! grep -qs "${NFS_SERVER}:${NFS_DIRECTORY}" /etc/fstab; then
  echo "Adding NFS entry to /etc/fstab..."
  echo "$FSTAB_LINE" | sudo tee -a /etc/fstab
fi

# === Mount the NFS Share ===
echo "Mounting NFS share..."
sudo mount "$REPO_MOUNT"
sudo systemctl daemon-reload

# === Initialize Borg Repository if Not Exists ===
if [ ! -d "$REPO_PATH" ]; then
  echo "Initializing Borg repository at $REPO_PATH..."
  export BORG_PASSPHRASE="$BORG_PASSPHRASE"
  borg init --encryption=repokey-blake2 "$REPO_PATH"
fi

# === Build exclude args for the backup script ===
EXCLUDE_ARGS=""
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  EXCLUDE_ARGS+=" --exclude '${pattern}'"
done

# === Create Backup Script ===
echo "Creating backup script at $BACKUP_SCRIPT..."
cat <<EOF | sudo tee "$BACKUP_SCRIPT" > /dev/null
#!/bin/bash

# === Configuration ===
export BORG_PASSPHRASE='${BORG_PASSPHRASE}'
REPO="${REPO_PATH}"
TIMESTAMP=\$(date +%F-%H%M)
ARCHIVE="\${REPO}::\$(hostname)-\${TIMESTAMP}"
LOGFILE="${LOGFILE}"

# === Logging ===
exec >> "\$LOGFILE" 2>&1
echo "=== Backup started at \$(date) ==="

# === Create Archive ===
borg create --stats --compression zstd --progress "\$ARCHIVE" \\
    ${BACKUP_PATHS[@]}${EXCLUDE_ARGS}

# === Retention Policy ===
echo "=== Pruning old backups ==="
borg prune -v --list "\$REPO" \\
    --keep-daily=${KEEP_DAILY} \\
    --keep-weekly=${KEEP_WEEKLY} \\
    --keep-monthly=${KEEP_MONTHLY}

# === Optional: Compact Repository ===
echo "=== Compacting repository ==="
borg compact "\$REPO"

echo "=== Backup completed at \$(date) ==="

# === Cleanup ===
unset BORG_PASSPHRASE
EOF

unset BORG_PASSPHRASE

# === Set Permissions ===
sudo chmod +x "$BACKUP_SCRIPT"
sudo touch "$LOGFILE"
sudo chown root:adm "$LOGFILE"
sudo chmod 640 "$LOGFILE"

# === Add Cron Job if Not Already Present ===
CRON_JOB="0 3 * * * $BACKUP_SCRIPT"
if ! sudo crontab -l 2>/dev/null | grep -F "$BACKUP_SCRIPT" > /dev/null 2>&1; then
  echo "Adding cron job for daily backups..."
  (sudo crontab -l 2>/dev/null; echo "$CRON_JOB") | sudo crontab -
fi

echo "Setup complete."
