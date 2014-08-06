#!/bin/bash

: ${SERVICE:=bitcasa}
: ${CPU:=100}
: ${MEMORY:=100M}
: ${DISK:=5G}

set -e -u

if ! test "$(whoami)" = 'root'; then
  echo 'this script must run as root.' >&2
  exit 1
fi

bitcasa::start() {
  if mountpoint -q "/storage/${SERVICE}/service"; then return; fi
  local cache_dir="/storage/${SERVICE}/mount/cache"
  local password="$(cat "/storage/${SERVICE}/password.txt")"
  mkdir -p "${cache_dir}"
  mount.bitcasa "$(cat "/storage/${SERVICE}/mail.txt")" \
                "/storage/${SERVICE}/service" \
                -o "password=${password},cachedir=${cache_dir}"
}

bitcasa::stop() {
  if mountpoint -q "/storage/${SERVICE}/service"; then
    fuser --kill "/storage/${SERVICE}/service" || true
    umount -f "/storage/${SERVICE}/service" || true
    if mountpoint -q "/storage/${SERVICE}/service"; then
      echo "failed to unmount: /storage/${SERVICE}/service" >&2
      exit 1
    fi
  fi
}

Mount() {
  if ! mountpoint -q "/storage/${SERVICE}/mount"; then
    if [ ! -f "/storage/${SERVICE}/image.dmg" ]; then
      echo "install ${SERVICE}: './service.sh install'" >&2
      exit 1
    fi
    e2fsck -y -f "/storage/${SERVICE}/image.dmg"
    resize2fs "/storage/${SERVICE}/image.dmg" "${DISK}"
    mount -t auto -o loop "/storage/${SERVICE}/image.dmg" \
                          "/storage/${SERVICE}/mount"
  fi
  chown root:root "/storage/${SERVICE}/mount"
}

Start() {
  Mount
  bitcasa::start
}

Stop() {
  if mountpoint -q "/storage/${SERVICE}/mount"; then
    fuser --kill "/storage/${SERVICE}/mount" || true
    umount -f "/storage/${SERVICE}/mount" || true
    if mountpoint -q "/storage/${SERVICE}/mount"; then
      echo "failed to unmount: /storage/${SERVICE}/mount" >&2
      exit 1
    fi
  fi
}

Install() {
  if ! which wget >/dev/null 2>/dev/null; then
    apt-get update -qq && apt-get -y install wget
  fi
  if ! which uuidgen >/dev/null 2>/dev/null; then
    apt-get update -qq && apt-get -y install uuid-runtime
  fi
  if ! which bitcasa >/dev/null 2>/dev/null; then
    echo "deb http://dist.bitcasa.com/release/apt debian main" \
        > /etc/apt/sources.list.d/bitcasa-release.list
    wget -O- http://dist.bitcasa.com/release/bitcasa-releases.gpg.key \
        | apt-key add -
    apt-get update -qq && apt-get -y install bitcasa
  fi
  Mount
  read -p "What's your email address for bitcasa? " email
  echo "${email}" >"/storage/${SERVICE}/mount/email.txt"
  read -p "What's your password for bitcasa? " password
  echo "${password}" >"/storage/${SERVICE}/mount/password.txt"
}

Uninstall() {
  Stop
  while true; do
    read -p "Do you really want to remove /storage/${SERVICE}? [yes/no] " yn
    if [ "${yn}" == 'yes' ]; then break; fi
    case "${yn}" in
      [Nn]*) exit;;
      *) echo "Please type 'Yes' or 'No'.";;
    esac
  done
  if mountpoint -q "/storage/${SERVICE}/mount"; then
    umount -f "/storage/${SERVICE}/mount"
  fi
  if [ -d "/storage/${SERVICE}" ]; then
    rm -rf "/storage/${SERVICE}"
  fi
}

command="$1"
shift
case "${command}" in
  'start') Start "$@";;
  'stop') Stop;;
  'install') Install;;
  'uninstall') Uninstall;;
  *) echo "no such command: ${command}" >&2;;
esac
