#!/bin/sh

set -eux

# Notes:
# * must be run as root
# * 1xxx UIDs are for EMPT system users
# * 2xxx+ UIDs are for EMPT human users

# TODO:
# * add validation to every service's config files

TABCHAR='	'

ABI=FreeBSD:15:amd64
ORG_DOMAIN=empt.siva
RESPONSIBILITY=primary

# TODO query this programmatically
IPV4_PREFIX=10.66.199
ULA_PREFIX=fd1a:7e1:6fdd

# TODO generate from ORG_DOMAIN
REALM=EMPT.SIVA

JAILS='dns kerberos mail cifs irc'
SERVICE_PRINCIPALS='cifs/cifs smtp/mail imap/mail HTTP/mail irc/irc'
KEYTABS='cifs mail irc'

HELPDESK_UID=1001
MLMMJ_UID=1002

_random_password() {
    LC_CTYPE=C tr -cd '[:graph:]' < /dev/random | head -c 16
}

# $@ = dirs
_truncate_dirs() {
    rm -rf "$@"
    mkdir -p "$@"
}

# $1 = line
# $2 = file
_append_if_missing() {
    grep -qxF "$1" "$2" || echo "$1" >> "$2"
}

# TODO read all variables from a file
# $1 = src
# $2 = dest
_template() {
    mkdir -p "${2%/*}"
    sed \
        -e "s,%%ORG_DOMAIN%%,${ORG_DOMAIN},g" \
        -e "s,%%REALM%%,${REALM},g" \
        -e "s,%%RESPONSIBILITY%%,${RESPONSIBILITY},g" \
        -e "s,%%IPV4_PREFIX%%,${IPV4_PREFIX},g" \
        -e "s,%%ULA_PREFIX%%,${ULA_PREFIX},g" \
        "$1" > "$2"
}

# $1 = src
# $2 = dest
_copytree() {
    (
        cd "$1"
        tree_files="$(find . -type f)"
        while IFS= read -r f; do
            _template "${f}" "$2/${f%%.in}"
        done <<EOF
${tree_files}
EOF
    )
}

factory_reset() {
    bectl activate default
}

# create a boot environment for a fresh EMPT setup
fresh_boot_environment() {
    bectl destroy empt_fresh || true
    zfs destroy -Rf zroot/empt || true
    bectl create empt_fresh
    bectl activate empt_fresh
}

# setup poudriere repos
upgrade_to_poudriere() {
    # cleanup stale repos
    _truncate_dirs \
        /usr/local/etc/pkg/repos \
        /usr/local/poudriere_repos/host_pkgbase \
        /usr/local/poudriere_repos/jail_pkgbase \
        /usr/local/poudriere_repos/ports

    tar -C /usr/local/poudriere_repos/host_pkgbase -xf wyse-host-pkgbase.tar.zst
    tar -C /usr/local/poudriere_repos/jail_pkgbase -xf wyse-jail-pkgbase.tar.zst
    tar -C /usr/local/poudriere_repos/ports -xf wyse-ports.tar.zst

    install -m 0700 empt-repos.conf /usr/local/etc/pkg/repos/empt.conf

    ABI="${ABI}" IGNORE_OSVERSION=yes pkg install -y -r host_pkgbase -g 'FreeBSD-*'
    # TODO find a better solution to keep important files
    for f in /etc/master.passwd /etc/group /etc/sysctl.conf /etc/ssh/sshd_config; do
        test -f "${f}.pkgsave" && cp "${f}.pkgsave" "${f}"
    done
    pwd_mkdb -p /etc/master.passwd
    find / -type f -name '*.pkgsave' -delete || true

    pkg upgrade -y -r ports
}

