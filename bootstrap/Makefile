.POSIX:
.SUFFIXES:

USER = root

copy_bootstrap:
	ssh $(USER)@jailhost-primary.home.arpa rm -rf *
	scp -r . $(USER)@jailhost-primary.home.arpa:
