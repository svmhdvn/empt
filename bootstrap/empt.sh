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

    # TODO Set user-provided details here
    sysrc \
        hostname="jailhost.${ORG_DOMAIN}" \
        cron_flags="-m it@${ORG_DOMAIN}"
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
        pkg install -y \
            empt-host-dns \
            empt-host-kerberos \
            empt-host-mail \
            empt-host-cifs \
            empt-host-irc \
            empt-host-www \
            empt-acme

        create_mailing_lists
        hire_humans

        # TODO open the helpdesk
        #pkg install -y empt-helpdesk
        ;;
    *)
        echo "ERROR: Unrecognized boot sequence number '$1'" >&2
        exit 64 # EX_USAGE
esac
reboot
