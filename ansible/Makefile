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

run: inventory.ini
	ansible-playbook -k -K main.yml

inventory.ini: inventory.ini.template
	sed \
		-e 's/%ORG_DOMAIN%/$(ORG_DOMAIN)/g' \
		-e 's/%FRESH_INSTALL_USER%/$(FRESH_INSTALL_USER)/g' \
		-e 's/%JAILHOST_IPV6_ULA%/$(JAILHOST_IPV6_ULA)/g' \
		-e 's/%ULA_PREFIX%/$(ULA_PREFIX)/g' \
		-e 's/%IPV4_PREFIX%/$(IPV4_PREFIX)/g' \
		$< > $@

reset:
	ansible-playbook -k -K factory_reset.yml

clean:
	rm -f inventory.ini

help:
	@echo "usage:"
	@echo "    make JAILHOST_IPV6_ULA=<ipv6_addr> [ORG_DOMAIN=<your_domain>] [FRESH_INSTALL_USER=<your_user>]"
	@echo
	@echo "  where"
	@echo
	@echo "    ipv6_addr: the jailhost's IPv6 Unique Local Address (ULA) on your network. REQUIRED"
	@echo "    your_domain: your organization's Fully Qualified Domain Name (FQDN). Default = empt.siva"
	@echo "    your_user: the user you added during the FreeBSD fresh install onto the jailhost. Default = siva"
