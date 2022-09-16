#
# Utilities for processing input
#

[ -n "${_lib_input_sh_loaded}" ] && return 0
readonly _lib_input_sh_loaded=1

#
# Read and print one key from stdin with timeout
#
# Depends: bc, stty, dd
# Requires: /dev/null
#
# Parameters:
#   $1 - timeout in seconds (can be a floating point number as well)
#
# Return:
#   0 if a key was read, and
#   1 otherwise
#
get_key ()
{
	# stty uses tenths of a second, we divide by 1 to truncate to whole numbers
	timeout="$(echo "scale=0; ($1 * 10) / 1" | bc)"

	# timeout cannot be zero
	[ "${timeout}" -gt 0 ] || timeout=1

	tmp="$(stty -g)"
	stty raw -echo min 0 time "${timeout}"
	key="$(dd bs=1 count=1 2>/dev/null)"
	stty ${tmp}

	[ -z "${key}" ] && return 1
	echo "${key}"
}

#
# Flush the stdin by reading until there is nothing more to read
#
# Depends: bc, stty, dd
# Requires: /dev/null
#
flush_stdin ()
{
	tmp="$(stty -g)"
	stty raw -echo min 0 time 0
	dd bs=1 count=10000 2>/dev/null 1>&2
	stty ${tmp}
}

#
# Retrieve and print the value of a given key in the kernel command line
#
# Depends: grep
# Requires: /proc/cmdline
#
# Parameters:
#    $1 - the key
#
# Return:
#    0 in case the key exists in the kernel command line, and
#    1 otherwise
#
get_cmdline_param ()
{
	key="$1"
	param="$(grep -o "${key}=\?[^\ ]*" < /proc/cmdline)"

	# if the key is not present, return error (1)
	[ -z "${param}" ] && return 1

	# return the value only (remove suffix up to and including =)
	echo "${param#*=}"
}
