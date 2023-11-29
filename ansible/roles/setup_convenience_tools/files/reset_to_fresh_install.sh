#!/bin/sh
# must be run as root
set -ex

service jail onestop
zfs destroy -Rf zroot/empt
zfs list -H -t snapshot -o name | grep '@fresh$' | xargs -L1 zfs rollback -R
reboot
