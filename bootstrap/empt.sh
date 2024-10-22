#!/bin/sh

set -eux

# Notes:
# * must be run as root
# * 1xxx UIDs are for EMPT system users
# * 2xxx+ UIDs are for EMPT human users

# TODO:
# * add validation to every service's config files
# * move monitoring to its own user for security reasons

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
    _copytree jailhost_etc /etc
    service ipfw restart

    # TODO replace common_etc with these actions for each jail:
    # * generate hosts file
    # * generate krb5.conf
    # * disable (at least) dumpdev, syslogd, and cron
    # * point the DNS resolver at the DNS jail

    # TODO create fstab for every jail that needs it
    echo "${JAILS}" | xargs -J% -n1 touch /empt/synced/rw/fstab.d/%.fstab
}

init_jail_dns() {
    pkg -r /empt/jails/dns install -y unbound
    service -j dns ldconfig start

    _copytree unbound /empt/jails/dns/usr/local/etc/unbound
    service -j dns unbound enable
    service -j dns unbound start
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
    jexec -l mail install -d -o rspamd -g rspamd -m 0700 /var/db/opendkim

    echo "key1._domainkey.${ORG_DOMAIN} ${ORG_DOMAIN}:key1:/var/db/opendkim/${ORG_DOMAIN}/key1.private" \
        > /empt/jails/mail/var/db/opendkim/dkim.keytable
    echo "*@${ORG_DOMAIN} key1._domainkey.${ORG_DOMAIN}" \
        > /empt/jails/mail/var/db/opendkim/dkim.signingtable

    # TODO reenable once testing is done with FreeDNS DKIM keys
    # =========================================================
    # TODO change to ed25519 keys once every major provider supports verification
    #jexec -l mail rspamadm dkim_keygen -s key1 -d "${ORG_DOMAIN}" -b 2048 \
    #    -k "/var/db/opendkim/${ORG_DOMAIN}/key1.private" \
    #    > "/empt/jails/mail/var/db/opendkim/${ORG_DOMAIN}/key1.txt"
    _copytree testing_dkim "/empt/jails/mail/var/db/opendkim/${ORG_DOMAIN}"
    # =========================================================

    jexec -l mail chown -R rspamd:rspamd /var/db/opendkim

    sysrc -j mail redis_profiles="rspamd-bayes rspamd-other"
    for s in saslauthd imapd redis rspamd postfix cron; do
        service -j mail "${s}" enable
        service -j mail "${s}" start
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
        pkg -r /empt/jails/dns install -y empt-jail-dns
        pkg -r /empt/jails/kerberos install -y empt-jail-kerberos
        # TODO run ACME in host and place certs for each jail in their own /var/db/tls directories
        # pkg -r /empt/jails/acme install -y empt-jail-acme
        init_jail_mail
        pkg -r /empt/jails/cifs install -y empt-jail-cifs
        pkg -r /empt/jails/irc install -y empt-jail-irc
        pkg -r /empt/jails/www install -y empt-jail-www
        create_mailing_lists
        hire_humans

        # open the helpdesk
        pkg install -y empt-helpdesk
        ;;
    *)
        echo "ERROR: Unrecognized boot sequence number '$1'" >&2
        exit 64 # EX_USAGE
esac
reboot
