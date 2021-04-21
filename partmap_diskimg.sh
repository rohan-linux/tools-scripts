#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

SIMG2DEV=$BASEDIR/../bin/simg2dev

declare -A DISK_SUPPORT_PARTITION=(
	["partition"]="gpt"
	["gpt"]="gpt"
	["dos"]="msdos"
	["mbr"]="msdos"
)

SYSTEM_DEVICE_CHECK=(
	"/dev/sr"
	"/dev/sda"
	"/dev/sdb"
	"/dev/sdc"
)

DISK_TARGET_CONFIG=()
DISK_TARGET=()
DISK_PARTMAP_FILE=
DISK_PARTMAP_LIST=()

#format = "$name:$type:$seek:$size:$file"
DISK_PART_IMAGE=()
DISK_DATA_IMAGE=()
DISK_PART_TYPE=

DISK_IMAGES_DIR="$(dirname "$(realpath "$(basename "$0")")")"
DISK_IMAGE_OUT="disk.img"
DISK_UPDATE_DEVICE=""
DO_UPDATE_PART_TABLE=false

function usage () {
	echo "usage: $(basename "$0") -f <partmap file>  [options]"
	echo ""
	echo " options:"
	echo -e "\t-t\t select update targets, ex> -t target ..."
	echo -e "\t-d\t path for the target images, default: '$DISK_IMAGES_DIR'"
	echo -e "\t-i\t partmap info"
	echo -e "\t-l\t listup <target ...>  in partmap list"
	echo -e "\t-s\t disk size: n GB (default $((DISK_SIZE / SZ_GB)) GB)"
	echo -e "\t-r\t disk margin size: n MB (default $((DISK_MARGIN / SZ_MB)) MB)"
	echo -e "\t-u\t update to device with <target> image, ex> -u /dev/sd? boot"
	echo -e "\t-n\t new disk image name (default $DISK_IMAGE_OUT)"
	echo -e "\t-p\t updates the partition table also. this option is valid when '-u'"
	echo -e "\t-o\t create <name>.loop and run losetup(loop device) to check created disk image with mount command"
	echo ""
	echo "Partmap struct:"
	echo "  fash=<>,<>:<>:<partition>:<start:hex>,<size:hex>"
	echo "  part   : gpt/dos(mbr) else ..."
	echo ""
	echo "DISK update:"
	echo "  $> sudo dd if=<path>/<image> of=/dev/sd? bs=1M"
	echo "  $> sync"
	echo ""
	echo "DISK mount: with '-t' option for test"
	echo "  $> sudo losetup -f"
	echo "  $> sudo losetup /dev/loopN <image>"
	echo "  $> sudo mount /dev/loopNpn <directory>"
	echo "  $> sudo losetup -d /dev/loopN"
	echo ""
	echo "Required packages:"
	echo "  parted"
}

SZ_KB=$((1024))
SZ_MB=$((SZ_KB * 1024))
SZ_GB=$((SZ_MB * 1024))

BLOCK_UNIT=$((512)) # FIX
DISK_MARGIN=$((500 * SZ_MB))
DISK_SIZE=$((8 * SZ_GB))

DISK_LOOP_DEVICE=
DO_LOOP_DEVICE=false
_SPACE_HEX_='            '
_SPACE_STR_='          '

function convert_byte_to_hn () {
	local val=$1 ret=$2

	if [[ $((val)) -ge $((SZ_GB)) ]]; then
		val="$((val / SZ_GB)).$(((val % SZ_GB) / SZ_MB)) G";
	elif [[ $((val)) -ge $((SZ_MB)) ]]; then
		val="$((val / SZ_MB)).$(((val % SZ_MB) / SZ_KB)) M";
	elif [[ $((val)) -ge $((SZ_KB)) ]]; then
		val="$((val / SZ_KB)).$((val % SZ_KB)) K";
	else
		val="$((val)) B";
	fi
	eval "$ret=\"${val}\""
}

function exec_partition () {
	local disk=$1 start=$2 size=$3
	local end=$((start + size))

	# unit:
	# ¡®s¡¯   : sector (n bytes depending on the sector size, often 512)
	# ¡®B¡¯   : byte
	if ! sudo parted --script "$disk" -- unit s mkpart primary $((start / BLOCK_UNIT)) $(($((end / BLOCK_UNIT)) - 1)); then
		[[ -n $DISK_LOOP_DEVICE ]] && sudo losetup -d "$DISK_LOOP_DEVICE"
	 	exit 1;
	fi
}

