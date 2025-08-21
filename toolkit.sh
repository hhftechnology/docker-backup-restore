#!/bin/bash

set -e

has_args() { [[ "$1" == *=* ]] && [[ -n "${1#*=}" ]] || [[ ! -z "$2" && "$2" != -* ]]; }

arg_exists() {
  for arg in "$@"; do
    if [ "$arg" == "$1" ]; then
      return 0
    fi
  done
  return 1
}

read_arg() {
  local opts="$1"
  IFS='|' read -ra FS <<< "$opts"
  shift
  while (("$#")); do
    for opt in "${FS[@]}"; do
      if [ "$1" == "$opt" ]; then
        if [[ "$2" != -* ]] && [[ -n "$2" ]]; then
          echo "$2"
          return
        elif [[ "$1" == *=* ]]; then
          echo "${1#*=}"
          return
        fi
      fi
    done
    shift
  done
}

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

usage() {
  case $1 in
    backup)
      echo "Usage: $(basename "$0") backup [options]"
      echo ""
      echo "backup from volume or volumes of a container"
      echo ""
      echo "Options:"
      echo "  -c, --container <container-name>      backup all volumes of a container"
      echo "  -v, --volume <volume-name>            backup a single volume"
      echo "  -h, --help                            display help for command"
      ;;
    restore)
      echo "Usage: $(basename "$0") restore [options]"
      echo ""
      echo "restore backup to volume"
      echo ""
      echo "Options:"
      echo "  -v, --volume <volume-name>            restore to this volume (required for single restore)"
      echo "  -f, --file <file-name>                backup file to restore (required for single restore)"
      echo "  -t, --timestamp <timestamp>           restore all volumes from backups with this timestamp"
      echo "  -h, --help                            display help for command"
      ;;
    *)
      echo "Usage: $(basename "$0") [options] [command]"
      echo ""
      echo "Docker volume backup and restore utility"
      echo "Author: @hhftechnology, https://github.com/hhftechnology"
      echo ""
      echo "Options:"
      echo "  -V, --version                         output the version number"
      echo "  -h, --help                            display help for command"
      echo ""
      echo "Commands:"
      echo "  backup [options]                      backup from volume or volumes of a container"
      echo "  restore [options]                     restore backup to volume"
      echo "  help [command]                        display help for command"
      ;;
  esac
}

format_timestamp() {
  local ts=$1
  echo "${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}:${ts:12:2}"
}

check_volume() {
  local VOLUME=$1
  if [ -z "$VOLUME" ]; then
    log "ERR: Volume name is required"
    exit 1
  fi
  local LIST=$(sudo docker volume ls -q --filter name="$VOLUME")
  if [ -z "$LIST" ]; then
    log "ERR: Volume $VOLUME not found"
    exit 1
  fi
}

backup_volume() {
  local VOLUME=$1
  check_volume "$VOLUME"
  local NOW="$(date +%Y%m%d%H%M%S)"
  local TAR_FILE="$VOLUME-$NOW.tar.gz"
  log "Backing up $VOLUME to $TAR_FILE"
  sudo docker run --rm -v "$(pwd)":/backup -v "$VOLUME":/volume ubuntu:latest tar -czvf /backup/"$TAR_FILE" -C /volume .
  if [ $? -eq 0 ]; then
    log "Backup successful"
  else
    log "ERR: Backup failed"
    exit 1
  fi
}

restore_volume() {
  local VOLUME=$1
  local TAR_FILE=$2
  check_volume "$VOLUME"
  if [ ! -f "$TAR_FILE" ]; then
    log "ERR: Backup file $TAR_FILE not found"
    exit 1
  fi
  log "Restoring $TAR_FILE to $VOLUME"
  sudo docker run --rm -v "$(pwd)":/backup -v "$VOLUME":/restore ubuntu:latest tar -xzvf /backup/"$TAR_FILE" -C /restore
  if [ $? -eq 0 ]; then
    log "Restore successful"
  else
    log "ERR: Restore failed"
    exit 1
  fi
}

list_volumes() {
  local CONTAINER_NAME=$1
  sudo docker inspect -f '{{ range .Mounts }}{{ printf "\n" }}{{ .Type }} {{ if eq .Type "bind" }}{{ .Source }}{{ end }}{{ .Name }} => {{ .Destination }}{{ end }}{{ printf "\n" }}' "$CONTAINER_NAME" | grep volume
}

