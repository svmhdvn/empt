#!/bin/sh

set -eu

# Notes:
# * must be run as root

ABI=FreeBSD:15:amd64
ORG_DOMAIN=empt.siva
RESPONSIBILITY=primary

# TODO generate from ORG_DOMAIN
REALM=EMPT.SIVA

# $1 = src
# $2 = dest
_copytree() {
    (cd "$1" && find . -type d -exec mkdir -p "$2/{}" \;)
    for f in $(find "$1" -type -f | sed "s,^$1/,,g"); do
        sed \
            -e "s,%%ORG_DOMAIN%%,${ORG_DOMAIN},g" \
            -e "s,%%RESPONSIBILITY%%,${RESPONSIBILITY},g" \
            "$1/${f}" > "$2/${f}"
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
}