function exec_dd () {
	local disk=$1 start=$2 size=$3 file=$4 option=$5

	[[ -z $file ]] || [[ ! -f $file ]] && return;

	if ! sudo dd if="$file" of="$disk" seek="$((start / BLOCK_UNIT))" bs="$BLOCK_UNIT" "$option" status=none; then
		[[ -n $DISK_LOOP_DEVICE ]] && sudo losetup -d "$DISK_LOOP_DEVICE"
	 	exit 1;
	fi
}

function disk_partition () {
	local disk=$1

	[[ -n $DISK_UPDATE_DEVICE ]] && [[ $DO_UPDATE_PART_TABLE == false ]] && return

	# make partition table type (gpt/msdos)
	if [[ -n $DISK_PART_TYPE ]]; then
		if ! sudo parted "$disk" --script -- unit s mklabel "$DISK_PART_TYPE"; then
			[[ -n $DISK_LOOP_DEVICE ]] && sudo losetup -d $DISK_LOOP_DEVICE
			exit 1;
		fi
	fi

	printf " %s :" "$DISK_PART_TYPE" | tr '[:lower:]' '[:upper:]';
	printf " %d\n" "${#DISK_PART_IMAGE[@]}";

	local n=1
	for i in "${DISK_PART_IMAGE[@]}"; do
		part=$(echo "$i" | cut -d':' -f 1)
		seek=$(echo "$i" | cut -d':' -f 3)
		size=$(echo "$i" | cut -d':' -f 4)
		hnum=0

		convert_byte_to_hn "$size" hnum

		printf "  %s%s:" "${_SPACE_STR_:${#hnum}}" "$hnum";
		[[ ! -z $seek ]] && printf "%s0x%x:" "${_SPACE_HEX_:${#seek}}" "$seek";
		[[ ! -z $size ]] && printf "%s0x%x:" "${_SPACE_HEX_:${#size}}" "$size";
		[[ ! -z $part ]] && printf " %s\n" "$part"

		exec_partition "$disk" "$seek" "$size"
		((n++))
	done
	printf "\n"
}

function disk_write () {
	local disk=$1 str=$2
	local -n __array__=$3

	printf " %s:\n" "$str"

	for i in "${__array__[@]}"; do
		name=$(echo "$i" | cut -d':' -f 1)
		seek=$(echo "$i" | cut -d':' -f 3)
		size=$(echo "$i" | cut -d':' -f 4)
		file=$(echo "$i" | cut -d':' -f 5)
		hnum=0
		sparse=false

		convert_byte_to_hn "$size" hnum

		file "$file" | grep -q 'Android sparse' && sparse=true;

		printf "  %s%s:" "${_SPACE_STR_:${#hnum}}" "$hnum"
		[[ ! -z $seek ]] && printf "%s0x%x:" "${_SPACE_HEX_:${#seek}}" "$seek";
		[[ ! -z $size ]] && printf "%s0x%x:" "${_SPACE_HEX_:${#size}}" "$size";
		[[ ! -z $name ]] && printf " %s:" "$name"
		[[ ! -z $file ]] && printf " %s" "$(realpath "$file")"
		if [[ -z $file ]] || [[ ! -f $file ]]; then
			printf "\x1B[31m Not found \x1B[0m\n";
			continue;
		else
			if [[ $sparse == true ]]; then printf " (sparse)\n"; else printf "\n"; fi
		fi

		if [[ $sparse == true ]]; then
			[[ ! -f "$SIMG2DEV" ]] && SIMG2DEV="./simg2dev";
			if ! sudo $SIMG2DEV "$file" "$disk" "$seek" > /dev/null; then
				exit 1;
			fi
		else
			exec_dd "$disk" "$seek" "$size" "$file" "conv=notrunc"
		fi
	done
	printf "\n"
}

