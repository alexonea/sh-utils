#
# Utilities for network operations
#

[ -n "${_lib_network_sh_loaded}" ] && return 0
readonly _lib_network_sh_loaded=1

[ -z "${LIBDIR}" ] && LIBDIR="."

. "${LIBDIR}/logging.sh"
. "${LIBDIR}/string.sh"

#
# Retrieve and print the ip address of the given network interface
#
# Depends: ip, awk
#
# Parameters:
#   $1 - the interface name
#
# Return:
#   0 if an address was found configured, or
#   1 otherwise
#
get_ip ()
{
	iface="$1"
	addr="$(ip -o -4 addr list "${iface}" | awk '{print $4}')"

	[ -z "${addr}" ] && return 1
	echo "${addr%/*}"
}

#
# Convert IP address to decimal
#
ip_to_decimal ()
{
	IFS=. read -r a b c d
	printf "%d\n" "$((a * 16777216 + b * 65536 + c * 256 + d))"
}

#
# Convert decimal to IP address
#
decimal_to_ip ()
{
	read -r dec
	a="$((dec / 16777216))"; dec="$((dec - a * 16777216))"
	b="$((dec / 65536))";    dec="$((dec - b * 65536))"
	c="$((dec / 256))";      dec="$((dec - c * 256))"
	d="${dec}"

	printf "%d.%d.%d.%d\n" "$a" "$b" "$c" "$d"
}

#
# Generate and print a random IP address given a subnet
#
# Depends: ip_to_decimal, decimal_to_ip, dd, xxd
# Requires: /dev/null
#
# Parameters:
#   $1 - the subnet (e.g. 192.168.1.200/24)
#
random_ip ()
{
	subnet="$1"
	addr="$(echo "${subnet%/*}" | ip_to_decimal)"
	netmask="${subnet#*/}"
	bitmask="$(((1 << (32 - netmask)) - 1))"

	bytes="0x$(dd if=/dev/urandom bs=1 count=4 2>/dev/null | xxd -p)"
	addr="$(((addr & (0xffffffff ^ bitmask)) + (bytes & bitmask)))"

	echo "${addr}" | decimal_to_ip
}

#
# Increments and prints the next IP address given the current one
#
# Depends: ip_to_decimal, decimal_to_ip
#
# Parameters:
#   $1 - the current IP address as subnet (e.g. 192.168.1.200/24)
#
# Return:
#   0 in case a new address was printed, or
#   1 otherwise (error or end of range)
#
next_ip ()
{
	subnet="$1"
	addr="$(echo "${subnet%/*}" | ip_to_decimal)"
	netmask="${subnet#*/}"
	bitmask="$(((1 << (32 - netmask)) - 1))"

	next="$(((addr & bitmask) + 1))"
	err="$((next & (0xffffffff ^ bitmask)))"
	[ "${err}" -ne 0 ] && return 1

	addr="$(((addr & (0xffffffff ^ bitmask)) + next))"
	echo "${addr}" | decimal_to_ip
}

#
# Check connection to the given remote host
#
# Depends: ping
# Requires: /dev/null
#
check_connection ()
{
	iface="$1"
	host="$2"
	ping -I "${iface}" -w 1 "${host}" >/dev/null 2>&1
}