prep_jailhost() {
    pkg install -y \
        tmux htop tree curl \
        cpu-microcode fdm empt-scripts
    cp tmux.conf ~/.tmux.conf

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

    _truncate_dirs \
        /empt/jails \
        /empt/synced/etc \
        /empt/synced/rw/fstab.d \
        /empt/synced/rw/groups \
        /empt/synced/rw/humans \
        /empt/synced/rw/logs

    for j in ${JAILS}; do
        cp -a /tmp/base_jail/etc "/empt/synced/etc/${j}"
    done
    _truncate_dirs /tmp/base_jail/etc

    for j in ${JAILS}; do
        cp -a /tmp/base_jail "/empt/jails/${j}"
        touch "/empt/synced/rw/fstab.d/${j}.fstab"
    done
    chflags -R 0 /tmp/base_jail
    rm -rf /tmp/base_jail

    mount -al

    ca_key_path="/empt/synced/rw/${ORG_DOMAIN}_PRIVATE_CA.key.pem"
    ca_crt_path="/usr/local/etc/ssl/certs/${ORG_DOMAIN}_PRIVATE_CA.crt.pem"
    _truncate_dirs /usr/local/etc/ssl/certs
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -nodes \
        -keyout "${ca_key_path}" \
        -out "${ca_crt_path}" \
        -subj "/CN=${ORG_DOMAIN}" \
        -addext "subjectAltName=DNS:${ORG_DOMAIN}" \
        -addext "keyUsage=keyCertSign,cRLSign"
    certctl rehash

    for j in ${JAILS}; do
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -CAkey "${ca_key_path}" -CA "${ca_crt_path}" \
            -days 90 -nodes \
            -keyout "/empt/jails/${j}/etc/ssl/${j}.key.pem" \
            -out "/empt/jails/${j}/etc/ssl/${j}.crt.pem" \
            -subj "/CN=${j}.${ORG_DOMAIN}" \
            -addext "basicConstraints=critical,CA:false" \
            -addext "subjectAltName=DNS:${j}.${ORG_DOMAIN}"
    done
    service jail onerestart
}

init_jail_dns() {
    pkg -r /empt/jails/dns install -y unbound
    service -j dns ldconfig start

    _copytree unbound /empt/jails/dns/usr/local/etc/unbound
    service -j dns unbound enable
    service -j dns unbound start
}

init_jail_kerberos() {
    _copytree kerberos_etc /empt/jails/kerberos/etc
    _truncate_dirs \
        /empt/jails/kerberos/var/heimdal \
        /empt/synced/rw/krb5data
    _append_if_missing \
        '/empt/synced/rw/krb5data /empt/jails/kerberos/var/heimdal nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/kerberos.fstab
    mount -aF /empt/synced/rw/fstab.d/kerberos.fstab

    jexec -l kerberos kstash --random-key
    jexec -l kerberos kadmin -l init \
        --realm-max-renewable-life=1w \
        --realm-max-ticket-life=1w \
        "${REALM}"

    for p in ${SERVICE_PRINCIPALS}; do
        jexec -l kerberos kadmin -l add --random-key --use-defaults "${p}.${ORG_DOMAIN}"
    done
    for k in ${KEYTABS}; do
        jexec -l kerberos kadmin -l ext_keytab --keytab="/tmp/${k}.keytab" "*/${k}.${ORG_DOMAIN}"
        mv "/empt/jails/kerberos/tmp/${k}.keytab" "/empt/jails/${k}/etc/krb5.keytab"
    done
    for s in kdc kpasswdd; do
        service -j kerberos "${s}" enable
        service -j kerberos "${s}" start
    done
}

