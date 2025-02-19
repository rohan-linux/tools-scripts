#!/bin/bash
# (c) 2024, Junghyun, Kim
# Build Shell Script

function logerr() { echo -e "\033[1;31m$*\033[0m"; }
function logmsg() { echo -e "\033[0;33m$*\033[0m"; }
function logext() {
	echo -e "\033[1;31m$*\033[0m"
	exit 1
}

function exec_sh() {
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
	echo -e "\t-f\t\tflash table"
	echo -e "\t-t\t\tflash targets"
	echo -e "\t-d\t\timage path, default: '${_image_path}'"
	echo -e "\t-i\t\tshow flash-table info"
	echo -e "\t-l\t\tlistup target in flash-table"
	echo -e "\t-r\t\tsend reboot command after end of flash update"
	echo -e "\t-v\t\tverbose"
	echo ""
	echo "flash-table format:"
	echo -e "\t<dev>,<dev num>:<type>:<target>:<offset:hex>,<length:hex>:<image>\""
	echo -e "\t- dev     \tflash device name ex. mmc, spi"
	echo -e "\t- dev num \tflash device number ex. 0 -> mmc.0, 1 -> mmc.1"
	echo -e "\t- target  \tThe name of the target to update at the <offset>,<length>"
	echo -e "\t- type    \t'raw', 'mmcboot0', 'mmcboot1', 'gpt', 'dos'"
	echo -e "\t          \tnote. 'gpt' and 'dos' create a partition table."
	echo -e "\t- length  \t0 will take the remaining size of the device."
	echo -e "\t- image   \tthe image file name of the target, used on the host side."
	echo ""
	echo "command:"
	echo -e "\t$ sudo fastboot flash flash-table <flash_table>"
	echo -e "\t$ sudo fastboot flash <target> <image>"
	echo ""
}

function b_to_h() {
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

function parse_content() {
	while read line; do
		[[ -z ${line} ]] && continue
		[[ ${line} == "#"* ]] && continue

		line=$(echo ${line} | cut -d '#' -f 1 -)
		line=$(echo ${line} | tr -d ' ')
		_flash_tbl_content+=("${line}")
	done <${_flash_tbl_file}
}

function parse_target() {
	for i in "${_flash_tbl_content[@]}"; do
		_flash_tbl_target+=("$(echo ${i} | cut -d':' -f 3)")
	done
}

function print_target() {
	if [[ ${_show_table} == true ]]; then
		printf " %8s %10s %10s %12s %12s %12s\n" "Device" "Type" "Target" "Offset" "Length" "Image"
		for i in "${_flash_tbl_content[@]}"; do
			device="$(echo "${i}" | cut -d':' -f1)"
			ptype=$(echo "$(echo "${i}" | cut -d':' -f2)" | cut -d',' -f2)
			target=$(echo "$(echo "${i}" | cut -d':' -f3)" | cut -d',' -f2)
			offset=$(echo "$(echo "${i}" | cut -d':' -f4)" | cut -d',' -f2)
			length=$(echo "$(echo "${i}" | cut -d':' -f4)" | cut -d',' -f2)
			image=$(echo "$(echo "${i}" | cut -d':' -f5)" | cut -d',' -f2)
			hulen=
			b_to_h ${length} hulen
			printf " %8s %10s %10s %12s %12s(%5s) %s\n" ${device} ${ptype} ${target} ${offset} ${length} ${hulen} ${image}
		done
		exit 0
	fi

	if [[ ${_show_list} == true ]]; then
		echo -en "Flash targets: "
		for i in "${_flash_tbl_target[@]}"; do
			echo -n "${i} "
		done
		echo ""
		exit 0
	fi
}

__cdir="./"
function flash_update() {
	local flash_images=()
	local command=()

	for t in "${_flash_target[@]}"; do
		local image=""
		for n in "${_flash_tbl_content[@]}"; do
			local v="$(echo ${n} | cut -d':' -f 3)"
			if [[ "${t}" == "$v" ]]; then
				image="$(echo $(echo ${n} | cut -d':' -f 5) | cut -d';' -f 1)"
				[[ -z "${image}" ]] && continue
				image="${_image_path}/${image}"
				break
			fi
		done

		[[ -z "${image}" ]] && continue

		if [[ ! -f "${image}" ]]; then
			logext "Not found '${t}': ${image}"
		fi
		flash_images+=("${t}:$(realpath ${image})")
	done

	command=("sudo" "fastboot" "flash" "flash-table" "${_flash_tbl_file}")
	exec_sh "${command[*]}"
	if [[ $? -ne 0 ]]; then
		logext " - FAILED"
	fi

	for i in ${flash_images[@]}; do
		target=$(echo ${i} | cut -d':' -f 1)
		image=$(echo ${i} | cut -d':' -f 2)

		command=("sudo" "fastboot" "flash" "${target}" "${image}")
		exec_sh "${command[*]}"
		if [[ $? -ne 0 ]]; then
			logext " - FAILED"
		fi
	done
}

_image_path=$(realpath ${__cdir})
_flash_target=()
_reboot_done=false
_show_list=false
_show_table=false
_verbose=false

function flash_args() {
	while getopts "f:t:d:ilrvh" opt; do
		case ${opt} in
		f) _flash_tbl_file="${OPTARG}" ;;
		t)
			_flash_target=("${OPTARG}")
			until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
				_flash_target+=("$(eval "echo \${$OPTIND}")")
				OPTIND=$((OPTIND + 1))
			done
			;;
		d) _image_path="${OPTARG}" ;;
		r) _reboot_done=true ;;
		l) _show_list=true ;;
		i) _show_table=true ;;
		v) _verbose=true ;;
		h)
			usage
			exit 0
			;;
		*) exit 1 ;;
		esac
	done
}

###############################################################################
# Start flash update !!!
###############################################################################
_flash_tbl_file=""
_flash_tbl_content=()
_flash_tbl_target=()

flash_args "${@}"

if [[ ! -f ${_flash_tbl_file} ]]; then
	logext " No such flash table: ${_flash_tbl_file}"
fi

parse_content
parse_target
print_target

if [ -z ${_flash_target} ]; then
	_flash_target=(${_flash_tbl_target[@]})
fi

flash_update

if [[ ${_reboot_done} == true ]]; then
	exec_sh "sudo fastboot reboot"
fi
