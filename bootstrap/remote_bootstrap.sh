#!/bin/sh

# $1 = full cmd string
_try_ssh() {
    while ! ssh root@jailhost-primary.home.arpa "$1"; do
        echo "not online, trying again..." >&2
        sleep 2
    done
}

# $1 = remote dest
# $2 = src files
_try_scp() {
    dest="$1"
    shift
    while ! scp -r "$@" "root@jailhost-primary.home.arpa:${dest}"; do
        echo "not online, trying again..." >&2
        sleep 2
    done
}

echo "===== STEP 0 ====="
_try_ssh './empt.sh 0'
echo "===== STEP 1 ====="
_try_ssh 'rm -rf *'
_try_scp '~' .
_try_ssh './empt.sh 1'
echo "===== STEP 2 ====="
_try_ssh 'rm -rf /tmp/wyse-*'
_try_scp /tmp ../ansible/roles/update_poudriere/files/wyse-*
_try_ssh './empt.sh 2'
echo "===== STEP 3 ====="
_try_ssh './empt.sh 3'
echo "===== FINSHED ====="
