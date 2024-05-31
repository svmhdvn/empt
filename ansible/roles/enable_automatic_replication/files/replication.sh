#!/bin/sh

set -e

zfscmd="doas -u zfsemptoperator /sbin/zfs"
readonly zfscmd

_usage() {
    cat <<EOF
usage:
    replication.sh init|backup
EOF
}

_init() {
    secondary="$(zfs get -Hp -o value empt:secondary zroot/empt)"
    primary_prop_from_secondary="$(ssh "zfsemptoperator@${secondary}" zfs get -Hp -o value empt:primary zroot/empt)"
    if test "${primary_prop_from_secondary}" != '-'; then
        echo "Failed to verify secondary host '${secondary}', please check configuration." >&2
        exit 78 # EX_CONFIG
    fi

    # start from scratch by clearing all snapshots that aren't held
    # TODO idempotency
    ${zfscmd} destroy -Rf zroot/empt/synced@% || true

    # create the first snapshot for a full send
    firstsnap=beginning
    ${zfscmd} snapshot -r "zroot/empt/synced@${firstsnap}"

    # do a full replication stream zfs send
    ${zfscmd} send -Rv "zroot/empt/synced@${firstsnap}" | ssh "zfsemptoperator@${secondary}" zfs receive -Fduv zroot

    # once that succeeds, everything is successfully initialized!
    ${zfscmd} set empt:primary=on "empt:lastsent=${firstsnap}" zroot/empt
}

_backup() {
    emptprops="$(zfs list -Hpo empt:primary,empt:secondary,empt:lastsent zroot/empt/synced)"
    read -r primary secondary lastsent <<EOF
${emptprops}
EOF
    if test "${primary}" != 'on' -o "${secondary}" = '-' -o "${lastsent}" = '-'; then
        echo "ERROR: $0: misconfigured replication tracking state! Sanity check both sides now." >&2
        exit 78 # EX_CONFIG
    fi

    # only perform a backup if the synced tree is dirty
    if ! zfs list -Hpr -o written zroot/empt/synced | grep -qvx 0; then
        echo "$0: already up to date." >&2
        exit 0
    fi

    newsnap="$(date -Iseconds)"
    ${zfscmd} snapshot -r "zroot/empt/synced@${newsnap}"

    # clean old snapshots that are expired by the snapshot retention schedule
    _clean

    # TODO figure out whether '-i' or '-I' is better here
    ${zfscmd} send -Rv -i "@${lastsent}" "zroot/empt/synced@${newsnap}" | ssh "zfsemptoperator@${secondary}" zfs receive -Fduv zroot

    # once that succeeds, we're good to go!
    ${zfscmd} set "empt:lastsent=${newsnap}" zroot/empt
}

# TODO:
# * Keep the most recent x minutes of snapshots
# * After that, keep the last y snapshots, x minutes apart
# * Only keep snapshots that are a maximum of z hours ago
# example (reasonable) configuration:
# * keep the most recent 10 minutes of snapshots
# * then keep the next 12 snapshots, each 10 minutes apart, for a total of 2 hours worth of old data live
# NOTE: current simple configuration is: keep the 10 most recent snapshots
_clean() {
    keep=10
    snapshots="$(zfs list -H -t snapshot -o name zroot/empt/synced)"
    numsnapshots="$(echo "${snapshots}" | wc -l)"
    if test "${numsnapshots}" -gt "${keep}"; then
        destroyupto="$(echo "${snapshots}" | tail -$((keep + 1)) | head -1)"
        ${zfscmd} destroy -Rfv "zroot/empt/synced@%${destroyupto##*@}"
    fi
}

case "$1" in
    init) _init ;;
    backup) _backup ;;
    clean) _clean ;;
    *)
        echo "unrecognized action: '$1'" >&2
        _usage >&2
        exit 64 # EX_USAGE
esac
