#!/bin/bash
#

OUTPUT_DIR="$(realpath $(dirname $(realpath "${BASH_SOURCE}")))"
FASTBOOT_DEVICE= #"FPGA-AB"

declare -A FASTBOOT_IMAGES=(
	["DTB"]="  0x80600000 : ${OUTPUT_DIR}/linux.dtb"
	["LINUX"]="0x81000000 : ${OUTPUT_DIR}/Image"
	["ROOT"]=" 0x82000000 : ${OUTPUT_DIR}/rootfs.cpio"
)

function logerr() { echo -e "\033[1;31m$*\033[0m"; }
function logmsg() { echo -e "\033[0;33m$*\033[0m"; }
function logext() {
    echo -e "\033[1;31m$*\033[0m"
    exit 1
}

function fastboot_download() {
	logmsg "Fastboot Download"

	for c in ${!FASTBOOT_IMAGES[*]}; do
		local ctx="${FASTBOOT_IMAGES[${c}]}"
		local buf=$(echo ${ctx} | cut -d':' -f1 | sed 's/^[ \t]*//;s/[ \t]*$//;s/\s\s*/ /g')
		local img=$(echo ${ctx} | cut -d':' -f2 | sed 's/^[ \t]*//;s/[ \t]*$//;s/\s\s*/ /g')
		local cmd=()

		if [[ ! -f ${img} ]]; then
			logerr "Not found ${c} : ${img}"
			continue
		fi
		fsz=$(du -sb ${img} | awk '{ print $1 }')
		# Align 1MB
		len=$((((fsz + ((1024 *1024) - 1))/(1024 *1024)) * (1024*1024)))
		printf -v len '0x%x' ${len}

		logmsg  "[${c}]"

		cmd=( "fastboot" )
		[[ -n ${FASTBOOT_DEVICE} ]] && cmd+=( "-s ${FASTBOOT_DEVICE}" );
		cmd+=( "oem run:fastboot_buf ${buf} ${len}" )

		logmsg  " -ADDRESS: ${buf}, LENGTH: ${len}"
		logmsg  " $ ${cmd[*]}"
		bash -c "${cmd[*]}"

		cmd=( "fastboot" )
		[[ -n ${FASTBOOT_DEVICE} ]] && cmd+=( "-s ${FASTBOOT_DEVICE}" );
		cmd+=( "boot ${img}" )

		logmsg  " - DOWNLOAD"
		logmsg  " $ ${cmd[*]}"
		bash -c "${cmd[*]}"

		logmsg ""
	done
}

function fastboot_exit() {
	logmsg "Fastboot EXIT"
	local cmd="fastboot continue"
	logmsg  " $ ${cmd}"
	bash -c "${cmd}"
}

function fastboot_usage() {
	echo " Usage: Please run this script as root or using sudo!"
	echo -e "\t$ sudo $(basename "${0}") <option>"
	echo " option:"
	echo -e "\t-d <DEVICE>\t specify a device $ fastboot devices"
	echo -e "\t-h\t\t show help"
	echo ""
}

function fastboot_args() {
	while getopts "d:h" opt; do
		case ${opt} in
		d)	FASTBOOT_DEVICE="${OPTARG}";;
		h)	fastboot_usage
			exit 0
			;;
		*)	exit 1 ;;
		esac
	done
}

fastboot_args "${@}"

if [[ $(id -u) -ne 0 ]]; then
	logext "Please run this script as root or using sudo!"
fi

fastboot_download
fastboot_exit
