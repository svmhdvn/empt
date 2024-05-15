#!/bin/sh

# TODO
# * Create a shared calendar
# * Create a group-private IRC channel (possibly with a shared password)

set -ex

# Converts an RFC 5322 address-list to a list of UNIX usernames
address_list_to_usernames() {
    awk -v RS=',' '{ split($NF, parts, "@"); sub("<", "", parts[1]); print parts[1] }'
}

append_if_missing() {
    _line="$1"
    _file="$2"
    grep -qxF "$_line" "$_file" || echo "$_line" >> "$_file"
}

creator="$(echo "$HELPDESK_FROM" | address_list_to_usernames)"
readonly creator
other_members="$(echo "$HELPDESK_CC" | address_list_to_usernames)"
readonly other_members
comma_separated_members="$(printf '%s\n%s\n' "$creator" "$other_members" | paste -s -d, -)"
readonly comma_separated_members

if ! echo "$HELPDESK_SUBJECT" | grep -qw 'create'; then
    echo "ERROR: only 'create' operation is supported now." >&2
    exit 64 # EX_USAGE
fi

# Take the new group name as the last word of the subject line
group_name="$(echo "$HELPDESK_SUBJECT" | awk '{ print $NF }')"
readonly group_name

# Add the group to the CIFS jail with all members and get back a GID for it
jexec -l cifs pw groupadd -n "$group_name" -M "$comma_separated_members" -q || true
group_gid="$(jexec -l cifs pw groupshow "$group_name" | cut -f 3 -d :)"
readonly group_gid

# Add the group to the other necessary jails with all members
for j in radicale; do
    jexec -l "$j" pw groupadd -g "$group_gid" -n "$group_name" -M "$comma_separated_members" -q || true
done

# Create a mailing list and subscribe all members of the group
# ============================================================

# TODO remove need for answer file
cat > /empt/jails/mail/tmp/mlmmj-answers.txt <<EOF
SPOOLDIR='/var/spool/mlmmj'
LISTNAME='$group_name'
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

echo "fe80::eeee:$mail_jid%lo0" | jexec -l -U mlmmj mail tee "/var/spool/mlmmj/$group_name/control/relayhost"
append_if_missing "$group_name@empt.siva $group_name@localhost.mlmmj" /empt/jails/mail/usr/local/etc/postfix/mlmmj_aliases
append_if_missing "$group_name@localhost.mlmmj mlmmj:$group_name" /empt/jails/mail/usr/local/etc/postfix/mlmmj_transport
for m in mlmmj_aliases mlmmj_transport; do
    jexec -l mail postmap "/usr/local/etc/postfix/$m"
done

for u in $creator $other_members; do
    jexec -l -U mlmmj mail /usr/local/bin/mlmmj-sub -L "/var/spool/mlmmj/$group_name" -a "$u@empt.siva" -c -f -s
done

# ============================================================

# Create a storage dataset for the group and mount it in corresponding jails
# ==========================================================================
# TODO do we need a reservation? I don't think so
zfs create -p \
    -o quota=1G \
    "zroot/empt/group_storage/$group_name"

for d in home diary; do
    mkdir -p "/empt/group_storage/$group_name/$d"
done

chown -R "root:$group_gid" "/empt/group_storage/$group_name"
chmod -R 1770 "/empt/group_storage/$group_name"
echo "welcome, $creator & $other_members" > "/empt/group_storage/$group_name/home/WELCOME.txt"

# Mount the group storage in cifs
jexec -l cifs mkdir -p "/groups/$group_name"
cifs_mount_src="/empt/group_storage/$group_name/home"
readonly cifs_mount_src
cifs_mount_dst="/empt/jails/cifs/groups/$group_name"
readonly cifs_mount_dst
append_if_missing "$cifs_mount_src $cifs_mount_dst nullfs rw 0 0" /empt/etc/cifs/fstab
# TODO make this idempotent
mount -t nullfs "$cifs_mount_src" "$cifs_mount_dst"

# TODO radicale
# ==========================================================================

# TODO figure out the proper way to use DMA without using the absolute command
/usr/libexec/dma -f 'helpdeskbot@empt.siva' -t <<EOF
To: $HELPDESK_FROM
Cc: $HELPDESK_CC, Helpdesk <helpdesk@empt.siva>
Subject: [HELPDESK] Re: $HELPDESK_SUBJECT
In-Reply-To: $HELPDESK_IN_REPLY_TO
References: $HELPDESK_REFERENCES $HELPDESK_IN_REPLY_TO

You are now part of the new group '$group_name'!

EOF
