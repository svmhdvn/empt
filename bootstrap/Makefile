.POSIX:
.SUFFIXES:

# relies on ~/.ssh/config for ssh aliases
copy_bootstrap:
	ssh wyse rm -rf *
	scp -r . wyse:
