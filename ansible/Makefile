.POSIX:
.SUFFIXES:

# TODO cleanup duplicate var
FRESH_INSTALL_USER = tester

TARGET = XXX
RESPONSIBILITY = XXX

fresh_start:
	ansible-playbook \
		-u $(FRESH_INSTALL_USER) \
		-l $(TARGET) \
		-i remote_inventory.ini \
		-b -K --become-method ansible.builtin.su \
		fresh_start.yml
	ssh $(FRESH_INSTALL_USER)@$(TARGET).home.arpa 'cd /tmp/empt-ansible/ansible && \
		doas env CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1 ansible-playbook \
		-i local_inventory.ini \
		-e responsibility=$(RESPONSIBILITY) \
		-e @org_vars.yml \
		main.yml'
	ansible \
		-u $(FRESH_INSTALL_USER) \
		-b -K --become-method ansible.builtin.su \
		-i remote_inventory.ini \
		-m reboot \
		$(TARGET)

# TODO update all jails
update_poudriere:
	ansible-playbook \
		-u $(FRESH_INSTALL_USER) \
		-l $(TARGET) \
		-i remote_inventory.ini \
		-b -K --become-method ansible.builtin.su \
		update_poudriere.yml

activate_zrep:
	ansible-playbook \
		-u $(FRESH_INSTALL_USER) \
		-b -K --become-method ansible.builtin.su \
		-i local_inventory.ini \
		-i remote_inventory.ini \
		activate_zrep.yml

reset:
	ansible \
		-u $(FRESH_INSTALL_USER) \
		-b -K --become-method ansible.builtin.su \
		-i remote_inventory.ini \
		-m import_role -a name=factory_reset \
		$(TARGET)

help:
	@echo "usage:"
	@echo "    make TARGET=<target_host> RESPONSIBILITY=<responsibility> [FRESH_INSTALL_USER=<your_user>]"
	@echo
	@echo "  where"
	@echo
	@echo "    target_host: the jailhost that you want to set up. REQUIRED."
	@echo "    responsibility: either 'primary' or 'secondary'. REQUIRED."
	@echo "    your_user: the user you added during the FreeBSD fresh install onto the jailhost. Default = tester"
