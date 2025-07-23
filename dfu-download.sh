#!/bin/bash
#

DFU_IMAGES=(
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

DFU_VERBOSE=false
DFU_SIGN_IMAGE=false
DFU_LIST_IMAGE=false
DFU_OUTPUT_PATH="$(pwd)"
DFU_TARGETS=()

function dfu_download() {
	logmsg "DFU Wait Connection ..."

	while true; do
		if dfu-util -l | grep -qw "DeepX"; then
			break
		else
			sleep 1
		fi
	done

	for img in ${DFU_TARGETS[*]}; do
		img=$(realpath ${DFU_OUTPUT_PATH}/${img})
		if [[ ! -f ${img} ]]; then
			logerr "Not found : ${img}"
			continue
		fi

		if ! dfu-util -l | grep -qw "DeepX"; then
			logext "Error disconnected, Check Connection !!!"
		fi

		if [[ ${DFU_SIGN_IMAGE} == true ]]; then
			img="$(dirname ${img})/$(echo $(basename ${img}) | cut -d '.' -f1).sig"
		fi

		logmsg  "DFU Image: ${img}"

		cmd=( "dfu-util -D ${img}" )
		[[ ${DFU_VERBOSE} == false ]] && cmd+=( ">/dev/null 2>&1" )

		logmsg  " $ ${cmd[*]}"
		bash -c "${cmd[*]}"
		if [[ ${?} -ne 0 ]]; then
			logerr "Error download: ${img}"
			logerr "- Please check if the image is valid !!!"
		fi

		cmd=( "dfu-util -e" )
		[[ ${DFU_VERBOSE} == false ]] && cmd+=( ">/dev/null 2>&1" )
		bash -c "${cmd[*]}"
		logmsg  "DFU Done"
		sleep 1
	done
}

function dfu_usage() {
	echo -e "\t$ sudo $(basename "${0}") <option>"
	echo " option:"
	echo -e "\t-t\t\t download targets"
	echo -e "\t-s\t\t download the signing images"
	echo -e "\t-l\t\t show download images"
	echo -e "\t-p\t\t set images path"
	echo -e "\t-v\t\t verbose"
	echo -e "\t-h\t\t show help"
	echo ""
}

while getopts "t:p:slvh" opt; do
	case ${opt} in
	t)	DFU_TARGETS=("${OPTARG}")
			until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
				DFU_TARGETS+=("$(eval "echo \${$OPTIND}")")
				OPTIND=$((OPTIND + 1))
			done
			;;
	p)	DFU_OUTPUT_PATH=${OPTARG};;
	s)	DFU_SIGN_IMAGE=true;;
	l)	DFU_LIST_IMAGE=true;;
	v)	DFU_VERBOSE=true;;
	h)	dfu_usage
		exit 0
		;;
	*)	exit 1 ;;
	esac
done

if [[ ${DFU_LIST_IMAGE} == true ]]; then
	logmsg "Download Images:"
	for img in ${DFU_IMAGES[*]}; do
		logmsg "- ${img}"
	done
	exit 0
fi

if [[ -z ${DFU_TARGETS} ]]; then
	DFU_TARGETS=(${DFU_IMAGES[@]})
fi

dfu_download
