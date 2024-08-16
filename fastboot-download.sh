#!/bin/bash
#

OUTPUT_DIR="$(realpath $(dirname $(realpath "${BASH_SOURCE}")))"

declare -A FASTBOOT_IMAGES=(
	["DTB"]="  0x80600000 0x0100000 : ${OUTPUT_DIR}/linux.dtb"
	["LINUX"]="0x81000000 0x1000000 : ${OUTPUT_DIR}/Image"
	["ROOT"]=" 0x82000000 0x3000000 : ${OUTPUT_DIR}/rootfs.cpio"
)

FASTBOOT_EXIT="fastboot continue"

function logerr() { echo -e "\033[1;31m$*\033[0m"; }
function logmsg() { echo -e "\033[0;33m$*\033[0m"; }
function logext() {
    echo -e "\033[1;31m$*\033[0m"
    exit 1
}

if [[ $(id -u) -ne 0 ]]; then
	logext "Please run this script as root or using sudo!"
fi

logmsg "Fastboot Download"
for c in ${!FASTBOOT_IMAGES[*]}; do
	ctx="${FASTBOOT_IMAGES[${c}]}"
	buf=$(echo ${ctx} | cut -d':' -f1 | sed 's/^[ \t]*//;s/[ \t]*$//;s/\s\s*/ /g')
	img=$(echo ${ctx} | cut -d':' -f2 | sed 's/^[ \t]*//;s/[ \t]*$//;s/\s\s*/ /g')

	if [[ ! -f ${img} ]]; then
		logerr "Not found ${c} : ${img}"
		continue
	fi

	logmsg  "[${c}]"
	cmd="fastboot oem run:fastboot_buf ${buf}"
	logmsg  " set buffer"
	logmsg  " $ ${cmd}"
	bash -c "${cmd}"

	cmd="fastboot boot ${img}"
	logmsg  " download"
	logmsg  " $ ${cmd}"
	bash -c "${cmd}"

	logmsg ""
done

logmsg ""
logmsg "Fastboot EXIT"
logmsg  " $ ${FASTBOOT_EXIT}"
bash -c "${FASTBOOT_EXIT}"
