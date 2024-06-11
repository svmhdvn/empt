#!/bin/sh

# TODO
# * Create a shared calendar
# * Create a group-private IRC channel (possibly with a shared password)
# * validate HELPDESK_* variables input

set -e

. /empt/synced/helpdesk/util.sh

_usage() {
    cat <<EOF
usage:
    groups.sh list
    groups.sh invite <groupname>

environment: HELPDESK_*
EOF
}

_list() {
    groups="$(jexec -l cifs groups "${HELPDESK_FROM_USER}")"
    readonly groups

    _helpdesk_reply <<EOF
You are a part of these groups:

${groups}
EOF
}

_invite() {
    # Take the new group name as the last word of the subject line
    group_name="$1"
    readonly group_name

    # If the group doesn't exist, then get the next available GID
    if shown_group="$(jexec -l cifs pw groupshow "${group_name}")"; then
        group_gid="$(echo "${shown_group}" | cut -f 3 -d :)"
    else
        group_gid="$(jexec -l cifs pw groupnext)"
    fi
    readonly group_gid

    for j in cifs radicale; do
        # TODO idempotency
        jexec -l "${j}" pw groupadd -g "${group_gid}" -n "${group_name}" -q || true
    done

    # Create a mailing list for the group if it doesn't already exist
    # ============================================================

    if ! test -d "/var/spool/mlmmj/${group_name}"; then
        # TODO remove need for answer file
        # TODO fix owner and figure out how that's going to work
        cat > /empt/jails/mail/tmp/mlmmj-answers.txt <<EOF
SPOOLDIR='/var/spool/mlmmj'
LISTNAME='${group_name}'
FQDN='empt.siva'
OWNER='postmaster@empt.siva'
TEXTLANG='en'
ADDALIAS='n'
DO_CHOWN='n'
CHOWN=''
ADDCRON='n'
EOF

        jexec -l -U mlmmj mail mlmmj-make-ml -f /tmp/mlmmj-answers.txt
        rm -f /empt/jails/mail/tmp/mlmmj-answers.txt
    fi

    # Set the upstream mail relayhost
    mail_jid="$(jls -j mail jid)"
    readonly mail_jid
    echo "fe80::eeee:${mail_jid}%lo0" | jexec -l -U mlmmj mail tee "/var/spool/mlmmj/${group_name}/control/relayhost"

    # Ensure that users cannot sub/unsub directly from the mailinglist
    jexec -l -U mlmmj mail touch "/var/spool/mlmmj/${group_name}/control/closedlist"

    # add the new mailing lists to the postfix maps
    _append_if_missing "${group_name}@empt.siva ${group_name}@localhost.mlmmj" /empt/jails/mail/usr/local/etc/postfix/mlmmj_aliases
    _append_if_missing "${group_name}@localhost.mlmmj mlmmj:${group_name}" /empt/jails/mail/usr/local/etc/postfix/mlmmj_transport
    for m in mlmmj_aliases mlmmj_transport; do
        jexec -l mail postmap "/usr/local/etc/postfix/${m}"
    done

    # Create a storage dataset for the group and mount it in corresponding jails
    # ==========================================================================

    # TODO do we need a reservation? I don't think so
    group_mount="/empt/synced/rw/groups/${group_name}"
    readonly group_mount

    zfs create -p \
        -o quota=1G \
        -o mountpoint="${group_mount}" \
        "zroot/empt/synced/rw/group:${group_name}"

    # Create the data and mountpoint directories
    for d in "${group_mount}/home" "${group_mount}/diary" "/empt/jails/cifs/groups/${group_name}"; do
        install -d -o root -g "${group_gid}" -m 1770 "${d}"
    done

    # Mount the group storage in cifs
    cifs_mount_src="${group_mount}/home"
    readonly cifs_mount_src
    cifs_mount_dst="/empt/jails/cifs/groups/${group_name}"
    readonly cifs_mount_dst
    _append_if_missing "${cifs_mount_src} ${cifs_mount_dst} nullfs rw 0 0" /empt/synced/rw/fstab.d/cifs.fstab
    # TODO idempotency
    mount -t nullfs "${cifs_mount_src}" "${cifs_mount_dst}" || true

    # create a welcome file
    echo "welcome, ${HELPDESK_FROM_USER} & ${other_members}" | jexec -l -U "${HELPDESK_FROM_USER}" cifs tee "/groups/${group_name}/WELCOME.txt"
    chmod 0660 "${group_mount}/home/WELCOME.txt"

    # TODO radicale
    # ==========================================================================

    # TODO join the user to the IRC channel and subscribe the IRC logging bot

    # Invite the users to all of the groups' resources
    # ================================================
    other_members="$(echo "${HELPDESK_CC}" | _address_list_to_usernames)"
    readonly other_members

    comma_separated_members="$(printf '%s\n%s\n' "${HELPDESK_FROM_USER}" "${other_members}" | paste -s -d, -)"
    readonly comma_separated_members

    for j in cifs radicale; do
        jexec -l "${j}" pw groupmod -n "${group_name}" -m "${comma_separated_members}" -q || true
    done

    for u in ${HELPDESK_FROM_USER} ${other_members}; do
        jexec -l -U mlmmj mail /usr/local/bin/mlmmj-sub -L "/var/spool/mlmmj/${group_name}" -a "${u}@empt.siva" -cfs
    done
    # ================================================

    # TODO figure out the proper way to use DMA without using the absolute command
    _helpdesk_reply <<EOF
You are now part of the new group '${group_name}'!
EOF
}

# TODO turn this into a case/esac statement
# TODO verify that the subject is already whitespace-trimmed on both sides
case "$1" in
    list|show) _list ;;
    create|invite|form) _invite "$2" ;;
    *)
        echo "$0: ERROR: invalid verb '$1'" >&2
        _usage >&2
        exit 64 # EX_USAGE
esac
