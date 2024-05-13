#!/bin/sh

# TODO
# * Create a shared calendar
# * Create a group-private IRC channel (possibly with a shared password)

set -ex

group_name="$1"
readonly group_name
creator="$2"
readonly creator
other_members="$3"
readonly other_members

# Add the group to the CIFS jail and get back a GID for it
jexec -l cifs pw groupadd -n "$group_name" -q || true
group_gid="$(jexec -l cifs pw groupshow "$group_name" | cut -f 3 -d :)"
readonly group_gid

# Add the group to the other necessary jails
for j in radicale; do
    jexec -l "$j" pw groupadd -n "$group_name" -g "$group_gid" -q || true
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
echo "$group_name@empt.siva $group_name@localhost.mlmmj" | jexec -l mail tee /usr/local/etc/postfix/mlmmj_aliases
echo "$group_name@localhost.mlmmj mlmmj:$group_name" | jexec -l mail tee /usr/local/etc/postfix/mlmmj_transport
for m in mlmmj_aliases mlmmj_transport; do
    jexec -l mail postmap "/usr/local/etc/postfix/$m"
done

for u in $creator $other_members; do
    jexec -l -U mlmmj mail /usr/local/bin/mlmmj-sub -L "/var/spool/mlmmj/$group_name" -a "$u" -c -f -s
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
echo "welcome, $other_members" > "/empt/group_storage/$group_name/home/WELCOME.txt"

# Mount the group storage in cifs
jexec -l cifs mkdir -p "/groups/$group_name"
cifs_mount_src="/empt/group_storage/$group_name/home"
readonly cifs_mount_src
cifs_mount_dst="/empt/jails/cifs/groups/$group_name"
readonly cifs_mount_dst
echo "$cifs_mount_src $cifs_mount_dst nullfs rw 0 0"
mount -t nullfs "$cifs_mount_src" "$cifs_mount_dst"

# TODO radicale
# ==========================================================================
