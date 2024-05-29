#!/bin/sh

set -ex

_usage() {
    cat <<EOF
usage:
    replication.sh init <hostname of secondary>
    replication.sh backup|failover|takeover
EOF
}

_init() {
    secondary="$1"
    firstsnap=beginning

    if test "$(ssh "$secondary" zfs get -Hp -o value empt:primary zroot/empt)" != '-'; then
        echo "Failed to verify secondary host '$secondary', please check configuration." >&2
        exit 78 # EX_CONFIG
    fi

    # start from scratch by clearing all snapshots that aren't held
    # TODO idempotency
    zfs destroy -Rf zroot/empt/synced@% || true

    # create the first snapshot for a full send
    zfs snapshot -r "zroot/empt/synced@$firstsnap"

    # do a full replication stream zfs send
    zfs send -Rv "zroot/empt/synced@$firstsnap" | ssh "$secondary" zfs receive -Fduv zroot

    # once that succeeds, everything is successfully initialized!
    zfs set empt:primary=on "empt:secondary=$secondary" "empt:lastsent=$firstsnap" zroot/empt
}

_backup() {
    read -r primary secondary lastsent <<EOF
$(zfs list -Hpo empt:primary,empt:secondary,empt:lastsent zroot/empt/synced)
EOF
    if test "$primary" != 'on' -o test "$secondary" = '-' -o "$lastsent" = '-'; then
        echo "ERROR: $0: misconfigured replication tracking state! Sanity check both sides now." >&2
        exit 78 # EX_CONFIG
    fi

    # only perform a backup if the synced tree is dirty
    if ! zfs list -Hpr -o written zroot/empt/synced | grep -qvx 0; then
        echo "$0: already up to date." >&2
        exit 0
    fi

    newsnap="$(date -Iseconds)"
    zfs snapshot -r "zroot/empt/synced@$newsnap"

    # TODO figure out whether '-i' or '-I' is better here
    zfs send -Rv -i "@$lastsent" "zroot/empt/synced@$newsnap" | ssh "$secondary" zfs receive -Fduv zroot

    # once that succeeds, we're good to go!
    zfs set "empt:lastsent=$newsnap" zroot/empt
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

    # start all jails
    service jail onerestart

    # unlock all EMPT robots
    # TODO idempotency
    awk -F: '$1 ~ /^empt/ { print $1 }' /etc/passwd | xargs -L1 pw unlock || true
}

case "$1" in
    init) _init "$2" ;;
    backup) _backup ;;
    failover) _failover ;;
    takeover) _takeover ;;
    *)
        echo "unrecognized action: '$1'" >&2
        _usage >&2
        exit 64 # EX_USAGE
esac
