#!/bin/sh

doas service jail onestop
doas zfs destroy -Rf zroot/empt
zfs list -H -t snapshot -o name | grep '@fresh$' | doas xargs -L1 zfs rollback -R