check_container() {
  local CONTAINER_NAME=$1
  local LIST=$(sudo docker ps -a -q --filter name="$CONTAINER_NAME")
  if [ -z "$LIST" ]; then
    log "ERR: Container $CONTAINER_NAME not found"
    exit 1
  fi
}

get_timestamps() {
  local timestamps=""
  for file in *.tar.gz; do
    if [[ $file =~ -([0-9]{14})\.tar\.gz$ ]]; then
      timestamps+="${BASH_REMATCH[1]}\n"
    fi
  done
  echo -e "$timestamps" | sort -u
}

list_backups() {
  local timestamps=$(get_timestamps)
  if [ -z "$timestamps" ]; then
    echo "No backups found in current directory."
    return
  fi
  echo "Available backups grouped by version (timestamp):"
  while IFS= read -r ts; do
    local files=$(ls *-${ts}.tar.gz 2>/dev/null)
    local vols=$(for f in $files; do echo "${f%-${ts}.tar.gz}"; done | tr '\n' ',' | sed 's/,$//')
    local display=$(format_timestamp "$ts")
    echo "- $display ($ts) - Volumes: $vols"
  done <<< "$timestamps"
}

backup_menu() {
  while true; do
    echo ""
    echo "Backup Menu:"
    echo "1. Backup volumes from container"
    echo "2. Backup single volume"
    echo "3. Back to main menu"
    read -p "Choose option: " ch
    case $ch in
      1)
        local containers=$(sudo docker ps -a --format "{{.Names}}")
        if [ -z "$containers" ]; then
          echo "No containers found."
          continue
        fi
        declare -A cont_map
        local index=1
        echo "Available containers with volumes:"
        for cont in $containers; do
          local vols=$(list_volumes "$cont" | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
          if [ -n "$vols" ]; then
            echo "$index. $cont - Volumes: $vols"
            cont_map[$index]=$cont
            ((index++))
          fi
        done
        if [ $index -eq 1 ]; then
          echo "No containers with volumes found."
          continue
        fi
        read -p "Choose container number: " sel
        if [[ $sel =~ ^[0-9]+$ ]] && [ $sel -ge 1 ] && [ $sel -lt $index ]; then
          local CONTAINER_NAME=${cont_map[$sel]}
          check_container "$CONTAINER_NAME"
          local vol_list=$(list_volumes "$CONTAINER_NAME" | awk '{print $2}')
          if [ -z "$vol_list" ]; then
            echo "No volumes found for $CONTAINER_NAME."
            continue
          fi
          for VOLUME in $vol_list; do
            if [ -n "$VOLUME" ]; then
              backup_volume "$VOLUME"
            fi
          done
        else
          echo "Invalid choice."
        fi
        ;;
      2)
        local volumes=$(sudo docker volume ls -q)
        if [ -z "$volumes" ]; then
          echo "No volumes found."
          continue
        fi
        declare -A vol_map
        local index=1
        echo "Available volumes:"
        for vol in $volumes; do
          echo "$index. $vol"
          vol_map[$index]=$vol
          ((index++))
        done
        read -p "Choose volume number: " sel
        if [[ $sel =~ ^[0-9]+$ ]] && [ $sel -ge 1 ] && [ $sel -lt $index ]; then
          local VOLUME=${vol_map[$sel]}
          backup_volume "$VOLUME"
        else
          echo "Invalid choice."
        fi
        ;;
      3) return ;;
      *) echo "Invalid option" ;;
    esac
  done
}

restore_version() {
  local timestamps=$(get_timestamps)
  if [ -z "$timestamps" ]; then
    echo "No backups found."
    return
  fi
  local ts_array=($(echo "$timestamps"))
  echo "Available versions:"
  for i in "${!ts_array[@]}"; do
    local ts=${ts_array[$i]}
    local files=$(ls *-${ts}.tar.gz)
    local vols=$(for f in $files; do echo "${f%-${ts}.tar.gz}"; done | tr '\n' ',' | sed 's/,$//')
    local display=$(format_timestamp "$ts")
    echo "$((i+1)). $display ($ts) - Volumes: $vols"
  done
  read -p "Choose version number: " ch
  if [[ $ch =~ ^[0-9]+$ ]] && [ "$ch" -ge 1 ] && [ "$ch" -le "${#ts_array[@]}" ]; then
    local ts=${ts_array[$((ch-1))]}
    read -p "Confirm restore for version $ts? This will overwrite volumes! (y/n): " conf
    if [ "$conf" = "y" ] || [ "$conf" = "Y" ]; then
      for file in *-${ts}.tar.gz; do
        if [ -e "$file" ]; then
          local volume=${file%-${ts}.tar.gz}
          restore_volume "$volume" "$file"
        fi
      done
    else
      echo "Restore cancelled."
    fi
  else
    echo "Invalid choice."
  fi
}

