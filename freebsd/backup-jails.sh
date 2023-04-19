#!/bin/sh

# TODO move to ansible playbook

cd "$HOME/src/empt/freebsd" || exit 1

##### common stuff #####

mkdir -p jail
cp /etc/jail.conf jail/
cp -r /usr/jail/fstabs jail/

##### ns1 #####

mkdir -p \
    jail/hosts/ns1/etc \
    jail/hosts/ns1/usr/local/etc/namedb \

cp \
    /usr/jail/hosts/ns1/etc/crontab \
    /usr/jail/hosts/ns1/etc/hosts \
    /usr/jail/hosts/ns1/etc/newsyslog.conf \
    /usr/jail/hosts/ns1/etc/rc.conf \
    /usr/jail/hosts/ns1/etc/resolv.conf \
    /usr/jail/hosts/ns1/etc/syslog.conf \
    jail/hosts/ns1/etc/

cp -r \
    /usr/jail/hosts/ns1/usr/local/etc/namedb/named.conf \
    /usr/jail/hosts/ns1/usr/local/etc/namedb/dynamic \
    jail/hosts/ns1/usr/local/etc/namedb/

cp -r \
    /usr/jail/hosts/ns1/usr/local/etc/nsd \
    jail/hosts/ns1/usr/local/etc/

##### ldap #####

# manually making openldap directory to work around permissions troubles
mkdir -p \
    jail/hosts/ldap/etc \
    jail/hosts/ldap/usr/local/etc/openldap

cp \
    /usr/jail/hosts/ldap/etc/crontab \
    /usr/jail/hosts/ldap/etc/hosts \
    /usr/jail/hosts/ldap/etc/newsyslog.conf \
    /usr/jail/hosts/ldap/etc/rc.conf \
    /usr/jail/hosts/ldap/etc/resolv.conf \
    /usr/jail/hosts/ldap/etc/syslog.conf \
    jail/hosts/ldap/etc/

cp -r \
    /usr/jail/hosts/ldap/usr/local/etc/openldap/schema \
    jail/hosts/ldap/usr/local/etc/openldap/

# TODO need to overcome permissions issues with this hack
doas cat /usr/jail/hosts/ldap/usr/local/etc/openldap/slapd.conf.sample \
    > jail/hosts/ldap/usr/local/etc/openldap/slapd.conf.sample
doas cat /usr/jail/hosts/ldap/usr/local/etc/openldap/slapd.ldif \
    > jail/hosts/ldap/usr/local/etc/openldap/slapd.ldif
doas cat /usr/jail/hosts/ldap/usr/local/etc/openldap/slapd.ldif.sample \
    > jail/hosts/ldap/usr/local/etc/openldap/slapd.ldif.sample

##### mail #####

mkdir -p \
    jail/hosts/mail/etc \
    jail/hosts/mail/usr/local/etc

cp \
    /usr/jail/hosts/mail/etc/crontab \
    /usr/jail/hosts/mail/etc/hosts \
    /usr/jail/hosts/mail/etc/newsyslog.conf \
    /usr/jail/hosts/mail/etc/rc.conf \
    /usr/jail/hosts/mail/etc/resolv.conf \
    /usr/jail/hosts/mail/etc/syslog.conf \
    jail/hosts/mail/etc/

cp -r \
    /usr/jail/hosts/mail/usr/local/etc/postfix \
    /usr/jail/hosts/mail/usr/local/etc/dovecot \
    jail/hosts/mail/usr/local/etc/

##### ssh #####

mkdir -p \
    jail/hosts/ssh/etc/ssh

cp -r \
    /usr/jail/hosts/ssh/etc/crontab \
    /usr/jail/hosts/ssh/etc/hosts \
    /usr/jail/hosts/ssh/etc/newsyslog.conf \
    /usr/jail/hosts/ssh/etc/rc.conf \
    /usr/jail/hosts/ssh/etc/resolv.conf \
    /usr/jail/hosts/ssh/etc/syslog.conf \
    jail/hosts/ssh/etc/

cp \
    /usr/jail/hosts/ssh/etc/ssh/sshd_config \
    jail/hosts/ssh/etc/ssh/

##### kerberos #####

mkdir -p \
    jail/hosts/kerberos/etc \
    jail/hosts/kerberos/usr/local/var/krb5kdc

cp \
    /usr/jail/hosts/kerberos/etc/crontab \
    /usr/jail/hosts/kerberos/etc/hosts \
    /usr/jail/hosts/kerberos/etc/newsyslog.conf \
    /usr/jail/hosts/kerberos/etc/rc.conf \
    /usr/jail/hosts/kerberos/etc/resolv.conf \
    /usr/jail/hosts/kerberos/etc/syslog.conf \
    jail/hosts/kerberos/etc/

cp \
    /usr/jail/hosts/kerberos/usr/local/var/krb5kdc/kdc.conf \
    /usr/jail/hosts/kerberos/usr/local/var/krb5kdc/kadm5.acl \
    jail/hosts/kerberos/usr/local/var/krb5kdc/

##### certauth #####

mkdir -p \
    jail/hosts/certauth/etc \
    jail/hosts/certauth/usr/local/etc/ssl

cp \
    /usr/jail/hosts/certauth/etc/crontab \
    /usr/jail/hosts/certauth/etc/hosts \
    /usr/jail/hosts/certauth/etc/newsyslog.conf \
    /usr/jail/hosts/certauth/etc/rc.conf \
    /usr/jail/hosts/certauth/etc/resolv.conf \
    /usr/jail/hosts/certauth/etc/syslog.conf \
    jail/hosts/certauth/etc/

cp \
    /usr/jail/hosts/certauth/usr/local/etc/ssl/extensions.kdc \
    /usr/jail/hosts/certauth/usr/local/etc/ssl/extensions.client \
    jail/hosts/certauth/usr/local/etc/ssl/

##### logs #####

mkdir -p \
    jail/hosts/logs/etc \

cp \
    /usr/jail/hosts/logs/etc/crontab \
    /usr/jail/hosts/logs/etc/hosts \
    /usr/jail/hosts/logs/etc/newsyslog.conf \
    /usr/jail/hosts/logs/etc/rc.conf \
    /usr/jail/hosts/logs/etc/resolv.conf \
    /usr/jail/hosts/logs/etc/syslog.conf \
    jail/hosts/logs/etc/

################

#git add backup-jails.sh jail && \
#    git commit -m "(automated) empt freebsd jail backup" && \
#    git push
