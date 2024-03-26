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
FRESH_INSTALL_USER = tester

JAILHOST_IPV4 = XXX
JAILHOST_IPV6 = XXX

IPV4_PREFIX != echo "$(JAILHOST_IPV4)" | sed 's/\..\{1,3\}$$//'
ULA_PREFIX != echo "$(JAILHOST_IPV6)" | sed 's/\([[:xdigit:]]\{1,4\}:[[:xdigit:]]\{1,4\}:[[:xdigit:]]\{1,4\}\):.*/\1/g'

fresh_start:
	ansible-playbook \
		-u $(FRESH_INSTALL_USER) \
		-i remote_inventory.ini \
		-b -K --become-method ansible.builtin.su \
		-K fresh_start.yml
	scp -r . $(FRESH_INSTALL_USER)@jailhost.$(ORG_DOMAIN):~
	ssh $(FRESH_INSTALL_USER)@jailhost.$(ORG_DOMAIN) doas ansible-playbook \
		-i local_inventory.ini \
		-e org_domain=$(ORG_DOMAIN) \
		-e fresh_install_user=$(FRESH_INSTALL_USER) \
		-e ula_prefix=$(ULA_PREFIX) \
		-e ipv4_prefix=$(IPV4_PREFIX) \
		main.yml
	ansible \
		-u $(FRESH_INSTALL_USER) \
		-b -K --become-method ansible.builtin.su \
		-i remote_inventory.ini \
		-m reboot \
		jailhost

update_poudriere:
	ansible \
		-u $(FRESH_INSTALL_USER) \
		-i remote_inventory.ini \
		-b -K --become-method ansible.builtin.su \
		-m import_role -a name=update_poudriere \
		jailhost

reset:
	ansible \
		-u $(FRESH_INSTALL_USER) \
		-i remote_inventory.ini \
		-b -K --become-method ansible.builtin.su \
		-m import_role -a name=factory_reset \
		jailhost

help:
	@echo "usage:"
	@echo "    make JAILHOST_IPV4=<ipv4_addr> JAILHOST_IPV6=<ipv6_addr> [ORG_DOMAIN=<your_domain>] [FRESH_INSTALL_USER=<your_user>]"
	@echo
	@echo "  where"
	@echo
	@echo "    ipv4_addr: the jailhost's IPv4 10.xxx.yyy/24 addr on your network. REQUIRED"
	@echo "    ipv6_addr: the jailhost's IPv6 Unique Local Address (ULA) on your network. REQUIRED"
	@echo "    your_domain: your organization's Fully Qualified Domain Name (FQDN). Default = empt.siva"
	@echo "    your_user: the user you added during the FreeBSD fresh install onto the jailhost. Default = tester"
