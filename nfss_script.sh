#!/usr/bin/env bash
# nfss_script.sh — конфигурирование NFS-СЕРВЕРА (bellona, 192.168.1.200).
# Запуск от root:  sudo bash nfss_script.sh [CLIENT_IP]
set -euo pipefail

CLIENT_IP="${1:-192.168.1.233}"

echo "===> Установка nfs-kernel-server"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y nfs-kernel-server

echo "===> Подготовка экспортируемой директории"
mkdir -p /srv/share/upload
chown -R nobody:nogroup /srv/share
chmod 0777 /srv/share/upload

echo "===> /etc/exports"
cat > /etc/exports <<EOF
/srv/share ${CLIENT_IP}/32(rw,sync,root_squash,no_subtree_check)
EOF

echo "===> Экспорт и запуск сервиса"
exportfs -r
systemctl enable --now nfs-server
systemctl is-active nfs-server
exportfs -s
