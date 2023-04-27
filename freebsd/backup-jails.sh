#!/bin/sh

# TODO delete this once everything is moved to ansible and tested

cd "$HOME/src/empt/freebsd" || exit 1

##### common stuff #####

mkdir -p jail
cp /etc/jail.conf jail/
cp -r /usr/jail/fstabs jail/

##### ns1 #####

mkdir -p \
    jail/guests/ns1/etc \
    jail/guests/ns1/usr/local/etc

cp \
    /usr/jail/guests/ns1/etc/crontab \
    /usr/jail/guests/ns1/etc/hosts \
    /usr/jail/guests/ns1/etc/newsyslog.conf \
    /usr/jail/guests/ns1/etc/rc.conf \
    /usr/jail/guests/ns1/etc/resolv.conf \
    /usr/jail/guests/ns1/etc/syslog.conf \
    jail/guests/ns1/etc/

cp -r \
    /usr/jail/guests/ns1/usr/local/etc/nsd \
    jail/guests/ns1/usr/local/etc/

##### mail #####

mkdir -p \
    jail/guests/mail/etc \
    jail/guests/mail/usr/local/etc

cp \
    /usr/jail/guests/mail/etc/crontab \
    /usr/jail/guests/mail/etc/hosts \
    /usr/jail/guests/mail/etc/newsyslog.conf \
    /usr/jail/guests/mail/etc/rc.conf \
    /usr/jail/guests/mail/etc/resolv.conf \
    /usr/jail/guests/mail/etc/syslog.conf \
    jail/guests/mail/etc/

cp -r \
    /usr/jail/guests/mail/usr/local/etc/postfix \
    /usr/jail/guests/mail/usr/local/etc/dovecot \
    jail/guests/mail/usr/local/etc/

##### ssh #####

mkdir -p \
    jail/guests/ssh/etc/ssh

cp -r \
    /usr/jail/guests/ssh/etc/crontab \
    /usr/jail/guests/ssh/etc/hosts \
    /usr/jail/guests/ssh/etc/newsyslog.conf \
    /usr/jail/guests/ssh/etc/rc.conf \
    /usr/jail/guests/ssh/etc/resolv.conf \
    /usr/jail/guests/ssh/etc/syslog.conf \
    jail/guests/ssh/etc/

cp \
    /usr/jail/guests/ssh/etc/ssh/sshd_config \
    jail/guests/ssh/etc/ssh/

##### kerberos #####

mkdir -p \
    jail/guests/kerberos/etc

cp \
    /usr/jail/guests/kerberos/etc/crontab \
    /usr/jail/guests/kerberos/etc/hosts \
    /usr/jail/guests/kerberos/etc/newsyslog.conf \
    /usr/jail/guests/kerberos/etc/rc.conf \
    /usr/jail/guests/kerberos/etc/resolv.conf \
    /usr/jail/guests/kerberos/etc/syslog.conf \
    jail/guests/kerberos/etc/

##### certauth #####

mkdir -p \
    jail/guests/certauth/etc \
    jail/guests/certauth/usr/local/etc/ssl

cp \
    /usr/jail/guests/certauth/etc/crontab \
    /usr/jail/guests/certauth/etc/hosts \
    /usr/jail/guests/certauth/etc/newsyslog.conf \
    /usr/jail/guests/certauth/etc/rc.conf \
    /usr/jail/guests/certauth/etc/resolv.conf \
    /usr/jail/guests/certauth/etc/syslog.conf \
    jail/guests/certauth/etc/

cp \
    /usr/jail/guests/certauth/usr/local/etc/ssl/extensions.kdc \
    /usr/jail/guests/certauth/usr/local/etc/ssl/extensions.client \
    jail/guests/certauth/usr/local/etc/ssl/

##### logs #####

mkdir -p \
    jail/guests/logs/etc \

cp \
    /usr/jail/guests/logs/etc/crontab \
    /usr/jail/guests/logs/etc/hosts \
    /usr/jail/guests/logs/etc/newsyslog.conf \
    /usr/jail/guests/logs/etc/rc.conf \
    /usr/jail/guests/logs/etc/resolv.conf \
    /usr/jail/guests/logs/etc/syslog.conf \
    jail/guests/logs/etc/

################

#git add backup-jails.sh jail && \
#    git commit -m "(automated) empt freebsd jail backup" && \
#    git push