#
# Scan and print a list of addressable network interfaces
#
# Depends:
#   log (logging.sh)
#   cat
# Requires: /sys/class/net/
#
scan_network_interfaces ()
{
	log "Scanning for network interfaces..."

	res=""
	for iface in /sys/class/net/*; do
		[ -r "${iface}/type" ] && type="$(cat "${iface}/type")"

		# check interface type and select only ARP interfaces
		# see kernel source include/uapi/linux/if_arp.h
		if [ -n "${type}" ] && [ "${type}" -lt 256 ]; then
			log "  Found: ${iface}"
			res="${res} ${iface}"
		else
			log "  Skip: ${iface}"
		fi
	done

	# echo without quotes to remove whitespaces
	[ -n "${res}" ] && echo ${res}
}

#
# Attempt to obtain an IP address for a given interface and check connection
#
# Depends:
#   log (logging.sh)
#   contains (string.sh)
#   decimal_to_ip, next_ip, random_ip, get_ip, check_connection
#   udhcpc, ifconfig
#
# Parameters:
#   iface=<interface>   network interface to configure (mandatory)
#   dhcp                attempt dhcp assignment
#   seq[=<tries>]       attempt sequencial assignment (default: 1 try)
#   rand[=<tries>]      attempt random assignemtn (default: 1 try)
#   verify=<host>       verify connection by pinging <host> (default: disabled)
#   hint=<ip>/<mask>    start sequencial assignment from <ip> upwards, the mask
#                       is used as random assignment pattern
#
# At least one of dhcp, seq and rand must be present at the command line.
# If seq is set to 0, then it will continue indefinitely, until an IP is
# assigned or an error occurs. If rand is set to 0, it will default to 1
#
# Return:
#   0 in case of successful setup of the interface, or
#   1 otherwise
#
config_network_interface ()
{
	iface=""
	dhcp=""
	seq=""
	rand=""
	verify=""
	hint="192.168.1.201/23"

	while [ $# -ne 0 ]; do
		case "$1" in
			iface=*)
				iface="${1#*=}"
				;;
			dhcp)
				dhcp=1
				;;
			seq*)
				tries="${1#*=}"
				seq="${tries:-1}"
				;;
			rand*)
				tries="${1#*=}"
				rand="${tries:-1}"
				;;
			hint=*)
				hint="${1#*=}"
				;;
			verify=*)
				verify="${1#*=}"
				;;
			*)
				;;
		esac
		shift
	done

	[ -z "${iface}" ] && return 1
	[ -z "${dhcp}${seq}${rand}" ] && return 1
	[ -n "${rand}" ] && [ "${rand}" -eq 0 ] && rand=1

	contains "${iface}" /sys/class/net/ && iface="${iface#/sys/class/net/}"
	log "Configuring network interface ${iface} for nfs..."

	# start with dhcp
	attempt="dhcp"

	# start sequencial assignment from here
	next_addr="${hint%/*}"
	subnet="${hint#*/}"
	netmask="$(echo "$((0xffffffff ^ ((1 << (32 - subnet)) - 1)))" | decimal_to_ip)"

	# configuration loop
	while true; do
		case "${attempt}" in
			dhcp)
				# if dhcp not requested, move to sequential
				[ -z "${dhcp}" ] && attempt="sequence=${seq}" && continue

				log "  Trying to get a lease with udhcpc..."
				udhcpc -n -t 1 -i "${iface}"
				sleep 0.2

				# move to sequential assignment
				attempt="sequence=${seq}"
				;;
			sequence=*)
				curr="${attempt#*=}"

				# if no sequencial assignment requested, move to random
				[ -z "${curr}" ] && attempt="random=${rand}" && continue

				# if not indefinite assinment and no more tries, move to random
				[ "${seq}" -ne 0 ] && [ "${curr}" -eq 0 ] && attempt="random=${rand}" && continue

				log "  Setting the next sequential IP address... [${curr}/${seq}]"
				log "    inet ${next_addr} netmask ${netmask}"
				ifconfig "${iface}" "${next_addr}" netmask "${netmask}" up

				# increment the address given the subnet
				next_addr="$(next_ip "${next_addr}/${subnet}")"

				# if no more addresses, move to random
				# else if not indefinite addressing, count down
				if [ -z "${next_addr}" ]; then
					attempt="random=${rand}"
				elif [ "${seq}" -ne 0 ]; then
					attempt="sequence=$((curr - 1))"
				fi
				;;
			random=*)
				curr="${attempt#*=}"

				# if no random assignment requested, or no more tries, abort
				[ -z "${curr}" ] || [ "${curr}" -eq 0 ] && attempt="abort" && continue

				# get a random address
				next_addr="$(random_ip "${hint}")"

				log "  Setting the next random IP address... [${curr}/${seq}]"
				log "    inet ${addr} netmask ${netmask}"
				ifconfig "${iface}" "${next_addr}" netmask "${netmask}" up

				# count down the tries
				attempt="random=$((curr - 1))"
				;;
			*)
				log "  Aborted. No IP address set"
				return 1
				;;
		esac

		# check assignment, if none, continue
		addr="$(get_ip "${iface}")" || continue
		log "    Assigned IP address ${addr}"

		# if requested, check connection
		if [ -n "${verify}" ]; then
			log -n "    Checking connection to ${verify}... "
			check_connection "${iface}" "${verify}" && log "OK" && break

			log "NOK"

			# if we tried dhcp and we got an IP, we abort manual assignment
			if [ "${attempt}" = "sequence=${seq}" ]; then
				log "  Aborting, leaving IP configured"
				return 1
			fi
		fi
	done

	log "Interface ${iface} has been configured with address ${addr}/${subnet}"
}

