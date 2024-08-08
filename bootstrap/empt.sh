#!/bin/sh

set -eu

# Notes:
# * must be run as root

# TODO:
# * add validation to every service's config files

ABI=FreeBSD:15:amd64
ORG_DOMAIN=empt.siva
RESPONSIBILITY=primary

# TODO generate from ORG_DOMAIN
REALM=EMPT.SIVA

JAILS='kerberos smtp imap cifs irc'
SERVICE_PRINCIPALS='cifs/cifs smtp/smtp imap/imap HTTP/imap irc/irc'
KEYTABS='cifs smtp imap irc'

# $1 = dir
_truncate_dir() {
    rm -rf "$1"
    mkdir -p "$1"
}

# $1 = line
# $2 = file
_append_if_missing() {
    grep -qxF "$1" "$2" || echo "$1" >> "$2"
}

# $1 = src
# $2 = dest
_template() {
    sed \
        -e "s,%%ORG_DOMAIN%%,${ORG_DOMAIN},g" \
        -e "s,%%REALM%%,${REALM},g" \
        -e "s,%%RESPONSIBILITY%%,${RESPONSIBILITY},g" \
        "$1" > "$2"
}

# $1 = src
# $2 = dest
_copytree() {
    (cd "$1" && find . -type d -exec mkdir -p "$2/{}" \;)
    for f in $(find "$1" -type -f | sed "s,^$1/,,g"); do
        _template "$1/${f}" "$2/${f}"
    done
}

# create a boot environment for a fresh EMPT setup
boot1() {
    bectl create empt_fresh
    bectl activate empt_fresh

    reboot
}

# setup poudriere repos
boot2() {
    # cleanup stale repos
    rm -rf /usr/local/poudriere_repos
    install -d -m 0700 \
        /usr/local/etc/pkg/repos \
        /usr/local/poudriere_repos/host_pkgbase \
        /usr/local/poudriere_repos/jail_pkgbase \
        /usr/local/poudriere_repos/ports

    # TODO scp the poudriere tarballs to /tmp

    tar -C /usr/local/poudriere_repos/host_pkgbase -xf /tmp/wyse-host-pkgbase.tar.zst
    tar -C /usr/local/poudriere_repos/jail_pkgbase -xf /tmp/wyse-jail-pkgbase.tar.zst
    tar -C /usr/local/poudriere_repos/ports -xf /tmp/wyse-ports.tar.zst

    install -m 0700 empt-repos.conf /usr/local/etc/pkg/repos/empt.conf

    ABI="${ABI}" IGNORE_OSVERSION=yes pkg install -y -r host_pkgbase -g 'FreeBSD-*'
    cp /etc/master.passwd.pkgsave /etc/master.passwd
    cp /etc/group.pkgsave /etc/group
    cp /etc/sysctl.conf.pkgsave /etc/sysctl.conf
    pwd_mkdb -p /etc/master.passwd
    find / -type f -name '*.pkgsave' -delete

    pkg upgrade -y -f -r ports

    reboot
}

init_jail_kerberos() {
    _copytree kerberos_etc /empt/jails/kerberos/etc
    _truncate_dir /empt/jails/kerberos/var/heimdal
    mkdir -p /empt/synced/rw/krb5data
    _append_if_missing \
        '/empt/synced/rw/krb5data /empt/jails/kerberos/var/heimdal nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/kerberos.fstab
    mount -aF /empt/synced/rw/fstab.d/kerberos.fstab

    jexec -l kerberos kstash --random-key
    jexec -l kerberos kadmin -l init --realm-max-renewable-life=1w "${REALM}"

    for p in ${SERVICE_PRINCIPALS}; do
        jexec -l kerberos kadmin -l add --random-key --use-defaults "${p}.${ORG_DOMAIN}"
    done
    for k in ${KEYTABS}; do
        jexec -l kerberos kadmin -l ext_keytab --keytab="/tmp/${k}.keytab" "*/${k}.${ORG_DOMAIN}"
        mv "/empt/jails/kerberos/tmp/${k}.keytab" "/empt/jails/${k}/etc/krb5.keytab"
    done
    for s in kdc kpasswd; do
        service -j kerberos enable "${s}"
    done
}

