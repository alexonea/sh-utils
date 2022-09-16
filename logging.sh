#
# Utilities for logging in the initramfs
#

[ -n "${_lib_logging_sh_loaded}" ] && return 0
readonly _lib_logging_sh_loaded=1

#
# Log a message to the serial console
#
# Requires: /dev/console
#
log ()
{
	echo "$@" > /dev/console
}

#
# Log the command given as arguments and execute it
#
log_run ()
{
	log "Running: $*"
	"$@"
}
