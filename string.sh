#
# Utilities for processing text
#

[ -n "${_lib_string_sh_loaded}" ] && return 0
readonly _lib_string_sh_loaded=1

#
# Join arguments by the delimiter and print the result
#
# Parameters:
#   $1 - delimiter
#   $@ - arguments to join
#
# Example:
#   join , a b c => a,b,c
#
join ()
{
	IFS="$1" shift; echo "$*"
}

#
# Check if second argument is contained within the first argument
#
# Parameters:
#   $1 - string
#   $2 - substring
#
# Return:
#   0 - substring is contained within string, and
#   1 - otherwise
#
contains () {
    string="$1"
    substring="$2"
    test "${string#*$substring}" != "$string"
}
