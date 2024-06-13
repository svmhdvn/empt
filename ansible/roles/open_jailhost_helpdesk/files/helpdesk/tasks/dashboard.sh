#!/bin/sh

set -e

. /empt/synced/helpdesk/util.sh

_usage() {
    cat <<EOF
usage:
    dashboard.sh

environment: HELPDESK_*
EOF
}

# $1 = dataset
_display_dataset_quota() {
    pretty_props="$(zfs list -Ho used,available "$1")"
    raw_props="$(zfs list -Hpo used,available "$1")"
    read -r used_pretty available_pretty <<EOF
${pretty_props}
EOF
    read -r used_raw available_raw <<EOF
${raw_props}
EOF
    printf "${used_pretty} / ${available_pretty} ($((used_raw * 100 / available_raw))%)"
}

_groups_storage() {
    for g in $(jexec -l cifs groups "${HELPDESK_FROM_USER}"); do
        test "${g}" = "${HELPDESK_FROM_USER}" && continue
        quota="$(_display_dataset_quota "zroot/empt/synced/rw/group:${g}")"
        echo "  ${g} = ${quota}"
    done
}

_dashboard() {
    user_quota="$(_display_dataset_quota zroot/empt/synced/rw/human:${HELPDESK_FROM_USER})"
    group_quotas="$(_groups_storage)"

    _helpdesk_reply <<EOF
DASHBOARD
=========

My storage = ${user_quota}

My groups:
${group_quotas}
EOF
}

_dashboard
