#!/bin/sh

# TODO
# * Create a shared calendar
# * Create a group-private IRC channel (possibly with a shared password)
# * validate HELPDESK_* variables input

set -e

# TODO is the relative path ok here?
. ../util.sh

_usage() {
    cat <<EOF
usage:
    groups.sh list
    groups.sh create <groupname>

environment: HELPDESK_*
EOF
}

_list() {
    _helpdesk_reply <<EOF
You are a part of these groups:

$(groups "${HELPDESK_FROM_USER}")
EOF
}

_create() {
    # Take the new group name as the last word of the subject line
    group_name="$1"
    readonly group_name

    other_members="$(echo "${HELPDESK_CC}" | _address_list_to_usernames)"
    readonly other_members
    comma_separated_members="$(printf '%s\n%s\n' "${HELPDESK_FROM_USER}" "${other_members}" | paste -s -d, -)"
    readonly comma_separated_members

    # Add the group to the CIFS jail with all members and get back a GID for it
    jexec -l cifs pw groupadd -n "${group_name}" -M "${comma_separated_members}" -q || true
    group_gid="$(jexec -l cifs pw groupshow "${group_name}" | cut -f 3 -d :)"
    readonly group_gid

    # Add the group to the other necessary jails with all members
    for j in radicale; do
        jexec -l "${j}" pw groupadd -g "${group_gid}" -n "${group_name}" -M "${comma_separated_members}" -q || true
    done

    # Create a mailing list and subscribe all members of the group
    # ============================================================

    # TODO remove need for answer file
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

    mail_jid="$(jls -j mail jid)"
    readonly mail_jid

    echo "fe80::eeee:${mail_jid}%lo0" | jexec -l -U mlmmj mail tee "/var/spool/mlmmj/${group_name}/control/relayhost"
    append_if_missing "${group_name}@empt.siva ${group_name}@localhost.mlmmj" /empt/jails/mail/usr/local/etc/postfix/mlmmj_aliases
    append_if_missing "${group_name}@localhost.mlmmj mlmmj:${group_name}" /empt/jails/mail/usr/local/etc/postfix/mlmmj_transport
    for m in mlmmj_aliases mlmmj_transport; do
        jexec -l mail postmap "/usr/local/etc/postfix/${m}"
    done

    for u in ${HELPDESK_FROM_USER} ${other_members}; do
        jexec -l -U mlmmj mail /usr/local/bin/mlmmj-sub -L "/var/spool/mlmmj/${group_name}" -a "${u}@empt.siva" -c -f -s
    done

    # ============================================================

    # Create a storage dataset for the group and mount it in corresponding jails
    # ==========================================================================

    # TODO do we need a reservation? I don't think so
    group_mount="/empt/synced/rw/groups/${group_name}"
    readonly group_mount
    zfs create -p \
        -o quota=1G \
        -o mountpoint="${group_mount}" \
        "zroot/empt/synced/rw/group:${group_name}"

    for d in home diary; do
        mkdir -p "${group_mount}/${d}"
    done

    chown -R "root:${group_gid}" "${group_mount}"
    chmod -R 1770 "${group_mount}"

    # create a welcome file
    echo "welcome, ${HELPDESK_FROM_USER} & ${other_members}" > "${group_mount}/home/WELCOME.txt"
    chown "${HELPDESK_FROM_USER}:${group_name}" "${group_mount}/home/WELCOME.txt"
    chmod 0660 "${group_mount}/home/WELCOME.txt"

    # Mount the group storage in cifs
    jexec -l cifs mkdir -p "/groups/${group_name}"
    cifs_mount_src="${group_mount}/home"
    readonly cifs_mount_src
    cifs_mount_dst="/empt/jails/cifs/groups/${group_name}"
    readonly cifs_mount_dst
    append_if_missing "${cifs_mount_src} ${cifs_mount_dst} nullfs rw 0 0" /empt/synced/rw/fstab.d/cifs.fstab
    # TODO idempotency
    mount -t nullfs "${cifs_mount_src}" "${cifs_mount_dst}" || true

    # TODO radicale
    # ==========================================================================

    # TODO figure out the proper way to use DMA without using the absolute command
    _helpdesk_reply <<EOF
You are now part of the new group '${group_name}'!
EOF
}

# TODO turn this into a case/esac statement
# TODO verify that the subject is already whitespace-trimmed on both sides
case "$1" in
    list) _list ;;
    create) _create "$2" ;;
    *)
        echo "$0: ERROR: invalid verb '$1'" >&2
        _usage >&2
        exit 64 # EX_USAGE
esac
