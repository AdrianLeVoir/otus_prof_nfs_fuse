#!/usr/bin/env bash
# krb5_server.sh — Kerberos KDC + NFSv4(sec=krb5) на сервере (bellona).
# Запуск от root:  sudo bash krb5_server.sh
set -euo pipefail

REALM=OTUS.LOCAL
DOMAIN=otus.local
MASTER_PW=OtusKrb5master
USER_PW=OtusKrb5user

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

echo "===> Установка KDC"
export DEBIAN_FRONTEND=noninteractive
echo "krb5-config krb5-config/default_realm string $REALM" | debconf-set-selections
apt-get install -y krb5-kdc krb5-admin-server krb5-user

echo "===> Создание рейлма и принципалов"
kdb5_util create -s -r $REALM -P $MASTER_PW
systemctl enable --now krb5-kdc krb5-admin-server
for p in nfs/bellona.$DOMAIN nfs/irida.$DOMAIN host/bellona.$DOMAIN host/irida.$DOMAIN; do
  kadmin.local -q "addprinc -randkey $p"
done
kadmin.local -q "addprinc -pw $USER_PW adrianl"
kadmin.local -q "ktadd -k /etc/krb5.keytab nfs/bellona.$DOMAIN"
kadmin.local -q "ktadd -k /etc/krb5.keytab host/bellona.$DOMAIN"
rm -f /root/irida.keytab
kadmin.local -q "ktadd -k /root/irida.keytab nfs/irida.$DOMAIN"
kadmin.local -q "ktadd -k /root/irida.keytab host/irida.$DOMAIN"   # передать на клиент в /etc/krb5.keytab

echo "===> idmap + NFSv4(sec=krb5) экспорт"
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
printf 'options nfsd nfs4_disable_idmapping=0\n' > /etc/modprobe.d/nfsd-idmap.conf
echo 0 > /sys/module/nfsd/parameters/nfs4_disable_idmapping || true

mkdir -p /srv/krb5share/upload
chown -R nobody:nogroup /srv/krb5share
chmod 0777 /srv/krb5share/upload
grep -q '/srv/krb5share' /etc/exports || \
  echo "/srv/krb5share 192.168.1.233/32(rw,sync,no_subtree_check,root_squash,sec=krb5)" >> /etc/exports
exportfs -r
systemctl restart nfs-server nfs-idmapd rpc-gssd rpc-svcgssd
systemctl is-active nfs-server
exportfs -s
