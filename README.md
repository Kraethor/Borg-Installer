# Borg Install Script

This script (`borg-install.sh`) automates the setup of Borg backup on a Linux
host (developed on Raspberry Pi, but not Pi-specific), mounting a remote NFS
share (e.g. a Synology NAS), initializing a Borg repo, and creating a daily
backup job.

## Features

- Installs necessary packages (`borgbackup`, `nfs-common`)
- Configures and mounts an NFS share (adds `/etc/fstab` entry if missing)
- Initializes a Borg repository if it does not exist
- Creates a backup script specific to the host
- Schedules daily backups via `cron`
- Logs backups to `/var/log/backup-<hostname>.log`

## Before you run it

Open `borg-install.sh` and edit the **CONFIGURATION** block near the top:

| Variable | Description | Example |
|---|---|---|
| `BORG_PASSPHRASE` | Encrypts the Borg repo. Losing it makes every backup permanently unrecoverable. | `<PASSPHRASE>` |
| `NFS_SERVER` | Hostname or IP of your NFS server. | `<NFS_SERVER_NAME>` |
| `NFS_DIRECTORY` | Exported path on that server. | `<NFS_DIRECTORY>` |
| `REPO_MOUNT` | Local mount point for the share. | `/mnt/backup` |
| `KEEP_DAILY` / `KEEP_WEEKLY` / `KEEP_MONTHLY` | Retention policy for `borg prune`. | `7` / `4` / `6` |
| `BACKUP_PATHS` | Directories to back up. | `/etc /home /usr/local /var/log` |
| `EXCLUDE_PATTERNS` | Paths to exclude. | `/home/*/.cache` |

The script checks for unedited `<PLACEHOLDER>` values and refuses to run until
you've replaced them.

## Usage

1. Configure your NFS server to allow access from this host.
2. Copy the script to the target machine: `scp borg-install.sh user@host:/home/user/`
3. Edit the configuration block (see above).
4. Run the script as root: `sudo bash borg-install.sh`
5. Confirm backups are being created and logged.

## Notes

- The Borg passphrase is embedded in the generated per-host backup script for
  automation. Restrict that file's permissions and store the passphrase in a
  password manager.
- Default retention: 7 daily, 4 weekly, 6 monthly.
- Edit `BACKUP_PATHS` / `EXCLUDE_PATTERNS` to change what's backed up.
