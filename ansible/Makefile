.POSIX:
.SUFFIXES:

# TODO cleanup duplicate var
FRESH_INSTALL_USER = tester
TARGET = primary

default: solitary

standby: fresh_start reboot

solitary: standby start_fake_company

redundant: standby enable_automatic_replication start_fake_company

fresh_start:
	ansible-playbook \
		-u $(FRESH_INSTALL_USER) \
		-l jailhost-$(TARGET) \
		-i remote_inventory.ini \
		-b -K --become-method ansible.builtin.su \
		fresh_start.yml
	ssh $(FRESH_INSTALL_USER)@jailhost-$(TARGET).home.arpa 'cd /var/tmp/empt-ansible/ansible && \
		doas env CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1 ansible-playbook \
		-i local_inventory.ini \
		-e responsibility=$(TARGET) \
		-e @org_vars.yml \
		main.yml'

start_fake_company:
	ssh $(FRESH_INSTALL_USER)@jailhost-$(TARGET).home.arpa 'cd /var/tmp/empt-ansible/ansible && \
		doas env CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1 ansible-playbook \
		-i remote_inventory.ini \
		-i local_inventory.ini \
		-e @org_vars.yml \
		start_fake_company.yml'

reboot:
	ansible \
		-u $(FRESH_INSTALL_USER) \
		-b --become-method community.general.doas \
		-i remote_inventory.ini \
		-m reboot \
		jailhost-$(TARGET)

# TODO update all jails
update_poudriere:
	ansible-playbook \
		-u $(FRESH_INSTALL_USER) \
		-l jailhost-$(TARGET) \
		-i remote_inventory.ini \
		-b -K --become-method ansible.builtin.su \
		update_poudriere.yml

enable_automatic_replication:
	ansible-playbook \
		-u $(FRESH_INSTALL_USER) \
		-b --become-method community.general.doas \
		-i local_inventory.ini \
		-i remote_inventory.ini \
		enable_automatic_replication.yml

reset:
	ansible \
		-u $(FRESH_INSTALL_USER) \
		-b -K --become-method ansible.builtin.su \
		-i remote_inventory.ini \
		-m import_role -a name=factory_reset \
		jailhost-$(TARGET)

help:
	@echo "usage:"
	@echo "    make [TARGET=<responsibility>] [FRESH_INSTALL_USER=<your_user>]"
	@echo
	@echo "  where"
	@echo
	@echo "    responsibility: either 'primary' or 'secondary'. Default = primary"
	@echo "    your_user: the user you added during the FreeBSD fresh install onto the jailhost. Default = tester"
