#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

RESULTDIR=$(realpath "./")

FASTBOOT_PARTMAP_FILE=
FASTBOOT_PARTMAP_CONFIG=()
FASTBOOT_PARTMAP_LIST=()

FASTBOOT_TARGETS=()
FASTBOOT_REBOOT=false

function usage () {
	echo "usage: $(basename "$0") -f [partmap file] <targets> <options>"
	echo ""
	echo "[OPTIONS]"
	echo "  -d : image path for fastboot, default: '$RESULTDIR'"
	echo "  -i : partmap info"
	echo "  -l : listup target in partmap list"
	echo "  -r : fastboot reboot command after end of fastboot"
	echo ""
	echo "Partmap format:"
	echo "  fash=<device>,<device number>:<target>:<device area>:<start:hex>,<size:hex>:<image>\""
	echo "  device      : support 'mmc','spi'"
	echo "  device area : for 'mmc' = 'bootsector', 'raw', 'partition', 'gpt', 'mbr'"
	echo "              : for 'spi' = 'raw'"
	echo ""
	echo "Fastboot command:"
	echo "  1. sudo fastboot flash partmap <partmap.txt>"
	echo "  2. sudo fastboot flash <target> <image>"
	echo ""
}

SZ_KB=$((1024))
SZ_MB=$((SZ_KB * 1024))
SZ_GB=$((SZ_MB * 1024))
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

function parse_partmap () {
	if [[ ! -f $FASTBOOT_PARTMAP_FILE ]]; then
		echo -e "\033[47;31m No such partmap: $FASTBOOT_PARTMAP_FILE \033[0m"
		echo -e "\n"
		exit 1;
	fi

	while read -r line; do
		line="${line//[[:space:]]/}"
		[[ "$line" == *"#"* ]] && continue;
		FASTBOOT_PARTMAP_CONFIG+=($line)
	done < "$FASTBOOT_PARTMAP_FILE"

	for i in "${FASTBOOT_PARTMAP_CONFIG[@]}"; do
		FASTBOOT_PARTMAP_LIST+=( "$(echo "$i" | cut -d':' -f 2)" )
	done
}

function print_partmap () {
	if [[ $SHOW_PARTMAP_LIST == true ]]; then
		echo -e  " Partmap : $FASTBOOT_PARTMAP_FILE"
		echo -en " Targets :"
		for i in "${FASTBOOT_PARTMAP_LIST[@]}"; do
			echo -n " $i"
		done
		echo -e "\n"
		exit 0;
	fi

	if [[ $SHOW_PARTMAP_INFO == true ]]; then
		echo -e " Partmap : $FASTBOOT_PARTMAP_FILE"
		printf "\n"
		for i in "${FASTBOOT_PARTMAP_CONFIG[@]}"; do
			size=$(echo "$i" | cut -d':' -f4)
			size=$(echo "$size" | cut -d',' -f2)
			convert_byte_to_hn "$size" size
			printf "%s%s: %s\n" "${_SPACE_STR_:${#size}}" "$size" "$i"
		done
		printf "\n"
		exit 0;
	fi
}

function do_fastboot () {
	local partmap_targets=()

	for i in "${FASTBOOT_TARGETS[@]}"; do
		local image=""
		for n in "${FASTBOOT_PARTMAP_CONFIG[@]}"; do
			if [[ "$i" == $(echo "$n" | cut -d':' -f 2) ]]; then
				image="$(echo "$n" | cut -d':' -f 5 | cut -d';' -f 1)"
				[[ -z $image ]] && continue;
				image="$RESULTDIR/$image"
				break;
			fi
		done

		[[ -z $image ]] && continue;

		if [[ ! -f $image ]]; then
			image=./$(basename "$image")
			if [[ ! -f $image ]]; then
				echo -e "\033[47;31m Not found '$i': $image\033[0m"
				continue
			fi
		fi
		partmap_targets+=("$i:$(realpath "$image")");
	done

	echo -e "\033[0;33m Partmap: $FASTBOOT_PARTMAP_FILE\033[0m"
	if ! sudo fastboot flash partmap $FASTBOOT_PARTMAP_FILE; then
		exit 1
	fi
	echo ""

	for i in "${partmap_targets[@]}"; do
		target=$(echo "$i" | cut -d':' -f 1)
		image=$(echo "$i" | cut -d':' -f 2)

		echo -e "\033[0;33m $target: $image\033[0m"
		if ! sudo fastboot flash "$target" "$image"; then
			exit 1
		fi
		echo ""
	done
}

SHOW_PARTMAP_LIST=false
SHOW_PARTMAP_INFO=false

case "$1" in
	-f )
		FASTBOOT_PARTMAP_FILE=$(realpath "$2")
		args=$# options=0 counts=0

		parse_partmap

		while [[ "$#" -gt 2 ]]; do
			# argc
			for i in "${FASTBOOT_PARTMAP_LIST[@]}"; do
				if [[ "$i" == "$3" ]]; then
					FASTBOOT_TARGETS+=("$i");
					shift 1
					break
				fi
			done

			case "$3" in
			-d )	RESULTDIR=$(realpath "$4"); ((options+=2)); shift 2;;
			-r ) 	FASTBOOT_REBOOT=true; ((options+=1)); shift 1;;
			-l )	SHOW_PARTMAP_LIST=true;	print_partmap;
				exit 0;;
			-i )	SHOW_PARTMAP_INFO=true;	print_partmap;
				exit 0;;
			-e )
				vim "$FASTBOOT_PARTMAP_FILE"
				exit 0;;
			-h )	usage;
				exit 1;;
			* )
				if [[ $((counts+=1)) -gt $args ]]; then
					break;
				fi
				;;
			esac
		done

		((args-=2))
		num=${#FASTBOOT_TARGETS[@]}
		num=$((args-num-options))

		if [[ $num -ne 0 ]]; then
			echo -e "\033[47;31m Unknown target: $FASTBOOT_PARTMAP_FILE\033[0m"
			echo -en " Check targets: "
			for i in "${FASTBOOT_PARTMAP_LIST[@]}"; do
				echo -n "$i "
			done
			echo ""
			exit 1
		fi

		if [[ ${#FASTBOOT_TARGETS[@]} -eq 0 ]]; then
			FASTBOOT_TARGETS=(${FASTBOOT_PARTMAP_LIST[@]})
		fi

		do_fastboot
		;;
	-r )
		FASTBOOT_REBOOT=true;
		shift 1;;
	-h | * )
		usage;
		exit 1;;
esac

if [[ $FASTBOOT_REBOOT == true ]]; then
	echo -e "\033[47;30m send reboot command...\033[0m"
	sudo fastboot reboot
fi
