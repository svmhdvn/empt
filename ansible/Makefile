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
JAILHOST_IPV6_ULA = XXX

# Parse the 48-bit ULA prefix to use for jail IPv6 address generation
ULA_PREFIX != echo "$(JAILHOST_IPV6_ULA)" | sed 's/\([[:xdigit:]]\{1,4\}:[[:xdigit:]]\{1,4\}:[[:xdigit:]]\{1,4\}\):.*/\1/g'

# TODO only supports 10.AAA.BBB.0/24 networks, I find that there's no need to support
# anything else realistically right now. IPv4 support will eventually be phased
# out.
IPV4_PREFIX != ifconfig | sed -n 's/.*[ \t]inet[ \t][^1]*\(10\.[[:digit:]]*\.[[:digit:]]*\).*/\1/p'

fresh_start:
	ansible-playbook \
		-u $(FRESH_INSTALL_USER) \
		-i remote_inventory.ini \
		-K fresh_start.yml
	scp -r . $(FRESH_INSTALL_USER)@[$(JAILHOST_IPV6_ULA)]:~
	ssh $(FRESH_INSTALL_USER)@$(JAILHOST_IPV6_ULA) doas ansible-playbook \
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

reset:
	ansible \
		-u $(FRESH_INSTALL_USER) \
		-b -K --become-method ansible.builtin.su \
		-i remote_inventory.ini \
		-m import_role -a name=factory_reset \
		jailhost

help:
	@echo "usage:"
	@echo "    make JAILHOST_IPV6_ULA=<ipv6_addr> [ORG_DOMAIN=<your_domain>] [FRESH_INSTALL_USER=<your_user>]"
	@echo
	@echo "  where"
	@echo
	@echo "    ipv6_addr: the jailhost's IPv6 Unique Local Address (ULA) on your network. REQUIRED"
	@echo "    your_domain: your organization's Fully Qualified Domain Name (FQDN). Default = empt.siva"
	@echo "    your_user: the user you added during the FreeBSD fresh install onto the jailhost. Default = tester"
