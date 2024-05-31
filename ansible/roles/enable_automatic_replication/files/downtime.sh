#!/bin/sh

_usage() {
    cat <<EOF
usage:
    downtime.sh failover|takeover
EOF
}

_failover() {
    # lock all EMPT robots
    # TODO idempotency
    awk -F: '$1 ~ /^empt/ { print $1 }' /etc/passwd | xargs -L1 pw lock || true

    # stop all jails
    service jail onestop

    # set readonly and become secondary
    zfs set readonly=on zroot/empt
    zfs inherit -r empt:primary zroot/empt

    # destroy all snapshots on the synced dataset to prepare for receiving from new primary
    zfs destroy -Rf zroot/empt/synced@%

    # unmount the entire EMPT zfs tree
    # TODO idempotency
    # TODO figure out how to keep it unmounted permanently as the secondary
    # using the 'canmount' property recursively.
    zfs unmount zroot/empt || true
}

_takeover() {
    # mount the entire EMPT zfs tree
    zfs mount -R zroot/empt

    # remove readonly from EMPT and takeover as primary
    zfs set empt:primary=on zroot/empt
    zfs inherit -r readonly zroot/empt

    # initialize the first snap with a full replication zfs send
    doas -u emptreplicator /home/emptreplicator/replication.sh init

    # start all jails
    service jail onerestart

    # unlock all EMPT robots
    # TODO idempotency
    awk -F: '$1 ~ /^empt/ { print $1 }' /etc/passwd | xargs -L1 pw unlock || true
}

case "$1" in
    failover) _failover ;;
    takeover) _takeover ;;
    *)
        echo "unrecognized action: '$1'" >&2
        _usage >&2
        exit 64 # EX_USAGE
esac
