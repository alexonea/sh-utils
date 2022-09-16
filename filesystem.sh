#
# Utilities for filesystem operations
#

[ -n "${_lib_filesystem_sh_loaded}" ] && return 0
readonly _lib_filesystem_sh_loaded=1

[ -z "${LIBDIR}" ] && LIBDIR="."

. "${LIBDIR}/logging.sh"
. "${LIBDIR}/string.sh"

#
# Determine and print the fstype of a device using blkid
#
# Depends:
#   blkid with TYPE information
#   grep
#
# Parameters:
#   $1 - device path
#
get_fstype ()
{
	devname="$1"
	fstype="$(blkid "${devname}" | grep -o "TYPE=\"[^\"]*\"")"

	(eval "${fstype}"; echo "${TYPE}")
}

#
# Scan and print a list of mount-able partitions
#
# Depends:
#   get_fstype
#   log (logging.sh)
#   tail, awk
# Requires:
#   /proc/partitions
#   /dev (devtmpfs populated)
#
scan_partitions ()
{
	log "Scanning for partitions..."

	res=""
	partitions="$(tail -n +3 < /proc/partitions | awk '{print "/dev/"$4}')"
	for devname in ${partitions}; do
		# check if partition has a filesystem
		fstype="$(get_fstype "${devname}")"
		if [ -n "${fstype}" ]; then
			log "  Found: ${devname} [${fstype}]"
			res="${res} ${devname}"
		else
			log "  Skip: ${devname}"
		fi
	done

	# echo without quotes to remove whitespaces
	[ -n "${res}" ] && echo ${res}
}

#
# Mount a filesystem with checks and options
#
# Depends:
#   logging.sh (log_run)
#   string.sh (join)
#   mount
#
# Parameters:
#   $1 - filesystem type, auto to autodetect
#   $2 - device to mount
#   $3 - target mountpoint
#   $@ - parameters to be passed to the mount command
#
do_mount ()
{
	fstype="$1"
	device="$2"
	target="$3"
	shift 3

	opts="$(join , "$@")"
	[ -n "${opts}" ] && opts="-o ${opts}"

	mkdir -p "${target}"

	log_run mount -t "${fstype}" ${opts} "${device}" "${target}"
}