init_jail_mail() {
#===============
# SMTP STUFF
#===============
    mkdir -p \
        /empt/synced/postfix_spool \
        /empt/jails/mail/var/spool/postfix
    _append_if_missing \
        '/empt/synced/postfix_spool /empt/jails/mail/var/spool/postfix nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/mail.fstab

    pw -R /empt/jails/mail \
        useradd mlmmj -u "${MLMMJ_UID}" -c 'mlmmj manager' -d /var/spool/mlmmj -s /usr/sbin/nologin -h -
    install -d -o "${MLMMJ_UID}" -g "${MLMMJ_UID}" \
        /empt/synced/rw/mlmmj_spool \
        /empt/jails/mail/var/spool/mlmmj
    _append_if_missing \
        '/empt/synced/rw/mlmmj_spool /empt/jails/mail/var/spool/mlmmj nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/mail.fstab

    mount -aF /empt/synced/rw/fstab.d/mail.fstab

    pkg -r /empt/jails/mail install -y postfix mlmmj
    service -j mail ldconfig start

    _copytree postfix /empt/jails/mail/usr/local/etc/postfix
    touch \
        /empt/jails/mail/usr/local/etc/postfix/mlmmj_aliases \
        /empt/jails/mail/usr/local/etc/postfix/mlmmj_transport
    jexec -l mail postmap /usr/local/etc/postfix/mlmmj_aliases
    jexec -l mail postmap /usr/local/etc/postfix/mlmmj_transport
    jexec -l mail postalias cdb:/etc/mail/aliases
    jexec -l mail postfix set-permissions

    mkdir -p /empt/jails/mail/usr/local/etc/sasl2
    echo 'pwcheck_method: auxprop saslauthd' \
        > /empt/jails/mail/usr/local/etc/sasl2/smtpd.conf
    jexec -l mail chown postfix:postfix /etc/krb5.keytab
    echo '* * * * * -n -q /usr/local/bin/mlmmj-maintd -F -d /var/spool/mlmmj' \
        > /empt/jails/mail/var/cron/tabs/mlmmj

#===============
# IMAP STUFF
#===============
    mkdir -p \
        /empt/synced/rw/cyrusimap/db \
        /empt/synced/rw/cyrusimap/spool \
        /empt/jails/mail/var/db/cyrusimap \
        /empt/jails/mail/var/spool/cyrusimap \
        /empt/jails/mail/var/run/cyrusimap
    _append_if_missing \
        '/empt/synced/rw/cyrusimap/db /empt/jails/mail/var/db/cyrusimap nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/mail.fstab
    _append_if_missing \
        '/empt/synced/rw/cyrusimap/spool /empt/jails/mail/var/spool/cyrusimap nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/mail.fstab
    mount -aF /empt/synced/rw/fstab.d/mail.fstab

    pkg -r /empt/jails/mail install -y cyrus-imapd310
    service -j mail ldconfig start

    _copytree cyrus /empt/jails/mail/usr/local/etc
    jexec -l mail /usr/local/cyrus/sbin/mkimap

    for s in smtp imap HTTP; do
        cat > "/empt/jails/mail/etc/pam.d/${s}" <<EOF
auth required pam_krb5.so no_user_check
account sufficient pam_permit.so
EOF
    done

    jexec -l mail chown -R cyrus:mail \
        /etc/krb5.keytab \
        /etc/ssl/mail.crt.pem \
        /etc/ssl/mail.key.pem \
        /var/db/cyrusimap \
        /var/spool/cyrusimap \
        /var/run/cyrusimap

    for s in saslauthd imapd postfix cron; do
        service -j mail "${s}" enable
        service -j mail "${s}" start
    done
}

init_jail_cifs() {
    pkg -r /empt/jails/cifs install -y samba419
    service -j cifs ldconfig start

    install -d -o root -g wheel -m 1755 /empt/jails/cifs/groups
    _template smb4.conf.in /empt/jails/cifs/usr/local/etc/smb4.conf
    sysrc -j cifs nmbd_enable=NO
    service -j cifs samba_server enable
    service -j cifs samba_server start
}

