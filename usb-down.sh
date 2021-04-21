#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BASEDIR=$(realpath $(cd "$(dirname "$0")" && pwd))

NXP3220_TOOLS_DIR="$BASEDIR/../bin"
SLSIAP_TOOLS_DIR="$BASEDIR/../../s5pxx18/fusing_tools"
nxp3220_usbdownloader="$NXP3220_TOOLS_DIR/linux-usbdownloader"
slsiap_usbdownloader="$SLSIAP_TOOLS_DIR/usb-downloader"

RESULTDIR=$(realpath "./")
DN_DEVICE=
USB_WAIT_TIME=	# sec

declare -A TARGET_PRODUCT_ID=(
	["3220"]="nxp3220"	# VID 0x2375 : Digit
	["3225"]="nxp3225"	# VID 0x2375 : Digit
	["1234"]="artik310"	# VID 0x04e8 : Samsung
	["1234"]="slsiap"	# VID 0x04e8 : Samsung
)

declare -A USBDOWNLOADER_BIN=(
	["nxp3220"]="$nxp3220_usbdownloader"
	["nxp3225"]="$nxp3220_usbdownloader"
	["artik310"]="$nxp3220_usbdownloader"
	["slsiap"]="$slsiap_usbdownloader"
)
usbdownloader_bin=""

