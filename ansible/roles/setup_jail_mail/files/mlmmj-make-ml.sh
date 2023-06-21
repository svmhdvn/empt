#!/bin/sh
#
# mlmmj-make-ml - henne@hennevogel.de
#

VERSION="0.2"
ALIASFILE=/etc/aliases
CRONTAB=/etc/crontab
TEXTLIBDIR=/usr/local/share/mlmmj/text.skel

USAGE="mlmmj-make-ml $VERSION

$0 <options>

options:
 -L listname: the name of the mailing list
 -a: create the needed entries in your $ALIASFILE file
 -b: add needed entry to $CRONTAB
 -c user: user to chown the spool directory to
 -d fqdn: fully qualified domain name of the mailing list
 -f answerfile: use answerfile to create mailing list non-interactively
 -h: display this help text
 -n answerfile: Do nothing. Instead, create answer file for later non-interactive use with -f
 -s spooldir: mlmmj spool directory
 -t lang: list text directory relative to $TEXTLIBDIR for given language
"

while getopts ":L:abc:d:f:hn:s:t:" Option
do
case "$Option" in
	L )
	LISTNAME="$OPTARG"
	;;
	a )
	ADDALIAS="y"
	;;
	b )
	ADDCRON="y"
	;;
	c )
	DO_CHOWN="y"
	CHOWN="$OPTARG"
	;;
	d )
	FQDN="$OPTARG"
	;;
	f )
	ANSWERFILEIN="$OPTARG"
	;;
	h )
	echo "$USAGE"
	exit 0
	;;
	n )
	ANSWERFILEOUT="$OPTARG"
	;;
	s )
	SPOOLDIR="$OPTARG"
	;;
	t )
	TEXTLANG="$OPTARG"
	;;
	* )
	echo "$0: invalid option"
	echo "Try $0 -h for more information."
	exit 1
esac
done
SHIFTVAL=$((OPTIND-1))
shift $SHIFTVAL

if [ -r "$ANSWERFILEIN" ]; then
	# shellcheck source=/dev/null
	. "$ANSWERFILEIN"
fi

if [ ! -d "$SPOOLDIR" ]; then
	SPOOLDIRDEF=/var/spool/mlmmj
	printf 'mlmmj spool directory under which to create new mailing list [%s] : ' "$SPOOLDIRDEF"
	read -r SPOOLDIR
	if [ ! -d "$SPOOLDIR" ]; then
		SPOOLDIR="$SPOOLDIRDEF"
	fi
fi

if [ -z "$LISTNAME" ]; then
	LISTNAMEDEF="mlmmj-test"
	printf 'What should the name of the Mailinglist be? [%s] : ' "$LISTNAMEDEF"
	read -r LISTNAME
	if [ -z "$LISTNAME" ]; then
		LISTNAME="$LISTNAMEDEF"
	fi
fi
LISTDIR="$SPOOLDIR/$LISTNAME"

if [ -z "$FQDN" ]; then
	printf 'The Fully Qualified Domain Name (FQDN) for the List? [] : '
	read -r FQDN
	if [ -z "$FQDN" ]; then
		FQDN="$(domainname -f)"
	fi
fi

if [ -z "$OWNER" ]; then
	OWNERDEF="postmaster"
	printf 'The emailaddress of the list owner? [%s] : ' "$OWNERDEF"
	read -r OWNER
	if [ -z "$OWNER" ]; then
		OWNER="$OWNERDEF"
	fi
fi

if [ -d "$TEXTLIBDIR" ]; then
	if [ -z "$TEXTLANG" ]; then
		cat <<EOF

You can choose between the following languages for the list texts.

Available languages:
EOF
		ls "$TEXTLIBDIR"

		TEXTLANGDEF=en
		printf 'mailing list texts language? [%s] : ' $TEXTLANGDEF
		read -r TEXTLANG
		if [ -z "$TEXTLANG" ] ; then
			TEXTLANG="$TEXTLANGDEF"
		fi
	fi

	TEXTPATH="$TEXTLIBDIR/$TEXTLANG"
else
	cat <<EOF

