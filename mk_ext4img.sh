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

	if [[ ${VERBOSE} == true ]]; then
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
	echo -e "\t-f\t\tcpio image file - Use fakeroot to maintain root permission."
	echo -e "\t-l\t\tdisk label (optional)"
	echo -e "\t-s\t\tsize(nG, nM), minimum size is 1M"
	echo -e "\t-o\t\toutput image name ({output}.ext4, {output}.img)"
	echo -e "\t\t\textend: .ext4 = ext4 image, .img = android sparse image"
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

function gen_ext4() {
	local ext4img aospimg # android sparse image
	local count
	local bs="1M"
	local command=()

	if [[ ! -d ${IMAGE_DIR} && ! -f ${IMAGE_FILE} ]]; then
		logerr "No such image directory '${IMAGE_DIR}' or file '${IMAGE_FILE}'"
		usage
		exit 1
	fi

	if [[ -z ${IMAGE_SIZE} || -z ${IMAGE_OUT} ]]; then
		logerr "Not defined output name or ext4 size !!!"
		usage
		exit 1
	fi

	ext4img="${IMAGE_OUT}.ext4"
	aospimg="${IMAGE_OUT}.img"

	htob ${IMAGE_SIZE} count
	count=$((count / 1024 / 1024))
	logmsg " Make EXT4: ${ext4img} and ${aospimg}, size ${IMAGE_SIZE}byte"

	if [[ -d ${IMAGE_DIR} ]]; then
		command=("dd" "if=/dev/zero" "of=${ext4img}" "bs=${bs}" "count=${count}" "conv=sparse")
		exec_shell "${command[*]}"
		if [[ $? -ne 0 ]]; then
			logext " - FAILED"
		fi

		command=("mkfs.ext4")
		[[ -n ${IMAGE_LABEL} ]] && command+=("-L ${IMAGE_LABEL}")
		command+=("-d ${IMAGE_DIR}" "${ext4img}")
		exec_shell "${command[*]}"
		if [[ ! -f ${ext4img} ]]; then
			logext " - FAILED"
		fi
	else
		fakeroot sh -c "
			mkdir -p rootfs
			cd rootfs
			cpio -idmv < ../${IMAGE_FILE} >/dev/null 2>&1
			cd ..
			dd if=/dev/zero of=${IMAGE_OUT}.ext4 bs=1M count=${count}
			mkfs.ext4 -d rootfs ${IMAGE_OUT}.ext4"
		if [[ ! -f ${ext4img} ]]; then
			logext " - FAILED"
		fi
	fi

	command=("img2simg" "${ext4img}" "${aospimg}")
	exec_shell "${command[*]}"
	if [[ $? -ne 0 ]]; then
		logext " - FAILED"
	fi
}

IMAGE_DIR=""
IMAGE_FILE="" # cpio image
IMAGE_LABEL=""
IMAGE_SIZE=""
IMAGE_OUT=""
VERBOSE=false

function gen_args() {
	while getopts "d:f:l:s:o:vh" opt; do
		case ${opt} in
		d)	IMAGE_DIR="${OPTARG}" ;;
		f)	IMAGE_FILE="${OPTARG}" ;;
		l)	IMAGE_LABEL="${OPTARG}" ;;
		s)	IMAGE_SIZE="${OPTARG}" ;;
		o)	IMAGE_OUT="${OPTARG}" ;;
		v)	VERBOSE=true ;;
		h)	usage
			exit 0
			;;
		*)	exit 1 ;;
		esac
	done
}

gen_args "${@}"
gen_ext4