function create_image () {
	local disk image

	DISK_IMAGES_DIR=$(realpath "$DISK_IMAGES_DIR")
	if [[ ! -d $DISK_IMAGES_DIR ]]; then
		echo -e "\033[47;31m No such image dir: $DISK_IMAGES_DIR"
		exit 1;
	fi

	disk="$DISK_IMAGES_DIR/$DISK_IMAGE_OUT"
	[[ $DO_LOOP_DEVICE == true ]] && disk+=".loop";

	if [[ -n $DISK_UPDATE_DEVICE ]]; then
		if [[ ! -e $DISK_UPDATE_DEVICE ]]; then
			echo -e "\033[47;31m No such update device: $DISK_UPDATE_DEVICE \033[0m"
			exit 1;
		fi

		for i in "${SYSTEM_DEVICE_CHECK[@]}"; do
			if echo "$DISK_UPDATE_DEVICE" | grep "$i" -m ${#DISK_UPDATE_DEVICE}; then
				echo -ne "\033[47;31m Can be 'system' region: $DISK_UPDATE_DEVICE, continue y/n ?> \033[0m"
				read -r input
				[[ $input != 'y' ]] && exit 1;
				echo -ne "\033[47;31m Check again: $DISK_UPDATE_DEVICE, continue y/n ?> \033[0m"
				read -r input
				[[ $input != 'y' ]] && exit 1;
			fi
		done

		disk=$DISK_UPDATE_DEVICE
		DO_LOOP_DEVICE=false # not support
	fi

	if [[ ! -n $DISK_UPDATE_DEVICE ]]; then
		local size=$(((DISK_SIZE / SZ_MB) - (DISK_MARGIN / SZ_MB)))
		echo -e  "\033[1;32m\n Creat DISK Image\033[0m\n"
		echo -e  "\033[0;33m DISK : $(basename $disk)\033[0m"
		echo -e  "\033[0;33m SIZE : $((DISK_SIZE / SZ_MB)) MB - Margin $((DISK_MARGIN / SZ_MB)) MB = $size MB\033[0m"
		echo -e  "\033[0;33m PART : $(echo $DISK_PART_TYPE | tr '[:lower:]' '[:upper:]')\033[0m\n"
	else
		echo -e  "\033[1;32m\n Update DISK Images\033[0m\n"
		echo -e  "\033[0;33m DISK : $disk\033[0m"
		echo -ne "\033[0;33m IMAGE: \033[0m"
		for i in "${DISK_TARGET[@]}"; do
			echo -ne "\033[0;32m$i \033[0m"
		done
		echo -e "\033[0;33m \033[0m\n"
	fi

	# create disk image
	if [[ ! -n $DISK_UPDATE_DEVICE ]]; then
		if ! sudo dd if=/dev/zero of=$disk bs=1 count=0 seek=$((DISK_SIZE)) status=none; then
			exit 1;
		fi
	fi

	image=$disk
	if [[ $DO_LOOP_DEVICE == true ]]; then
		DISK_LOOP_DEVICE=$(sudo losetup -f)
		if ! sudo losetup "$DISK_LOOP_DEVICE" "$disk"; then
			exit 1;
		fi

		# Change disk name
		loop=$DISK_LOOP_DEVICE
		disk=$loop
		echo -e "\033[0;33m LOOP : $loop\033[0m\n"
	fi

	disk_partition "$disk"
	disk_write "$disk" "PART" DISK_PART_IMAGE
	disk_write "$disk" "DATA" DISK_DATA_IMAGE

	[[ -n $DISK_LOOP_DEVICE ]] && sudo losetup -d "$DISK_LOOP_DEVICE"

	echo -e "\033[0;33m RET : $(realpath $image)\033[0m\n"
	if ! echo "$disk" | grep '/dev/sd'; then
		echo -e "\033[0;33m $> sudo dd if=$(realpath $image) of=/dev/sd? bs=1M\033[0m"
		echo -e "\033[0;33m $> sync\033[0m\n"
		if [[ $DO_LOOP_DEVICE == true ]]; then
			echo -e "\033[0;33m Loop Device: \033[0m"
			echo -e "\033[0;33m\t $> sudo losetup -f\033[0m"
			echo -e "\033[0;33m\t $> sudo losetup ${DISK_LOOP_DEVICE} $(realpath $image)\033[0m"
			echo -e "\033[0;33m\t $> sudo mount ${DISK_LOOP_DEVICE}pX <mountpoint>\033[0m"
			echo -e "\033[0;33m\t $> sudo losetup -d ${DISK_LOOP_DEVICE}\033[0m\n"
		fi
	fi

	sync
}

function parse_images () {
	local offset=0 end

	for i in "${DISK_TARGET[@]}"; do
		local found=false;
		for n in "${DISK_PARTMAP_LIST[@]}"; do
			if [[ $i == "$n" ]]; then
				found=true
				break;
			fi
		done
		if [[ $found == false ]]; then
			echo -ne "\n\033[1;31m Not Support '$i' : $DISK_PARTMAP_FILE ( \033[0m"
			for t in "${DISK_PARTMAP_LIST[@]}"; do
				echo -n "$t "
			done
			echo -e "\033[1;31m)\033[0m\n"
			exit 1;
		fi
	done

	if [[ ${#DISK_TARGET[@]} -eq 0 ]]; then
		DISK_TARGET=(${DISK_PARTMAP_LIST[@]})
	fi

	for i in "${DISK_TARGET[@]}"; do
		local file="" part

		for n in "${DISK_TARGET_CONFIG[@]}"; do
			name=$(echo "$n" | cut -d':' -f 2)
			if [[ "$i" == "$name" ]]; then
				type=$(echo "$n" | cut -d':' -f 3)
				seek=$(echo "$n" | cut -d':' -f 4 | cut -d',' -f 1)
				size=$(echo "$n" | cut -d':' -f 4 | cut -d',' -f 2)
				file=$(echo "$n" | cut -d':' -f 5 | cut -d';' -f 1)
				break;
			fi
		done

		if [[ $((seek)) -lt $((end)) ]]; then
			printf "\x1B[31m Error:'%s' start:0x%x is overwrite previous end 0x%x \x1B[0m\n" "$name" "$seek" "$end"
			exit 1
		fi
		end=$((seek + size))

		# get partition type: gpt/dos
		for p in "${!DISK_SUPPORT_PARTITION[@]}"; do
			if [[ $p == "$type" ]]; then
				part=${DISK_SUPPORT_PARTITION[$p]};
				break;
			fi
		done

		[[ $((seek)) -gt $((offset)) ]] && offset=$((seek));
		[[ $((size)) -eq 0 ]] && size=$(printf "0x%x" $((DISK_SIZE - DISK_MARGIN - offset)));

		# set file real path
		[[ -n $file ]] && file="$DISK_IMAGES_DIR/$file";

		if [[ -n $part ]]; then
			if [[ -n $DISK_PART_TYPE ]] && [[ $part != "$DISK_PART_TYPE" ]]; then
				echo -e "\033[47;31m Another partition $type: $DISK_PART_TYPE !!!\033[0m";
				exit 1;
			fi
			DISK_PART_TYPE=$part
			DISK_PART_IMAGE+=("$name:$type:$seek:$size:$file");
		else
			DISK_DATA_IMAGE+=("$name:$type:$seek:$size:$file");
		fi
	done
}

function parse_partmap () {
	if [[ ! -f $DISK_PARTMAP_FILE ]]; then
		echo -e "\033[47;31m No such to partmap: $DISK_PARTMAP_FILE"
		exit 1;
	fi

	while read -r line; do
		line="${line//[[:space:]]/}"
		[[ "$line" == *"#"* ]] && continue;
		DISK_TARGET_CONFIG+=($line)
	done < $DISK_PARTMAP_FILE

	for i in "${DISK_TARGET_CONFIG[@]}"; do
		local val=$(echo "$i" | cut -d':' -f 2)
		DISK_PARTMAP_LIST+=( ${val} )
	done
}

function print_partmap () {
	if [[ $SHOW_PARTMAP_LIST == true ]]; then
		echo ""
		echo -en " Disk Targets: "
		for i in "${DISK_PARTMAP_LIST[@]}"; do
			echo -n "$i "
		done
		echo -e "\n"
		exit 0;
	fi

	if [[ $SHOW_PARTMAP_INFO == true ]]; then
		printf "\n"
		for i in "${DISK_TARGET_CONFIG[@]}"; do
			size=$(echo "$i" | cut -d':' -f4)
			size=$(echo "$size" | cut -d',' -f2)
			convert_byte_to_hn "$size" size
			printf "%s%s: %s\n" "${_SPACE_STR_:${#size}}" "$size" "$i"
		done
		printf "\n"
		exit 0;
	fi
}

SHOW_PARTMAP_LIST=false
SHOW_PARTMAP_INFO=false

function parse_arguments () {
	while getopts "f:t:d:s:r:n:u:plioeh" opt; do
	case $opt in
		f )	DISK_PARTMAP_FILE=$OPTARG;;
		t )	DISK_TARGET=("$OPTARG")
			until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
				DISK_TARGET+=("$(eval "echo \${$OPTIND}")")
				OPTIND=$((OPTIND + 1))
			done
			;;
		d )	DISK_IMAGES_DIR=$OPTARG;;
		s )	DISK_SIZE=$((OPTARG * SZ_GB));;
		r )	DISK_MARGIN=$((OPTARG * SZ_MB));;
		n )	DISK_IMAGE_OUT=$OPTARG;;
		u )	DISK_UPDATE_DEVICE=$OPTARG;;
		l )	SHOW_PARTMAP_LIST=true;;
		i )	SHOW_PARTMAP_INFO=true;;
		p )	DO_UPDATE_PART_TABLE=true;;
		o )	DO_LOOP_DEVICE=true;;
		e )
			vim "$DISK_PARTMAP_FILE"
			exit 0;;
		h )	usage;
			exit 1;;
	        * )	exit 1;;
	esac
	done
}

###############################################################################
# Run build
###############################################################################

parse_arguments "$@"

parse_partmap
print_partmap
parse_images
create_image