init_jail_irc() {
    pkg -r /empt/jails/irc install -y ngircd soju kimchi tlstunnel
    service -j irc ldconfig start

    mkdir -p \
        /empt/synced/rw/sojudb \
        /empt/jails/irc/var/db/soju
    _append_if_missing \
        '/empt/synced/rw/sojudb /empt/jails/irc/var/db/soju nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/irc.fstab
    mount -aF /empt/synced/rw/fstab.d/irc.fstab

    _copytree soju /empt/jails/irc/usr/local/etc/soju
    _copytree kimchi /empt/jails/irc/usr/local/etc/kimchi
    _copytree tlstunnel /empt/jails/irc/usr/local/etc/tlstunnel

    # TODO remove the chmod after upstream patch is merged
    _copytree ngircd /empt/jails/irc/usr/local/etc/ngircd
    chmod 0644 /empt/jails/irc/usr/local/etc/ngircd/ngircd.conf

    # TODO change this to 'soju' when it supports specifying service name
    cat > /empt/jails/irc/etc/pam.d/login <<EOF
auth required pam_krb5.so no_user_check
account sufficient pam_permit.so
EOF

    jexec -l irc chown soju:soju \
        /etc/krb5.keytab \
        /etc/ssl/irc.crt.pem \
        /etc/ssl/irc.key.pem

    _truncate_dirs /empt/jails/irc/usr/local/www
    cp -R gamja /empt/jails/irc/usr/local/www/gamja
    sysrc -j irc \
        kimchi_user=root kimchi_group=wheel \
        tlstunnel_user=root tlstunnel_group=wheel

    for s in ngircd soju kimchi tlstunnel; do
        service -j irc "${s}" enable
        service -j irc "${s}" start
    done
}

create_mailing_lists() {
    while read -r m; do
        sed \
            -e "s,%%ORG_DOMAIN%%,${ORG_DOMAIN},g" \
            -e "s,%%LISTNAME%%,${m},g" \
            mlmmj-answers.txt.in > /empt/jails/mail/tmp/mlmmj-answers.txt

        jexec -l -U mlmmj mail /usr/local/bin/mlmmj-make-ml -f /tmp/mlmmj-answers.txt
        echo mail.home.arpa > "/empt/jails/mail/var/spool/mlmmj/${m}/control/relayhost"
        touch "/empt/jails/mail/var/spool/mlmmj/${m}/control/tocc"
        echo "${m}@${ORG_DOMAIN} ${m}@localhost.mlmmj" >> /empt/jails/mail/usr/local/etc/postfix/mlmmj_aliases
        echo "${m}@localhost.mlmmj mlmmj:${m}" >> /empt/jails/mail/usr/local/etc/postfix/mlmmj_transport
    done < mailing_lists.txt

    jexec -l mail postmap /usr/local/etc/postfix/mlmmj_aliases
    jexec -l mail postmap /usr/local/etc/postfix/mlmmj_transport
}

open_helpdesk() {
    pw useradd empthelper -u "${HELPDESK_UID}" -c 'EMPT helpdesk agent' -d /empt/synced/rw/helpdesk -s /usr/sbin/nologin -h -
    pw -R /empt/jails/mail useradd empthelper -u "${HELPDESK_UID}" -c 'EMPT helpdesk agent' -d /nonexistent -s /usr/sbin/nologin -h -

    # TODO secure
    jexec -l kerberos kadmin -l add --use-defaults --password=empthelper empthelper
    echo cm INBOX | jexec -l mail cyradm \
        --server mail.home.arpa \
        --port 143 \
        --user "empthelper@${ORG_DOMAIN}" \
        --auth PLAIN \
        --password empthelper

    touch \
        /empt/jails/mail/var/spool/mlmmj/helpdesk/control/closedlist \
        /empt/jails/mail/var/spool/mlmmj/helpdesk/control/noget \
        /empt/jails/mail/var/spool/mlmmj/helpdesk/control/notifymod \
        /empt/jails/mail/var/spool/mlmmj/helpdesk/control/notmetoo
    echo "it@${ORG_DOMAIN}" > /empt/jails/mail/var/spool/mlmmj/helpdesk/control/moderators
    cat > /empt/jails/mail/var/spool/mlmmj/helpdesk/control/access <<EOF
allow ^subject:[ \t]*(list|show)[ \t]*group
allow ^subject:[ \t]*(show|display|my)[ \t]*(dashboard|summary)
moderate
EOF
    jexec -l -U mlmmj mail \
        /usr/local/bin/mlmmj-sub -L /var/spool/mlmmj/helpdesk -a "empthelper@${ORG_DOMAIN}" -fqs
    _append_if_missing \
        'permit nopass empthelper cmd /usr/local/libexec/empt/helpdesk' \
        /usr/local/etc/doas.conf

    _template fdm.conf.in /empt/synced/rw/helpdesk/.fdm.conf
    chmod 0600 /empt/synced/rw/helpdesk/.fdm.conf
    chown empthelper:empthelper /empt/synced/rw/helpdesk/.fdm.conf
    _append_if_missing \
        '* * * * * -q fdm -q fetch' \
        /var/cron/tabs/empthelper
}

