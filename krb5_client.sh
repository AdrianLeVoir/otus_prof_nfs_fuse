#!/usr/bin/env bash
# krb5_client.sh — NFSv4(sec=krb5) клиент (irida).
# Запуск от root:  sudo bash krb5_client.sh [SERVER]
set -euo pipefail

SERVER="${1:-bellona.otus.local}"
REALM=OTUS.LOCAL
DOMAIN=otus.local

echo "===> /etc/hosts"
grep -q "bellona.$DOMAIN" /etc/hosts || echo "192.168.1.200 bellona.$DOMAIN bellona" >> /etc/hosts
grep -q "irida.$DOMAIN"   /etc/hosts || echo "192.168.1.233 irida.$DOMAIN irida"     >> /etc/hosts

echo "===> /etc/krb5.conf"
cat > /etc/krb5.conf <<K
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    rdns = false
[realms]
    $REALM = {
        kdc = bellona.$DOMAIN
        admin_server = bellona.$DOMAIN
    }
[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
K

echo "===> Пакеты"
export DEBIAN_FRONTEND=noninteractive
echo "krb5-config krb5-config/default_realm string $REALM" | debconf-set-selections
apt-get install -y krb5-user nfs-common

echo "===> keytab (передаётся с сервера как /root/irida.keytab)"
install -m 600 -o root -g root /root/irida.keytab /etc/krb5.keytab

echo "===> idmap"
cat > /etc/idmapd.conf <<C
[General]
Verbosity = 0
Domain = $DOMAIN
Local-Realms = $REALM

[Mapping]
Nobody-User = nobody
Nobody-Group = nogroup

[Translation]
Method = nsswitch
C
printf 'options nfs nfs4_disable_idmapping=0\n' > /etc/modprobe.d/nfs-idmap.conf
echo 0 > /sys/module/nfs/parameters/nfs4_disable_idmapping || true

systemctl enable --now rpc-gssd
systemctl restart rpc-gssd

echo "===> kinit и монтирование NFSv4/kerberos"
echo 'OtusKrb5user' | kinit adrianl@$REALM
klist
mkdir -p /mnt/krb5
mount -t nfs4 -o vers=4.2,sec=krb5 "$SERVER:/srv/krb5share" /mnt/krb5
mount | grep krb5
ls -la /mnt/krb5/upload