init_jail_smtp() {
    mkdir -p \
        /empt/synced/postfix_spool \
        /empt/synced/rw/mlmmj_spool \
        /empt/jails/smtp/var/spool/mlmmj \
        /empt/jails/smtp/var/spool/postfix
    _append_if_missing \
        '/empt/synced/rw/mlmmj_spool /empt/jails/smtp/var/spool/mlmmj nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/smtp.fstab
    _append_if_missing \
        '/empt/synced/postfix_spool /empt/jails/smtp/var/spool/postfix nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/smtp.fstab
    mount -aF /empt/synced/rw/fstab.d/smtp.fstab

    pkg -r /empt/jails/smtp install -y postfix mlmmj
    service -j smtp ldconfig start

    _copytree postfix /empt/jails/smtp/usr/local/etc/postfix
    touch \
        /empt/jails/smtp/usr/local/etc/postfix/mlmmj_aliases \
        /empt/jails/smtp/usr/local/etc/postfix/mlmmj_transport
    jexec -l smtp postmap /usr/local/etc/postfix/mlmmj_aliases
    jexec -l smtp postmap /usr/local/etc/postfix/mlmmj_transport
    jexec -l smtp postalias cdb:/etc/mail/aliases

    cat > /empt/jails/smtp/etc/pam.d/smtp <<EOF
auth required pam_krb5.so
account required pam_nologin.so
EOF

    mkdir -p /empt/jails/smtp/usr/local/etc/sasl2
    echo 'pwcheck_method: auxprop saslauthd' \
        > /empt/jails/smtp/usr/local/smtp/sasl2/smtpd.conf
    jexec -l smtp chown postfix:postfix /etc/krb5.keytab
    echo '* * * * * -n -q /usr/local/bin/mlmmj-maintd -F -d /var/spool/mlmmj' \
        > /empt/jails/smtp/var/cron/tabs/mlmmj
    for s in postfix saslauthd cron; do
        service -j smtp service "${s}" enable
    done
}

init_jail_imap() {
    mkdir -p
        /empt/synced/rw/cyrusimap/db \
        /empt/synced/rw/cyrusimap/spool \
        /empt/jails/var/db/cyrusimap \
        /empt/jails/var/spool/cyrusimap \
        /empt/jails/var/run/cyrusimap
    _append_if_missing \
        '/empt/synced/rw/cyrusimap/db /empt/jails/imap/var/db/cyrusimap nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/imap.fstab
    _append_if_missing \
        '/empt/synced/rw/cyrusimap/spool /empt/jails/imap/var/spool/cyrusimap nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/imap.fstab
    mount -aF /empt/synced/rw/fstab.d/imap.fstab

    pkg -r /empt/jails/smtp install -y cyrus-imapd38
    service -j imap ldconfig start
    for s in imap HTTP; do
        cat > "/empt/jails/imap/etc/pam.d/${s}" <<EOF
auth required pam_krb5.so
account required pam_nologin.so
EOF
    done

    jexec -l imap chown cyrus:cyrus \
        /etc/krb5.keytab \
        /etc/ssl/imap.crt.pem \
        /etc/ssl/imap.key.pem
    jexec -l imap chown -R cyrus:cyrus \
        /var/db/cyrusimap \
        /var/spool/cyrusimap \
        /var/run/cyrusimap
    for s in imapd saslauthd; do
        service -j imap service "${s}" enable
    done
}

init_jail_cifs() {
    pkg -r /empt/jails/cifs install -y samba419
    service -j imap ldconfig start

    install -d -o root -g wheel -m 1755 /empt/jails/cifs/groups
    _template smb4.conf.in /empt/jails/cifs/usr/local/etc/smb4.conf
    sysrc -j cifs nmbd_enable=NO
    service -j cifs samba_server enable

    jexec -l irc chown soju:soju \
        /etc/krb5.keytab \
        /etc/ssl/imap.crt.pem \
        /etc/ssl/imap.key.pem

    mkdir -p /usr/local/www
    cp -R gamja /usr/local/www/gamja
    sysrc -j irc \
        kimchi_user=root kimchi_group=wheel
        tlstunnel_user=root tlstunnel_group=wheel
    for s in ngircd soju kimchi tlstunnel; do
        service -j irc "${s}" enable
    done
}

