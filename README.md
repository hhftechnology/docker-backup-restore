# Docker-backup-restore-toolkit

---

- [Installation](#-installation)
- [Usage](#-usage)
  - [backup](#backup)
  - [restore](#restore)
- [Contributing](#-contributing)
- [License](#license)

##  Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/hhftechnology/docker-backup-restore.git
cd docker-backup-restore
chmod +x toolkit.sh
```

##  Usage

The toolkit provides both CLI and interactive modes. If run without arguments (`./toolkit.sh`), it enters interactive menu mode for backup, restore, listing backups, etc. For CLI usage:

```text
Usage: toolkit.sh [options] [command]

Docker volume backup and restore utility
Author: @hhftechnology, https://github.com/hhftechnology

Options:
  -V, --version                         output the version number
  -h, --help                            display help for command

Commands:
  backup [options]                      backup from volume or volumes of a container
  restore [options]                     restore backup to volume
  help [command]                        display help for command
```

### backup

This command is used to backup a container's volumes or a single volume to timestamped tar files (e.g., `my-volume-20250821123456.tar.gz`).

#### Options

```txt
Usage: toolkit.sh backup [options]

backup from volume or volumes of a container

Options:
  -c, --container <container-name>      backup all volumes of a container
  -v, --volume <volume-name>            backup a single volume
  -h, --help                            display help for command
```

If no options are provided for `backup`, it will prompt for a container name interactively.

###### Examples

```bash
# Backup from all volumes of a container
./toolkit.sh backup --container my-container

# Backup from a single volume
./toolkit.sh backup --volume my-volume
```

### restore

This command is used to restore from a backup tar file to a volume. Backups are assumed to be in the current directory.

#### Options

```txt
Usage: toolkit.sh restore [options]

restore backup to volume

Options:
  -v, --volume <volume-name>            restore to this volume (required for single restore)
  -f, --file <file-name>                backup file to restore (required for single restore)
  -t, --timestamp <timestamp>           restore all volumes from backups with this timestamp
  -h, --help                            display help for command
```

If no options are provided for `restore`, it enters an interactive restore menu where you can select versions or single backups.

###### Examples

```bash
# Restore a single backup to a volume
./toolkit.sh restore --volume my-volume --file my-volume-20250821123456.tar.gz

# Restore all volumes from a specific timestamp
./toolkit.sh restore --timestamp 20250821123456
```

#### Interactive Mode

Run `./toolkit.sh` without arguments to access the main menu:

1. Backup  
   - Submenu for backing up containers or single volumes.  
   - For containers: Lists all containers with their associated volumes (if any), user selects by number to backup those volumes.  
   - For single volume: Lists all available volumes, user selects by number to backup.  
2. Restore  
   - Submenu for restoring a full version (all volumes from a timestamp) or a single backup.  
   - Lists available timestamps with formatted dates and associated volumes.  
   - For versions: Select by number, confirm, and restore all matching backups.  
   - For single: Select backup file, confirm or change target volume, and restore.  
3. List Backups  
   - Displays grouped backups by timestamp, showing formatted dates and volumes.  
4. Help  
   - Shows usage information.  
5. Exit  

Backups are versioned by timestamp. Restore operations overwrite existing volume data—use with caution. For consistency, consider stopping related containers before backup/restore. The script exits on errors such as non-existent containers or volumes.

##  Contributing

Contributions are welcome! Please submit pull requests for improvements.

##  License

MIT License

