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
ORG_DOMAIN=katcheri.org
RESPONSIBILITY=primary

# TODO query this programmatically
ULA_PREFIX=fd1a:7e1:6fdd

REALM="$(echo "${ORG_DOMAIN}" | tr '[:lower:]' '[:upper:]')"

JAILS='dns kerberos mail cifs irc www acme'
SERVICE_PRINCIPALS='cifs/cifs smtp/mail imap/mail HTTP/mail host/irc'
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

    install -m 0700 pkg-repos.conf /usr/local/etc/pkg/repos/empt.conf

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
    service ipfw restart

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
        /empt/synced/rw/logs \
        /empt/synced/rw/acme

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
    _truncate_dirs /empt/jails/mail/var/db/acme
    _append_if_missing \
        "/empt/synced/rw/acme/${ORG_DOMAIN}_ecc /empt/jails/mail/var/db/acme nullfs ro,noatime 0 0" \
        /empt/synced/rw/fstab.d/mail.fstab

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

    pkg -r /empt/jails/mail install -y \
        postfix mlmmj cyrus-imapd310 cyrus-sasl-gssapi cyrus-sasl-saslauthd \
        rspamd redis
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

    _copytree redis /empt/jails/mail/usr/local/etc
    _copytree rspamd /empt/jails/mail/usr/local/etc/rspamd/local.d

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
        /var/db/cyrusimap \
        /var/spool/cyrusimap \
        /var/run/cyrusimap


#===============
# RSPAMD AND DKIM STUFF
#===============
    jexec -l mail install -d -o redis -g redis \
        /var/log/redis \
        /var/db/redis \
        /var/run/redis
    jexec -l mail install -d -o redis -g rspamd -m 0775 /var/run/redis-rspamd
    jexec -l mail install -d -o rspamd -g rspamd -m 0700 "/var/db/opendkim/${ORG_DOMAIN}"
    # TODO change to ed25519 keys once every major provider supports verification
    jexec -l mail rspamadm dkim_keygen -s key1 -d "${ORG_DOMAIN}" -b 2048 \
        -k "/var/db/opendkim/${ORG_DOMAIN}/key1.private" \
        > "/empt/jails/mail/var/db/opendkim/${ORG_DOMAIN}/key1.txt"

    echo "key1._domainkey.${ORG_DOMAIN} ${ORG_DOMAIN}:key1:/var/db/opendkim/${ORG_DOMAIN}/key1.private" \
        > /empt/jails/mail/var/db/opendkim/dkim.keytable
    echo "*@${ORG_DOMAIN} key1._domainkey.${ORG_DOMAIN}" \
        > /empt/jails/mail/var/db/opendkim/dkim.signingtable
    jexec -l mail chown rspamd:rspamd \
        /var/db/opendkim/dkim.keytable \
        /var/db/opendkim/dkim.signingtable

    sysrc -j mail redis_profiles="rspamd-bayes rspamd-other"
    for s in saslauthd imapd redis rspamd postfix cron; do
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
    pkg -r /empt/jails/irc install -y ngircd soju nginx-lite
    service -j irc ldconfig start

    soju_uid="$(pw -R /empt/jails/irc usershow soju | cut -d: -f3)"
    install -d -o "${soju_uid}" -g "${soju_uid}" -m 0755 /empt/synced/rw/sojudb
    _truncate_dirs \
        /empt/jails/irc/var/db/soju \
        /empt/jails/irc/var/db/acme
    _append_if_missing \
        '/empt/synced/rw/sojudb /empt/jails/irc/var/db/soju nullfs rw,noatime 0 0' \
        /empt/synced/rw/fstab.d/irc.fstab
    _append_if_missing \
        "/empt/synced/rw/acme/${ORG_DOMAIN}_ecc /empt/jails/irc/var/db/acme nullfs ro,noatime 0 0" \
        /empt/synced/rw/fstab.d/irc.fstab
    mount -aF /empt/synced/rw/fstab.d/irc.fstab

    _copytree ngircd /empt/jails/irc/usr/local/etc/ngircd
    _copytree soju /empt/jails/irc/usr/local/etc/soju

    # TODO change this to 'soju' when it supports specifying service name
    cat > /empt/jails/irc/etc/pam.d/login <<EOF
auth required pam_krb5.so no_user_check
account sufficient pam_permit.so
EOF

    jexec -l irc chown soju:soju /etc/krb5.keytab

    for s in ngircd soju nginx; do
        service -j irc "${s}" enable
        service -j irc "${s}" start
    done
}

init_jail_www() {
    pkg -r /empt/jails/www install -y nginx-lite
    service -j www ldconfig start

    _truncate_dirs /empt/jails/www/var/db/acme
    _append_if_missing \
        "/empt/synced/rw/acme/${ORG_DOMAIN}_ecc /empt/jails/www/var/db/acme nullfs ro,noatime 0 0" \
        /empt/synced/rw/fstab.d/www.fstab
    mount -aF /empt/synced/rw/fstab.d/www.fstab

    _copytree nginx /empt/jails/www/usr/local/etc/nginx

    _truncate_dirs /empt/jails/www/usr/local/www
    cp -R gamja /empt/jails/www/usr/local/www/gamja

    service -j www nginx enable
    service -j www nginx start
}

init_jail_acme() {
    pkg -r /empt/jails/acme install -y acme.sh
    service -j acme ldconfig start

    _truncate_dirs /empt/jails/www/var/db/acme
    _append_if_missing \
        "/empt/synced/rw/acme /empt/jails/acme/var/db/acme nullfs rw,noatime 0 0" \
        /empt/synced/rw/fstab.d/acme.fstab
    mount -aF /empt/synced/rw/fstab.d/acme.fstab

    # TODO replace with production once working
    jexec -l acme acme.sh --home /var/db/acme --set-default-ca --server letsencrypt_test
    jexec -l acme acme.sh --home /var/db/acme --issue --standalone \
        -d "${ORG_DOMAIN}" \
        -d "mail.${ORG_DOMAIN}" \
        -d "www.${ORG_DOMAIN}" \
        -d "irc.${ORG_DOMAIN}"
    chmod 0644 "/empt/synced/rw/acme/${ORG_DOMAIN}_ecc/${ORG_DOMAIN}.key"

    _append_if_missing \
        '35 4 * * * root -n -q acme.sh --home /var/db/acme --renew' \
        /etc/crontab

    service -j acme cron enable
    service -j acme cron start
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
        --user empthelper \
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
            --user "${username}" \
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
        init_jail_acme
        init_jail_mail
        init_jail_cifs
        init_jail_irc
        init_jail_www
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
