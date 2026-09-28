# Домашнее задание: Работа с NFS

## Название и текст задания

**Работа с NFS.** Цель — научиться самостоятельно разворачивать сервис NFS и
подключать к нему клиентов.

Основная часть:
- запустить 2 виртуальные машины (сервер NFS и клиента);
- на сервере NFS подготовить и экспортировать директорию;
- в экспортированной директории создать подкаталог `upload` с правами на запись;
- экспортированная директория должна автоматически монтироваться на клиенте при
  старте ВМ (systemd, autofs или fstab);
- монтирование и работа NFS на клиенте — с использованием **NFSv3**.

⭐ Задание со звёздочкой: аутентификация через **KERBEROS** с **NFSv4**.

## Стенд

| Роль | ОС |
|---|---|---|---|
| NFS-**сервер** | Ubuntu 24.04.4 LTS |
| NFS-**клиент** | Ubuntu 24.04.3 LTS |

Сервер и клиент — отдельные ВМ (bellona — VM 300 на Proxmox `Hecate`, irida — VM 103),
находятся в одной сети `192.168.1.0/24`.

## Описание каталогов и файлов репозитория

```
hw3/
├── README.md            — этот отчёт
├── nfss_script.sh       — bash-скрипт конфигурирования NFS-сервера
├── nfsc_script.sh       — bash-скрипт конфигурирования NFS-клиента
├── krb5_server.sh       — ⭐ Kerberos KDC + экспорт NFSv4(sec=krb5) на сервере
├── krb5_client.sh       — ⭐ настройка NFSv4(sec=krb5)-клиента + kinit + монтирование
└── logs/                — логи выполнения, снятые утилитой script
    ├── nfs_server.log            — установка и настройка сервера (NFSv3)
    ├── nfs_client.log            — установка и настройка клиента (NFSv3)
    ├── nfs_check_server1.log     — создание check_file на сервере
    ├── nfs_check_client1.log     — проверка/создание client_file на клиенте
    ├── nfs_check_server2.log     — проверка client_file и showmount на сервере
    ├── nfs_client_reboot.log     — клиент после перезагрузки
    ├── nfs_server_reboot.log     — сервер после перезагрузки
    ├── nfs_client_final.log      — финальная проверка клиента + final_check
    ├── krb_server.log            — ⭐ установка KDC, принципалы, keytab
    ├── krb_server2.log           — ⭐ idmapd и экспорт sec=krb5
    ├── krb_client.log            — ⭐ настройка клиента Kerberos
    ├── krb_mount.log             — ⭐ kinit + монтирование NFSv4 sec=krb5
    └── krb_write.log             — ⭐ запись в /mnt/krb5/upload от имени adrianl
```

## Реализация

### Сервер NFS (bellona)

```bash
apt install nfs-kernel-server
mkdir -p /srv/share/upload
chown -R nobody:nogroup /srv/share
chmod 0777 /srv/share/upload

cat > /etc/exports <<'EOF'
/srv/share 192.168.1.233/32(rw,sync,root_squash,no_subtree_check)
EOF

exportfs -r
systemctl enable --now nfs-server
exportfs -s
```

Проверка экспорта и портов:

```
# exportfs -s
/srv/share  192.168.1.233/32(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)

# ss -tnplu | grep -E ':2049|:111'
udp/tcp 0.0.0.0:111   (rpcbind)
tcp 0.0.0.0:2049      (nfsd)
```

### Клиент NFS

```bash
apt install nfs-common
echo "192.168.1.200:/srv/share/ /mnt nfs vers=3,noauto,x-systemd.automount 0 0" >> /etc/fstab
systemctl daemon-reload
systemctl restart remote-fs.target
ls /mnt        # первый доступ запускает automount
mount | grep mnt
```

Фактическое монтирование ( `vers=3`):

```
systemd-1 on /mnt type autofs (rw,relatime,...)
192.168.1.200:/srv/share/ on /mnt type nfs (rw,relatime,vers=3,rsize=524288,wsize=524288,
  namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=192.168.1.200,
  mountvers=3,mountport=50136,mountproto=udp,local_lock=none,addr=192.168.1.200)
```

### Проверка работоспособности

1. На сервере: `touch /srv/share/upload/check_file`.
2. На клиенте: `test -f /mnt/upload/check_file` → **OK**, `touch /mnt/upload/client_file`.
3. На сервере: `test -f /srv/share/upload/client_file` → **OK**; `showmount -a localhost` → `192.168.1.233:/srv/share`.
4. Перезагрузка клиента → файлы на месте, монтирование `vers=3` восстановилось автоматически.
5. Перезагрузка сервера → файлы на месте, `exportfs -s` активен, `showmount -a 192.168.1.200` видит клиент.
6. Перезагрузка клиента → `showmount -a 192.168.1.200`, файлы на месте, `touch /mnt/upload/final_check`
   → файл виден и на сервере.