List text library directory not found! Please check compile options.
**WARNING** Could not copy the texts for the list
Please manually copy the files from the listtexts/ directory
in the source distribution of mlmmj.
EOF
fi

LISTADDRESS="$LISTNAME@$FQDN"

MLMMJRECEIVE=$(which mlmmj-receive 2>/dev/null)
if [ -z "$MLMMJRECEIVE" ]; then
	MLMMJRECEIVE="/path/to/mlmmj-receive"
fi

MLMMJMAINTD=$(which mlmmj-maintd 2>/dev/null)
if [ -z "$MLMMJMAINTD" ]; then
	MLMMJMAINTD="/path/to/mlmmj-maintd"
fi

ALIAS="$LISTNAME:  \"|$MLMMJRECEIVE -L $LISTDIR/\""
CRONENTRY="0 */2 * * * \"$MLMMJMAINTD -F -L $LISTDIR/\""


if [ -z "$ADDALIAS" ]; then
	cat <<EOF

Don't forget to add this line to $ALIASFILE:
$ALIAS

EOF
	printf 'Should I add it for you? (y/n) [n] '
	read -r ADDALIAS
	ADDALIAS=${ADDALIAS:-n}
fi

if [ -z "$DO_CHOWN" ]; then
	printf 'Would you like to change the owner of the newly created mailing list directory? (y/n) [n] '
	read -r DO_CHOWN
	DO_CHOWN=${DO_CHOWN:-n}
fi
case $DO_CHOWN in
	y|Y)
		if [ -z "$CHOWN" ]; then
			printf 'New owner of %s [] : ' "$LISTDIR"
			read -r CHOWN
		fi
esac

if [ -z "$ADDCRON" ]; then
	cat <<EOF

If you're not starting mlmmj-maintd in daemon mode,
don't forget to add this line to your crontab:
$CRONENTRY

EOF
	printf 'Should I add it to the system-wide crontab at %s for you? (y/n) [n] ' "$CRONTAB"
	read -r ADDCRON
	ADDCRON=${ADDCRON:-n}
fi

if [ -n "$ANSWERFILEOUT" ]; then
	echo
	echo "Writing all selections to $ANSWERFILEOUT. No changes made."
	cat > "$ANSWERFILEOUT" <<EOF
SPOOLDIR='$SPOOLDIR'
LISTNAME='$LISTNAME'
FQDN='$FQDN'
OWNER='$OWNER'
TEXTLANG='$TEXTLANG'
ADDALIAS='$ADDALIAS'
DO_CHOWN='$DO_CHOWN'
CHOWN='$CHOWN'
ADDCRON='$ADDCRON'
EOF
else
	mkdir -p "$LISTDIR"
	for DIR in incoming queue queue/discarded archive text subconf unsubconf \
		   bounce control moderation subscribers.d digesters.d requeue \
		   nomailsubs.d
	do
		mkdir -p "$LISTDIR/$DIR"
	done

	test -f "$LISTDIR/index" || touch "$LISTDIR/index"
	echo "$OWNER" > "$LISTDIR/control/owner"
	echo "$LISTADDRESS" > "$LISTDIR/control/listaddress"

	if [ -d "$TEXTPATH" ]; then
		cp "$TEXTPATH"/* "$LISTDIR/text"
	else
		echo "WARNING: List text language '$TEXTLANG' not found."
		echo "Proceeding without copying list texts."
	fi

	case "$ADDALIAS" in
		y|Y)
			echo "$ALIAS" >> $ALIASFILE
	esac

	case "$DO_CHOWN" in
		y|Y)
			if [ -n "$CHOWN" ]; then
				chown -R "$CHOWN" "$LISTDIR"
			fi
	esac

	case "$ADDCRON" in
		y|Y)
			echo "$CRONENTRY" >> $CRONTAB
	esac

	echo
	echo "Mailing list $LISTDIR was created successfully."
fi

cat <<EOF

** FINAL NOTES **
1) The mailinglist directory has to be owned by the user running the
mailserver (i.e. starting the binaries to work the list)
2) Run newaliases
EOF
