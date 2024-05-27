#!/bin/sh

set -e

_usage() {
    echo "usage: downtime.sh <planned|emergency> <failover|takeover>"
}

_failover() {
    # lock all EMPT robots
    # TODO idempotency
    awk -F: '$1 ~ /^empt/ { print $1 }' /etc/passwd | xargs -L1 pw lock || true

    # stop all jails
    service jail onestop

    # failover with zrep to the secondary host (locally if recovering from emergency)
    # TODO idempotency
    zrep list | xargs -L1 zrep failover ${emergency:+-L} || true

    # unmount the entire EMPT zfs tree
    # TODO idempotency
    zfs unmount zroot/empt || true
}

_takeover() {
    # mount the entire EMPT zfs tree
    zfs mount -R zroot/empt

    # takeover from the primary that is down in an emergency
    # TODO idempotency
    if test $emergency = 1; then
        zrep list | xargs -L1 zrep takeover -L || true
    fi

    # start all jails
    service jail onestart

    # unlock all EMPT robots
    # TODO idempotency
    awk -F: '$1 ~ /^empt/ { print $1 }' /etc/passwd | xargs -L1 pw unlock || true
}

case $1 in
    planned) ;;
    emergency) emergency=1 ;;
    *)
        echo "unrecognized situation: '$1'" >&2
        _usage >&2
        exit 64 # EX_USAGE
esac

case $2 in
    failover) _failover ;;
    takeover) _takeover ;;
    *)
        echo "unrecognized action: '$2'" >&2
        _usage >&2
        exit 64 # EX_USAGE
esac