Все проверки пройдены.

## Особенности реализации

- **Автомонтирование** выполнено через `fstab` + `x-systemd.automount`: systemd
  генерирует automount-unit в `/run/systemd/generator/`, поэтому монтирование
  фактически происходит при первом обращении к `/mnt`, а не при загрузке.
- **NFSv3** обеспечивается опцией `vers=3` в fstab; в выводе `mount` видно `vers=3`
  и `mountvers=3`.
- Экспорт ограничен конкретным IP клиента (`192.168.1.233/32`) и использует
  `root_squash` (root клиента отображается в `nobody`), поэтому в `upload` права
  выданы `0777`, а владелец каталога — `nobody:nogroup`.
- Каталог `/srv/share` экспортируется целиком; подкаталог `upload` доступен на
  клиенте как `/mnt/upload`.
- Все шаги вынесены в два идемпотентных bash-скрипта `nfss_script.sh` и
  `nfsc_script.sh` (принимают IP второй стороны аргументом).

### ⭐ Kerberos + NFSv4 (сделано)

Развёрнут Kerberos-рейлм **`OTUS.LOCAL`** (KDC на bellona) и NFSv4 с аутентификацией
`sec=krb5`. Дополнительно к базовому экспорту создан отдельный каталог
`/srv/krb5share` с `sec=krb5`, клиент монтирует его через NFSv4.

Сервер (bellona):

```bash
apt install krb5-kdc krb5-admin-server krb5-user
kdb5_util create -s -r OTUS.LOCAL -P <master>
systemctl enable --now krb5-kdc krb5-admin-server
# принципалы:
kadmin.local -q "addprinc -randkey nfs/bellona.otus.local"
kadmin.local -q "addprinc -randkey nfs/irida.otus.local"
kadmin.local -q "addprinc -randkey host/bellona.otus.local"
kadmin.local -q "addprinc -randkey host/irida.otus.local"
kadmin.local -q "addprinc -pw <userpw> adrianl"
kadmin.local -q "ktadd -k /etc/krb5.keytab nfs/bellona.otus.local"
kadmin.local -q "ktadd -k /etc/krb5.keytab host/bellona.otus.local"
# keytab клиента: ktadd -k /root/irida.keytab nfs/irida.otus.local host/irida.otus.local

# экспорт с kerberos:
echo "/srv/krb5share 192.168.1.233/32(rw,sync,no_subtree_check,root_squash,sec=krb5)" >> /etc/exports
exportfs -r
```

Клиент (irida):

```bash
apt install krb5-user nfs-common
install -m600 -o root -g root /root/irida.keytab /etc/krb5.keytab   # ключи с сервера
echo 0 > /sys/module/nfs/parameters/nfs4_disable_idmapping          # + /etc/modprobe.d/krb5
kinit adrianl@OTUS.LOCAL
mount -t nfs4 -o vers=4.2,sec=krb5 192.168.1.200:/srv/krb5share /mnt/krb5
```

Результат монтирования:

```
192.168.1.200:/srv/krb5share on /mnt/krb5 type nfs4 (rw,relatime,vers=4.2,rsize=524288,
  wsize=524288,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=krb5,
  clientaddr=192.168.1.233,local_lock=none,addr=192.168.1.200)
```

Запись от имени аутентифицированного пользователя `adrianl@OTUS.LOCAL` проходит, файл на
сервере принадлежит `adrianl` (uid 1000) — ID-mapping NFSv4 работает:

```
# на сервере:
-rw-rw-r-- 1 1000 1000 0 Sep 27 23:52 map_test3
```

**Особенность:** в Ubuntu 24.04 по умолчанию включён
`nfs4_disable_idmapping=Y`, из-за чего все объекты отдавались как `nobody` (65534).
Пришлось выставить `nfs4_disable_idmapping=0` на сервере (`/sys/module/nfsd/...` +
`/etc/modprobe.d/nfsd-idmap.conf`) и на клиенте (`/sys/module/nfs/...` +
`/etc/modprobe.d/nfs-idmap.conf`), а также задать `Domain`/`Local-Realms` в
`/etc/idmapd.conf`.

## Заметки

- При оформлении использован адрес клиента `192.168.1.233`; при смене DHCP-адреса
  клиента нужно поправить `/etc/exports` на сервере.
- Логи `nfs_client.log` и `nfs_server.log` содержат полный вывод установки пакетов.
