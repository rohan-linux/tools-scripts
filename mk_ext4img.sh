##!/bin/bash
# (c) 2024, Junghyun, Kim
# Build Shell Script

function logerr() { echo -e "\033[1;31m$*\033[0m"; }
function logmsg() { echo -e "\033[0;33m$*\033[0m"; }
function logext() {
	echo -e "\033[1;31m$*\033[0m"
	exit 1
}

function exec_shell() {
	local exec=${1} err

	# remove first,last space and set multiple space to single space
	exec="$(echo "${exec}" | sed 's/^[ \t]*//;s/[ \t]*$//;s/\s\s*/ /g')"
	logmsg " $ ${exec}"

	if [[ ${_verbose} == true ]]; then
		bash -c "${exec}"
		err=${?}
	else
		bash -c "${exec}" >/dev/null 2>&1
		err=${?}
	fi

	return ${err}
}

function usage() {
	echo "usage: $(basename $0) <option>"
	echo ""
	echo "option:"
	echo -e "\t-d\t\troot directory"
	echo -e "\t-l\t\tdisk label (optional)"
	echo -e "\t-s\t\tsize(nG, nM), minimum size is 1M"
	echo -e "\t-o\t\toutput image name ({output}.ext4, {output}.simg)"
	echo -e "\t\t\textend: .ext4 = ext4 image, .simg = android sparse image"
	echo ""
}

function btoh() {
	local val=${1} ret=${2}
	local KB=$((1024)) MB=$((1024 * 1024)) GB=$((1024 * 1024 * 1024))

	if [[ $((val)) -ge $((GB)) ]]; then
		val="$((val / $GB))G"
	elif [[ $((val)) -ge $((MB)) ]]; then
		val="$((val / $MB))M"
	elif [[ $((val)) -ge $((KB)) ]]; then
		val="$((val / $KB))K"
	else
		val="$((val))B"
	fi
	eval "${ret}=\"${val}\""
}

function htob() {
	local input=${1} byte=${2}
	local value=${input%[GgMmKk]}
	local unit=${input: -1}

	if [[ ${unit} == "G" || ${unit} == "g" ]]; then
		value=$((value * 1024 * 1024 * 1024))
	elif [[ ${unit} == "M" || ${unit} == "m" ]]; then
		value=$((value * 1024 * 1024))
	elif [[ ${unit} == "K" || ${unit} == "k" ]]; then
		value=$((value * 1024))
	else
		value=$((value))
	fi

	eval "${byte}=\"${value}\""
}

function gen_image_ext4() {
	local ext4img aospimg # android sparse image
	local count
	local bs="1M"
	local command=()

	if [[ ! -d ${_image_path} ]]; then
		logext "No such image directory: ${_image_path}"
	fi

	if [[ -z ${_image_output} ]]; then
		_image_output=${_image_path}
	fi

	ext4img="${_image_output}.ext4"
	aospimg="${_image_output}.simg"

	htob ${_image_size} count
	count=$((count / 1024 / 1024))
	logmsg "Make EXT4: ${ext4img} and ${aospimg}, size ${_image_size}byte"

	command=("dd"
		"if=/dev/zero"
		"of=${ext4img}"
		"bs=${bs}"
		"count=${count}"
		"conv=sparse")
	exec_shell "${command[*]}"
	if [[ $? -ne 0 ]]; then
		logext " - FAILED"
	fi

	command=("mkfs.ext4")
	[[ -n ${_image_label} ]] && command+=("-L ${_image_label}")
	command+=("-d ${_image_path}" "${ext4img}")
	exec_shell "${command[*]}"
	if [[ ! -f ${ext4img} ]]; then
		logext " - FAILED"
	fi

	command=("img2simg" "${ext4img}" "${aospimg}")
	exec_shell "${command[*]}"
	if [[ $? -ne 0 ]]; then
		logext " - FAILED"
	fi
}

_image_path=""
_image_label=""
_image_size=""
_image_output=""
_verbose=false

function gen_image_args() {
	while getopts "d:l:s:o:vh" opt; do
		case ${opt} in
		d)	_image_path="${OPTARG}" ;;
		l)	_image_label="${OPTARG}" ;;
		s)	_image_size="${OPTARG}" ;;
		o)	_image_output="${OPTARG}" ;;
		v)	_verbose=true ;;
		h)	usage
			exit 0
			;;
		*)	exit 1 ;;
		esac
	done
}

gen_image_args "${@}"
gen_image_ext4
