.POSIX:
.SUFFIXES:

USER = root

factory_reset:

copy_bootstrap:
	ssh $(USER)@jailhost-primary.home.arpa rm -rf *
	scp -r . $(USER)@jailhost-primary.home.arpa:

copy_poudriere:
	ssh $(USER)@jailhost-primary.home.arpa 'rm -rf /tmp/wyse-*'
	scp -r ../ansible/roles/update_poudriere/files/wyse-* $(USER)@jailhost-primary.home.arpa:/tmp
