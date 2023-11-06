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

run:
	echo "jailhost ansible_host=$(JAILHOST_IPV6_ULA)" > inventory
	ansible-playbook -k -K \
		-e org_domain=$(ORG_DOMAIN) \
		-e fresh_install_user=$(FRESH_INSTALL_USER) \
		main.yml

help:
	@echo "usage:"
	@echo "    make ORG_DOMAIN=<your_domain> FRESH_INSTALL_USER=<your_user> JAILHOST_IPV6_ULA=<ipv6_addr>"
	@echo
	@echo "  where"
	@echo
	@echo "    your_domain: your organization's Fully Qualified Domain Name (FQDN). Default = empt.siva"
	@echo "    your_user: the user you added during the FreeBSD fresh install onto the jailhost. Default = siva"
	@echo "    ipv6_addr: the jailhost's IPv6 Unique Local Address (ULA) on your network. MANDATORY"