start_monitor() {
    pw useradd emptmonitor -c 'EMPT monitoring agent' -d /nonexistent -s /usr/sbin/nologin -h -
    _append_if_missing \
        'permit nopass emptmonitor cmd /usr/local/libexec/empt/monitor' \
        /usr/local/etc/doas.conf
    _append_if_missing \
        '* * * * * -n -q /usr/local/libexec/empt/monitor every_minute' \
        /var/cron/tabs/emptmonitor
    _append_if_missing \
        '0 * * * * -n -q /usr/local/libexec/empt/monitor every_hour' \
        /var/cron/tabs/emptmonitor
    _append_if_missing \
        '0 0 * * * -n -q /usr/local/libexec/empt/monitor every_day' \
        /var/cron/tabs/emptmonitor
}

hire_humans() {
    while IFS="${TABCHAR}" read -r username fullname uid lists; do
        cifs_userhome="/empt/jails/cifs/home/${username}"
        pw -R /empt/jails/cifs useradd "${username}" -u "${uid}" -c "${fullname}" -d "${cifs_userhome}" -s /usr/sbin/nologin -h -
        #pw -R /empt/jails/mail useradd "${username}" -u "${uid}" -c "${fullname}" -d /nonexistent -s /usr/sbin/nologin -h -

        # TODO change mountpoint into a nullfs mount if needed
        install -d -o "${uid}" -g "${uid}" -m 0700 "${cifs_userhome}"
        zfs create \
            -o quota=1G \
            -o reservation=1G \
            -o "mountpoint=${cifs_userhome}" \
            "zroot/empt/synced/rw/human:${username}"

        # TODO secure password
        jexec -l kerberos kadmin -l add --use-defaults --password="${username}" "${username}"
        echo cm INBOX | jexec -l mail cyradm \
            --server mail.home.arpa \
            --port 143 \
            --user "${username}@${ORG_DOMAIN}" \
            --auth PLAIN \
            --password "${username}"

        for l in ${lists}; do
            jexec -l -U mlmmj mail \
                /usr/local/bin/mlmmj-sub -L "/var/spool/mlmmj/${l}" -a "${username}@${ORG_DOMAIN}" -cfs
        done
    done < humans.tsv
}

case "$1" in
    0)
        factory_reset
        ;;
    1)
        fresh_boot_environment
        ;;
    2)
        upgrade_to_poudriere
        ;;
    3)
        prep_jailhost
        init_jail_dns
        init_jail_kerberos
        init_jail_mail
        init_jail_cifs
        init_jail_irc
        create_mailing_lists
        open_helpdesk
        start_monitor
        hire_humans
        ;;
    *)
        echo "ERROR: Unrecognized boot sequence number '$1'" >&2
        exit 64 # EX_USAGE
esac
reboot
