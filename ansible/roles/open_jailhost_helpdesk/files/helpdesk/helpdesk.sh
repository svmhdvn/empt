#!/bin/sh

set -e

. /empt/synced/helpdesk/util.sh

HELPDESK_FROM_USER="$(echo "${HELPDESK_FROM}" | _address_list_to_usernames)"
export HELPDESK_FROM_USER

if test -z "${HELPDESK_FROM_USER}"; then
    echo "$0: ERROR: invalid HELPDESK_FROM value '${HELPDESK_FROM}'" >&2
    exit 65 # EX_DATAERR
fi

# parse the subject line
read -r verb object param1 <<EOF
${HELPDESK_SUBJECT}
EOF

# triage the task based on the type of object
case "${object}" in
    group*) taskname=groups ;;
    *) taskname=helpdesk_usage ;;
esac

doas "/empt/synced/helpdesk/tasks/${taskname}.sh" "${verb}" "${param1}"
