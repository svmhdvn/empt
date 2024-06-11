#!/bin/sh

# Converts an RFC 5322 address-list to a list of UNIX usernames
_address_list_to_usernames() {
    awk -v RS=',' '{ split($NF, parts, "@"); sub("<", "", parts[1]); print parts[1] }'
}

# $1 = line
# $2 = file
_append_if_missing() {
    grep -qxF "$1" "$2" || echo "$1" >> "$2"
}

_helpdesk_reply() {
    # TODO figure out the proper way to use DMA without using the absolute command
    {
        cat <<EOF
To: ${HELPDESK_FROM}
Cc: ${HELPDESK_CC}, Helpdesk <helpdesk@empt.siva>
Subject: [HELPDESK] Re: ${HELPDESK_SUBJECT}
In-Reply-To: ${HELPDESK_MESSAGE_ID}
References: ${HELPDESK_REFERENCES} ${HELPDESK_MESSAGE_ID}

EOF
        cat
    } | /usr/libexec/dma -f 'empthelper@empt.siva' -t
}
