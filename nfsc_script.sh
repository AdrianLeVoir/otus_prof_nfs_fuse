#!/usr/bin/env bash
# nfsc_script.sh — конфигурирование NFS-КЛИЕНТА (irida, 192.168.1.233).
# Запуск от root:  sudo bash nfsc_script.sh [SERVER_IP]
set -euo pipefail

SERVER_IP="${1:-192.168.1.200}"

echo "===> Установка nfs-common"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y nfs-common

echo "===> Добавление automount в /etc/fstab (NFSv3)"
grep -q "${SERVER_IP}:/srv/share/" /etc/fstab || \
  echo "${SERVER_IP}:/srv/share/ /mnt nfs vers=3,noauto,x-systemd.automount 0 0" >> /etc/fstab
cat /etc/fstab

echo "===> Перегенерация systemd units и монтирование"
systemctl daemon-reload
systemctl restart remote-fs.target
ls /mnt >/dev/null    # первый доступ запускает automount
mount | grep /mnt