function err () { echo -e "\033[0;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

function usage () {
	echo "usage: $(basename "$0") [-f config] [options] "
	echo ""
	echo " options:"
	echo -e "\t-f\t download config file"
	echo -e "\t-l\t download files"
	echo -e "\t\t EX> $(basename "$0") -f <config> -l <path>/file1 <path>/file2"
	echo -e "\t-s\t wait sec for next download"
	echo -e "\t-w\t wait sec for usb connect"
	echo -e "\t-e\t open download config file"
	echo -e "\t-p\t encryted file transfer"
	echo -e "\t-d\t download image path, default:'$RESULTDIR'"
	echo -e "\t-t\t set usb device name, this name overwrite configs 'TARGET' field"
	echo -e "\t\t support device [nxp3220,nxp3225,artik310,slsiap]"
	echo -e ""
}

function get_prefix_element () {
	local value=$1			# $1 = store the prefix's value
	local params=("${@}")
	local prefix=("${params[1]}")	# $2 = search prefix in $2
	local images=("${params[@]:2}")	# $3 = search array

	for i in "${images[@]}"; do
		if [[ "$i" = *"$prefix"* ]]; then
			local comp="$(echo "$i" | cut -d':' -f 2)"
			comp="$(echo "$comp" | cut -d',' -f 1)"
			comp="$(echo -e "${comp}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			eval "$value=(\"${comp}\")"
			break
		fi
	done
}

function get_usb_device () {
	local value=$1			# $1 = store the prefix's value
	local counter=0

	if [[ -n $USB_WAIT_TIME ]]; then
		msg " Wait $USB_WAIT_TIME sec connect";
	fi

	while true; do
		for i in "${!TARGET_PRODUCT_ID[@]}"; do
			local id="$(lsusb | grep "$i" | cut -d ':' -f 3 | cut -d ' ' -f 1)"
			if [ "$i" == "$id" ]; then
				id=${TARGET_PRODUCT_ID[$i]}
				eval "$value=(\"${id}\")"
				return
			fi
		done

		if [[ -n $USB_WAIT_TIME ]]; then
			counter=$((counter+1))
			sleep 1
		fi

		if [[ "$counter" -ge "$USB_WAIT_TIME" ]]; then
			err " Not found usb device !!!";
			exit 1
		fi
	done

	err " Not suport $id !!!"
	err "${!TARGET_PRODUCT_ID[@]}"
	exit 1;
}

function usb_download () {
	local device="$1" file="$2" argument="$3"
	local devopt=${USBDOWNLOADER_BIN["$device"]}
	local bin="$(echo $devopt | cut -d ':' -f1)"
	local option command

	if [[ -n ${argument} ]]; then
		option=$argument
	else
		option=${devopt#$usbdownloader_bin}
		[[ $option ]] && option="$(echo $devopt | cut -d ':' -f2)"
		option="-f $file $option"
	fi

	command="${bin} -t ${device} ${option}"

	msg " $> $command"
	if ! sudo bash -c "${command}"; then
		exit 1;
	fi
	msg " DOWNLOAD: DONE\n"
}

function usb_download_list () {
	local device=""
	local images=("${@}")	# IMAGES

	get_prefix_element device "TARGET" "${images[@]}"
	if [ -z "$DN_DEVICE" ]; then
		get_usb_device device
		DN_DEVICE=$device # set DN_DEVICE with config file
	else
		device=$DN_DEVICE # overwrite device with input device parameter with '-t'
	fi

	msg "##################################################################"
	msg " CONFIG DEVICE: $device"
	msg "##################################################################"
	msg ""

	for i in "${images[@]}"; do
		local opts file
		[[ "$i" = *"TARGET"* ]] && continue;
		[[ "$i" = *"BOARD"* ]] && continue;

		opts=$(echo "$i" | cut -d':' -f 2)
		opts="$(echo "$opts" | tr '\n' ' ')"
		opts="$(echo "$opts" | sed 's/^[ \t]*//;s/[ \t]*$//')"
		file=$(echo "$opts" | cut -d' ' -f 2)

		# reset load command with current file path
		if [[ ! -e $file ]]; then
			file=$(basename "$file")
			if [[ ! -e $file ]]; then
				err " DOWNLOAD: No such file $file"
				exit 1
			fi
			local opt="$(echo "$opts" | cut -d' ' -f 1)"
			file=./$file
			opts="$opt $file"
		fi

		usb_download "$device" "" "$opts"

		sleep "$DN_SLEEP_SEC"	# wait for next connect
	done
}

# input parameters
# $1 = download file array
function usb_download_image () {
	local files=("${@}")	# IMAGES
	local device=$DN_DEVICE

	if [[ -z $DN_DEVICE ]]; then
		get_usb_device device
	fi

	msg "##################################################################"
	msg " LOAD DEVICE: $device"
	msg "##################################################################"
	msg ""

	for i in "${files[@]}"; do
		i=$(realpath "$RESULTDIR/$i")
		if [[ ! -f $i ]]; then
			err " No such file: $i..."
			exit 1;
		fi

		if [[ -z $device ]]; then
			err " No Device ..."
			usage
			exit 1;
		fi

		usb_download "$device" "$i" ""
		sleep "$DN_SLEEP_SEC"
	done
}

DN_LOAD_TARGETS=()
DN_LOAD_CONFIG=
EDIT_FILE=false
DN_ENCRYPTED=false
DN_SLEEP_SEC=2

while getopts 'hf:l:t:s:d:w:ep' opt
do
        case $opt in
        f )	DN_LOAD_CONFIG=$OPTARG;;
        t )	DN_DEVICE=$OPTARG;;
        l )	DN_LOAD_TARGETS=("$OPTARG")
		until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z $(eval "echo \${$OPTIND}") ]]; do
			DN_LOAD_TARGETS+=($(eval "echo \${$OPTIND}"))
                	OPTIND=$((OPTIND + 1))
		done
		;;
	e )	EDIT_FILE=true;;
	p )	DN_ENCRYPTED=true;;
	s )	DN_SLEEP_SEC=$OPTARG;;
	w )	USB_WAIT_TIME=$OPTARG;;
	d )	RESULTDIR=$(realpath "$OPTARG");;
        h | *)
        	usage
		exit 1;;
		esac
done

if [[ $EDIT_FILE == true ]]; then
	if [[ ! -f $DN_LOAD_CONFIG ]]; then
		err " No such file: $DN_LOAD_CONFIG"
		exit 1
	fi

	vim "$DN_LOAD_CONFIG"
	exit 0
fi

if [[ ! -z $DN_LOAD_CONFIG ]]; then
	if [[ ! -f $DN_LOAD_CONFIG ]]; then
		err " No such config: $DN_LOAD_CONFIG"
		exit 1
	fi

	# include input file
	source "$DN_LOAD_CONFIG"

	if [[ $DN_ENCRYPTED == false ]]; then
		usb_download_list "${DN_IMAGES[@]}"
	else
		usb_download_list "${DN_ENC_IMAGES[@]}"
	fi
fi

if [[ ${#DN_LOAD_TARGETS} -ne 0 ]]; then
	usb_download_image "${DN_LOAD_TARGETS[@]}"
fi
