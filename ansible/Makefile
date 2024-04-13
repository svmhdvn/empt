.POSIX:
.SUFFIXES:

# TODO cleanup duplicate var
FRESH_INSTALL_USER = tester

TARGET = XXX

fresh_start:
	ansible-playbook \
		-u $(FRESH_INSTALL_USER) \
		-l $(TARGET) \
		-i remote_inventory.ini \
		-b -K --become-method ansible.builtin.su \
		-K fresh_start.yml
	ssh $(FRESH_INSTALL_USER)@$(TARGET).home.arpa 'cd /tmp/empt-ansible/ansible && \
		doas ansible-playbook \
		-i local_inventory.ini \
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
		-K update_poudriere.yml

reset:
	ansible \
		-u $(FRESH_INSTALL_USER) \
		-i remote_inventory.ini \
		-b -K --become-method ansible.builtin.su \
		-m import_role -a name=factory_reset \
		$(TARGET)

help:
	@echo "usage:"
	@echo "    make TARGET=<target_host> [FRESH_INSTALL_USER=<your_user>]"
	@echo
	@echo "  where"
	@echo
	@echo "    target_host: the jailhost that you want to set up. REQUIRED."
	@echo "    your_user: the user you added during the FreeBSD fresh install onto the jailhost. Default = tester"