restore_single() {
  local backup_files=$(ls *.tar.gz 2>/dev/null)
  if [ -z "$backup_files" ]; then
    echo "No backups found."
    return
  fi
  local file_array=($(echo "$backup_files"))
  echo "Available backups:"
  for i in "${!file_array[@]}"; do
    echo "$((i+1)). ${file_array[$i]}"
  done
  read -p "Choose backup number: " ch
  if [[ $ch =~ ^[0-9]+$ ]] && [ "$ch" -ge 1 ] && [ "$ch" -le "${#file_array[@]}" ]; then
    local file=${file_array[$((ch-1))]}
    local default_vol=${file%%-[0-9]*.tar.gz}
    read -p "Restore to volume [$default_vol]: " vol
    vol=${vol:-$default_vol}
    read -p "Confirm restore $file to $vol? This will overwrite the volume! (y/n): " conf
    if [ "$conf" = "y" ] || [ "$conf" = "Y" ]; then
      restore_volume "$vol" "$file"
    else
      echo "Restore cancelled."
    fi
  else
    echo "Invalid choice."
  fi
}

restore_menu() {
  while true; do
    echo ""
    echo "Restore Menu:"
    echo "1. Restore a version (all volumes from timestamp)"
    echo "2. Restore a single backup"
    echo "3. Back to main menu"
    read -p "Choose option: " ch
    case $ch in
      1) restore_version ;;
      2) restore_single ;;
      3) return ;;
      *) echo "Invalid option" ;;
    esac
  done
}

show_menu() {
  while true; do
    echo ""
    echo "Docker Backup Toolkit"
    echo "1. Backup"
    echo "2. Restore"
    echo "3. List Backups"
    echo "4. Help"
    echo "5. Exit"
    read -p "Choose option: " choice
    case $choice in
      1) backup_menu ;;
      2) restore_menu ;;
      3) list_backups ;;
      4) usage ;;
      5) exit 0 ;;
      *) echo "Invalid option" ;;
    esac
  done
}

if [ $# -eq 0 ]; then
  show_menu
  exit 0
fi

if arg_exists "--help" "$@" || arg_exists "-h" "$@"; then
  usage
  exit 0
fi

if arg_exists "--version" "$@" || arg_exists "-V" "$@"; then
  echo "Version 1.0"
  exit 0
fi

case $1 in
  backup)
    shift
    if arg_exists "--volume" "$@" || arg_exists "-v" "$@"; then
      _VOLUME_NAME=$(read_arg "-v|--volume" "$@")
      backup_volume "$_VOLUME_NAME"
      exit 0
    fi

    if arg_exists "--container" "$@" || arg_exists "-c" "$@"; then
      CONTAINER_NAME=$(read_arg "-c|--container" "$@")
    else
      read -r -p "Container name: " CONTAINER_NAME
    fi

    check_container "$CONTAINER_NAME"

    for VOLUME in $(list_volumes "$CONTAINER_NAME" | awk '{print $2}'); do
      if [ -n "$VOLUME" ]; then
        backup_volume "$VOLUME"
      fi
    done
    ;;
  restore)
    shift
    if arg_exists "--timestamp" "$@" || arg_exists "-t" "$@"; then
      _TS=$(read_arg "-t|--timestamp" "$@")
      for file in *-${_TS}.tar.gz; do
        if [ -e "$file" ]; then
          volume=${file%-${_TS}.tar.gz}
          restore_volume "$volume" "$file"
        fi
      done
      exit 0
    fi

    if (arg_exists "--volume" "$@" || arg_exists "-v" "$@") && (arg_exists "--file" "$@" || arg_exists "-f" "$@"); then
      _VOLUME_NAME=$(read_arg "-v|--volume" "$@")
      _FILE=$(read_arg "-f|--file" "$@")
      restore_volume "$_VOLUME_NAME" "$_FILE"
      exit 0
    fi

    restore_menu
    ;;
  help)
    usage "$2"
    ;;
  *)
    usage
    exit 1
    ;;
esac

exit 0