#!/bin/sh

# TODO move to ansible playbook

cd $HOME/src/empt/freebsd

##### ns1 #####

mkdir -p jail/ns1/etc jail/ns1/usr/local/etc

cp \
    /usr/jail/ns1/etc/rc.conf \
    /usr/jail/ns1/etc/resolv.conf \
    /usr/jail/ns1/etc/hosts \
    jail/ns1/etc/

cp -r /usr/jail/ns1/usr/local/etc/namedb jail/ns1/usr/local/etc/

##### ldap #####

mkdir -p jail/ldap/etc jail/ldap/usr/local/etc 

cp \
    /usr/jail/ldap/etc/rc.conf \
    /usr/jail/ldap/etc/resolv.conf \
    /usr/jail/ldap/etc/hosts \
    jail/ldap/etc/

doas cp -r /usr/jail/ldap/usr/local/etc/openldap jail/ldap/usr/local/etc/

##### mail #####

mkdir -p jail/mail/etc jail/mail/usr/local/etc

cp \
    /usr/jail/mail/etc/rc.conf \
    /usr/jail/mail/etc/resolv.conf \
    /usr/jail/mail/etc/hosts \
    jail/mail/etc/

cp -r /usr/jail/mail/usr/local/etc/postfix jail/mail/usr/local/etc/
cp -r /usr/jail/mail/usr/local/etc/dovecot jail/mail/usr/local/etc/

git add jail
git commit -m "(automated) empt freebsd jail backup"
git push
