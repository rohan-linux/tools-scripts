#!/bin/bash
#

XMODEM_IMAGES=(
	"dxv3_bl2.img"
	"bootfw.img"
	"ddrfw.img"
	"tfw.img"
	"bl31.img"
	"u-boot.img"
)

function logerr() { echo -e "\033[1;31m$*\033[0m"; }
function logmsg() { echo -e "\033[0;33m$*\033[0m"; }
function logext() {
    echo -e "\033[1;31m$*\033[0m"
    exit 1
}

XMODEM_DEVICE="/dev/ttyUSBx"
XMODEM_VERBOSE=true
XMODEM_SIGN_IMAGE=false
XMODEM_LIST_IMAGE=false
XMODEM_OUTPUT_PATH="$(pwd)"
XMODEM_TARGETS=()

function xmodem_download() {
	logmsg "Check xmodem tty: ${XMODEM_DEVICE} ..."

	if [[ ! -e ${XMODEM_DEVICE} ]]; then
		logext " - Not found tty: ${XMODEM_DEVICE}"
	fi

	for img in ${XMODEM_TARGETS[*]}; do
		img=$(realpath ${XMODEM_OUTPUT_PATH}/${img})
		if [[ ! -f ${img} ]]; then
			logerr "Not found : ${img}"
			continue
		fi

		if [[ ${XMODEM_SIGN_IMAGE} == true ]]; then
			img="$(dirname ${img})/$(echo $(basename ${img}) | cut -d '.' -f1).sig"
		fi

		logmsg  "XMODEM Image: ${img}"

		cmd=( "./xmodem ${XMODEM_DEVICE} ${img}" )
		[[ ${XMODEM_VERBOSE} == false ]] && cmd+=( ">/dev/null 2>&1" )

		logmsg  " $ ${cmd[*]}"
		bash -c "${cmd[*]}"
		if [[ ${?} -ne 0 ]]; then
			logerr "Error download: ${img}"
			logerr "- Please check if the image is valid !!!"
		fi
		logmsg  "XMODEM Done"
		sleep 1
	done
}

function xmodem_usage() {
	echo -e "\t$ sudo $(basename "${0}") <option>"
	echo " option:"
	echo -e "\t-d\t\t XMODEM device (-d /dev/ttyUSBx)"
	echo -e "\t-t\t\t download targets"
	echo -e "\t-s\t\t Download the signing images"
	echo -e "\t-l\t\t List download images"
	echo -e "\t-p\t\t Set images path"
	echo -e "\t-v\t\t Verbose"
	echo -e "\t-h\t\t Show help"
	echo ""
}

while getopts "d:t:p:slvh" opt; do
	case ${opt} in
	d)	XMODEM_DEVICE=${OPTARG};;
	t)	XMODEM_TARGETS=("${OPTARG}")
			until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
				XMODEM_TARGETS+=("$(eval "echo \${$OPTIND}")")
				OPTIND=$((OPTIND + 1))
			done
			;;
	p)	XMODEM_OUTPUT_PATH=${OPTARG};;
	s)	XMODEM_SIGN_IMAGE=true;;
	l)	XMODEM_LIST_IMAGE=true;;
	v)	XMODEM_VERBOSE=true;;
	h)	xmodem_usage
		exit 0
		;;
	*)	exit 1 ;;
	esac
done

if [[ ${XMODEM_LIST_IMAGE} == true ]]; then
	logmsg "Download Images:"
	for img in ${XMODEM_IMAGES[*]}; do
		logmsg "- ${img}"
	done
	exit 0
fi

if [[ -z ${XMODEM_TARGETS} ]]; then
	XMODEM_TARGETS=(${XMODEM_IMAGES[@]})
fi

xmodem_download
