.POSIX:
.SUFFIXES:

# Currently needed for bootstrapping domain information before ansible fact
# gathering works on jails. Technically this isn't needed, since we can do all
# jailhost setup after the jails' facts have been gathered. However, this makes
# it much easier to track, and doesn't accidentally run into other local FQDN
# names like '.lan' or '.local'.
# TODO see if there's a cleaner way to do this centrally, or automatically
# through fact gathering.
ORG_DOMAIN = empt.siva

FRESH_INSTALL_USER = siva
JAILHOST_IPV6_ULA = XXX

# Parse the 48-bit ULA prefix to use for jail IPv6 address generation
ULA_PREFIX != echo "$(JAILHOST_IPV6_ULA)" | sed 's/\([[:xdigit:]]\{1,4\}:[[:xdigit:]]\{1,4\}:[[:xdigit:]]\{1,4\}\):.*/\1/g'

run: inventory.ini
	ansible-playbook -k -K \
		-e org_domain=$(ORG_DOMAIN) \
		-e fresh_install_user=$(FRESH_INSTALL_USER) \
		main.yml

inventory.ini:
	echo "jailhost.$(ORG_DOMAIN) ansible_host=$(JAILHOST_IPV6_ULA)" > $@

# TODO loop through some central file and generate these in one line
	echo '[jails]' >> $@
	echo 'certauth.$(ORG_DOMAIN) ansible_host=$(ULA_PREFIX)::eeee:1' >> $@
	echo 'cifs.$(ORG_DOMAIN) ansible_host=$(ULA_PREFIX)::eeee:2' >> $@
	echo 'dns.$(ORG_DOMAIN) ansible_host=$(ULA_PREFIX)::eeee:3' >> $@
	echo 'irc.$(ORG_DOMAIN) ansible_host=$(ULA_PREFIX)::eeee:4' >> $@
	echo 'kerberos.$(ORG_DOMAIN) ansible_host=$(ULA_PREFIX)::eeee:5' >> $@
	echo 'mail.$(ORG_DOMAIN) ansible_host=$(ULA_PREFIX)::eeee:6' >> $@
	echo 'prometheus.$(ORG_DOMAIN) ansible_host=$(ULA_PREFIX)::eeee:7' >> $@
	echo 'ssh.$(ORG_DOMAIN) ansible_host=$(ULA_PREFIX)::eeee:8' >> $@

help:
	@echo "usage:"
	@echo "    make JAILHOST_IPV6_ULA=<ipv6_addr> ORG_DOMAIN=<your_domain> FRESH_INSTALL_USER=<your_user>"
	@echo
	@echo "  where"
	@echo
	@echo "    ipv6_addr: the jailhost's IPv6 Unique Local Address (ULA) on your network. REQUIRED"
	@echo "    your_domain: your organization's Fully Qualified Domain Name (FQDN). Default = empt.siva"
	@echo "    your_user: the user you added during the FreeBSD fresh install onto the jailhost. Default = siva"