init_jail_irc() {
    pkg -r /empt/jails/irc install -y ngircd soju kimchi tlstunnel
    service -j imap ldconfig start

    mkdir -p
        /empt/synced/rw/sojudb \
        /empt/jails/irc/var/db/soju
    _append_if_missing \
        '/empt/synced/rw/sojudb /empt/jails/irc/var/db/soju nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/irc.fstab
    mount -aF /empt/synced/rw/fstab.d/imap.fstab

    _copytree ngircd /empt/jails/irc/usr/local/etc/ngircd
    _copytree soju /empt/jails/irc/usr/local/etc/soju
    _copytree kimchi /empt/jails/irc/usr/local/etc/kimchi
    _copytree tlstunnel /empt/jails/irc/usr/local/etc/tlstunnel

    # TODO change this to 'soju' when it supports specifying service name
    cat > /empt/jails/irc/etc/pam.d/login <<EOF
auth required pam_krb5.so
account required pam_nologin.so
EOF
}

# setup convenience tools
boot3() {
    pkg install -y \
        tmux htop tree curl \
        cpu-microcode fdm empt-scripts
    install -o tester -g tester tmux.conf /home/tester/.tmux.conf

    sysrc -f /boot/loader.conf \
        cpu_microcode_load=YES \
        cpu_microcode_name=/boot/firmware/amd-ucode.bin

    _copytree jailhost_etc /etc

    mkdir -p /tmp/base_jail
    pkg -r /tmp/base_jail install -y -r jail_pkgbase -g 'FreeBSD-*'
    _copytree common_etc /tmp/base_jail/etc

    zfs create -o mountpoint=/empt zroot/empt
    zfs create zroot/empt/synced
    zfs create \
        -o exec=off \
        -o setuid=off \
        -o compression=zstd \
        zroot/empt/synced/rw

    mkdir -p \
        /empt/jails \
        /empt/synced/etc \
        /empt/synced/rw/fstab.d \
        /empt/synced/rw/groups \
        /empt/synced/rw/humans \
        /empt/synced/rw/logs \

    _copytree jail.conf.d /empt/synced/rw/jail.conf.d

    for j in ${JAILS}; do
        cp -a /tmp/base_jail/etc "/empt/synced/etc/${j}"
        #touch "/empt/synced/rw/fstab.d/${j}.fstab"
    done
    _truncate_dir /tmp/base_jail/etc

    for j in ${JAILS}; do
        cp -a /tmp/base_jail "/empt/jails/${j}"
    done
    chflags -R 0 /tmp/base_jail
    rm -rf /tmp/base_jail

    mount -al

    ca_key_path="/empt/synced/rw/${ORG_DOMAIN}_PRIVATE_CA.key.pem"
    ca_crt_path="/usr/local/etc/ssl/certs/${ORG_DOMAIN}_PRIVATE_CA.crt.pem"
    mkdir -p /usr/local/etc/ssl/certs
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -nodes \
        -keyout "${ca_key_path}" \
        -out "${ca_crt_path}" \
        -subj "/CN=${ORG_DOMAIN}" \
        -addext "subjectAltName=DNS:${ORG_DOMAIN}"
    certctl rehash

    for j in ${JAILS}; do
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -CAkey "${ca_key_path}" -CA "${ca_crt_path}" \
            -days 90 -nodes \
            -keyout "/empt/jails/${j}/etc/ssl/${j}.key.pem" \
            -out "/empt/jails/${j}/etc/ssl/${j}.crt.pem" \
            -subj "/CN=${j}.${ORG_DOMAIN}" \
            -addext "subjectAltName=DNS:${j}.${ORG_DOMAIN}"
    done

    init_jail_kerberos
    init_jail_smtp
    init_jail_imap
    init_jail_cifs
    init_jail_irc
}
