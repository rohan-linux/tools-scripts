#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#
# $> build_yocto.sh <machine> <image> [options]
#

# build features
BB_TARGET_MACHINE=$1
BB_TARGET_IMAGE=$2
BB_TARGET_FEATURES=""
BB_TARGET_SDK=false

[[ $BB_TARGET_MACHINE == "-"* ]] && BB_TARGET_MACHINE="";
[[ $BB_TARGET_MACHINE == menuconfig ]] && BB_TARGET_MACHINE="";
[[ $BB_TARGET_IMAGE == "-"* ]] && BB_TARGET_IMAGE="";

# build macros
MACHINE_SUPPORT=( "nxp3220" )

BSP_TOP_DIR="$(realpath "$(dirname "$(realpath "$0")")/../..")"
BSP_VENDOR_DIR="${BSP_TOP_DIR}/vendor/nexell"
BSP_TOOLS_DIR="${BSP_TOP_DIR}/nxp3220_tools"
BSP_YOCTO_DIR="$BSP_TOP_DIR/layers"

YOCTO_DISTRO="$BSP_YOCTO_DIR/poky"
YOCTO_META="$BSP_YOCTO_DIR/meta-nexell/meta-nexell-distro"
YOCTO_MACHINE_CONFIGS="$YOCTO_META/configs/nxp3220/machines"
YOCTO_FEATURE_CONFIGS="$YOCTO_META/configs/nxp3220/images"
YOCTO_IMAGE_ROOTFS="$YOCTO_META/recipes-core/images/nxp3220"
YOCTO_BUILD_DIR="$BSP_TOP_DIR/build"

BSP_RESULT_TOP="$BSP_TOP_DIR/out"
BSP_RESULT_LINK_NAME="result"
BSP_SDK_LINK_NAME="SDK"

# Copy from deploy to result dir
BSP_RESULT_FILES=(
	"bl1-nxp3220.bin.raw"
	"bl1-nxp3220.bin.enc.raw"
	"bl1-nxp3220.bin.raw.ecc"
	"bl1-nxp3220.bin.enc.raw.ecc"
	"bl2.bin.raw"
	"bl2.bin.raw.ecc"
	"bl32.bin.raw"
	"bl32.bin.enc.raw"
	"bl32.bin.raw.ecc"
	"bl32.bin.enc.raw.ecc"
	"u-boot-BUILD_MACHINE_NAME-1.0-r0.bin"
	"u-boot.bin"
	"u-boot.bin.raw"
	"u-boot.bin.raw.ecc"
	"params_env.*"
	"boot/"
	"boot.img"
	"rootfs.img"
	"userdata.img"
	"misc/"
	"misc.img"
	"swu_image.sh"
	"swu_hash.py"
	"*sw-description*"
	"*.sh"
	"swu.private.key"
	"swu.public.key"
	"*.swu"
	"secure-bootkey.pem.pub.hash.txt"
)

# Copy from tools to result dir
BSP_RESULT_TOOLS=(
	"nxp3220_tools/scripts/partmap_fastboot.sh"
	"nxp3220_tools/scripts/partmap_diskimg.sh"
	"nxp3220_tools/scripts/usb-down.sh"
	"nxp3220_tools/scripts/configs/udown.bootloader.sh"
	"nxp3220_tools/scripts/configs/udown.bootloader-secure.sh"
	"nxp3220_tools/bin/linux-usbdownloader"
	"nxp3220_tools/bin/simg2dev"
	"nxp3220_tools/files/partmap_*.txt"
	"nxp3220_tools/files/secure-bl1-enckey.txt"
	"nxp3220_tools/files/secure-bl32-enckey.txt"
	"nxp3220_tools/files/secure-bl32-ivector.txt"
	"nxp3220_tools/files/secure-bootkey.pem"
	"nxp3220_tools/files/secure-userkey.pem"
	"nxp3220_tools/files/secure-jtag-hash.txt"
	"nxp3220_tools/files/secure-bootkey.pem.pub.hash.txt"
	"nxp3220_tools/files/efuse_cfg-aes_enb.txt"
	"nxp3220_tools/files/efuse_cfg-verify_enb-hash0.txt"
	"nxp3220_tools/files/efuse_cfg-sjtag_enb.txt"
)

# Recipe alias
BB_RECIPE_ALIAS=(
	"bl1 = bl1-nxp3220"
	"bl2 = bl2-nxp3220"
	"bl32 = bl32-nxp3220"
	"uboot = virtual/bootloader"
	"kernel = virtual/kernel"
	"bootimg = nexell-bootimg"
	"dataimg = nexell-dataimg"
	"miscimg = nexell-miscimg"
	"recoveryimg = nexell-recoveryimg"
	"swuimg = nexell-swuimg"
)

declare -A BB_COMMAND_ALIAS=(
  	["clean"]="buildclean"
  	["distclean"]="cleansstate"
)

AVAIL_MACHINE="machine"
AVAIL_IMAGE="image"
AVAIL_FEATURE="feature"
AVAIL_MACHINE_TABLE=""
AVAIL_IMAGE_TABLE=""
AVAIL_FEATURE_TABLE=""

BUILD_DEPLOY_DIR=""
BUILD_RESULT_DIR=""
BUILD_RESULT_LINK=""
BUILD_CONFIG=$YOCTO_BUILD_DIR/.config

declare -A BUILD_LOCAL_CONF_CONFIGURE=(
	["BSP_VENDOR_DIR"]="$BSP_VENDOR_DIR"
	["BSP_TOOLS_DIR"]="$BSP_TOOLS_DIR"
	["BSP_TARGET_MACHINE"]=""
)

function err () { echo -e "\033[0;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

function setup_env () {
	# set global configures
	BUILD_MACHINE_NAME="$(echo "$BB_TARGET_MACHINE" | cut -d'-' -f 1)"
	BUILD_TARGET_DIR="$YOCTO_BUILD_DIR/build-${BB_TARGET_MACHINE}"
	BUILD_TARGET_CONFIG="$BUILD_TARGET_DIR/.config"
	BUILD_LOCAL_CONF="$BUILD_TARGET_DIR/conf/local.conf"
	BUILD_LAYER_CONF="$BUILD_TARGET_DIR/conf/bblayers.conf"
	BUILD_IMAGE_DIR="$BSP_RESULT_TOP/result-${BB_TARGET_MACHINE}"
	BUILD_SDK_DIR="$BSP_RESULT_TOP/SDK-result-${BB_TARGET_MACHINE}"

	BUILD_LOCAL_CONF_CONFIGURE["BSP_TARGET_MACHINE"]="$BB_TARGET_MACHINE"
}

function usage () {
	echo ""
	echo "Usage: $(basename "$0") [machine] [image] [option]"
	echo "Usage: $(basename "$0") menuconfig"
	echo "       $(basename "$0") [option]"
	echo ""
	echo " machine"
	echo "      : Located at '$(echo "$YOCTO_MACHINE_CONFIGS" | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo " image"
	echo "      : Located at '$(echo "$YOCTO_IMAGE_ROOTFS" | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo "      : The image name is prefixed with 'nexell-image-', ex> 'nexell-image-<name>'"
	echo ""
	echo " option"
	echo "  -l : Show available lists and build status"
	echo "  -t : Bitbake recipe name or recipe alias to build"
	echo "  -i : Add features to image, Must be nospace each features, Depend on order ex> -i A,B,..."
	echo "  -c : Bitbake build commands"
	echo "  -o : Bitbake build option"
	echo "  -v : Enable bitbake verbose option"
	echo "  -S : Build the SDK image (-c populate_sdk)"
	echo "  -p : Copy images from deploy dir to result dir"
	echo "  -f : Force update buid conf file (local.conf, bblayers.conf)"
	echo "  -j : Determines how many tasks bitbake should run in parallel"
	echo "  -h : Help"
	echo ""
}

function parse_avail_target () {
	local dir=$1 deli=$2
	local table=$3	# parse table
	local val value
	[[ $4 ]] && declare -n avail=$4;

	if ! cd "$dir"; then return; fi

	value=$(find ./ -print \
		2> >(grep -v 'No such file or directory' >&2) | \
		grep -w ".*\.${deli}" | sort)

	for i in $value; do
		i="$(echo "$i" | cut -d'/' -f2)"
		if [[ -n $(echo "$i" | awk -F".${deli}" '{print $2}') ]]; then
			continue
		fi

		if [[ $i == *local.conf* ]] || [[ $i == *bblayers.conf* ]]; then
			continue
		fi

		local match=false
		if [[ ${#avail[@]} -ne 0 ]]; then
			for n in "${avail[@]}"; do
				if [[ $i == *$n* ]]; then
					match=true
					break;
				fi
			done
		else
			match=true
		fi

		[[ $match != true ]] && continue;

		val="${val} $(echo "$i" | awk -F".${deli}" '{print $1}')"
		eval "$table=(\"${val}\")"
	done
}

function check_avail_target () {
	local name=$1 table=$2 feature=$3
	local comp=()

	if [[ -z $name ]] && [[ $feature == "$AVAIL_FEATURE" ]]; then
		return
	fi

	for i in ${table}; do
		for n in ${name}; do
			[[ $i == "$n" ]] && comp+=($i);
		done
	done

	arr=($name)
	[[ ${#comp[@]} -ne 0 ]] && [[ ${#arr[@]} == "${#comp[@]}" ]] && return;

	err ""
	err " Not support $feature: $name"
	err " Availiable: $table"
	err ""

	show_info
	exit 1;
}

function merge_conf_file () {
	local src=$1 cmp=$2 dst=$3

	while IFS='' read i;
        do
                merge=true
                while IFS='' read n;
                do
			[[ -z $i ]] && break;
			[[ $i == *BBMASK* ]] || [[ $i == *_append* ]] && break;
			[[ $i == *+=* ]] && break;
			[[ ${i:0:1} = "#" ]] && break;

			[[ -z $n ]] && continue;
			[[ $n == *BBMASK* ]] || [[ $n == *_append* ]] && continue;
			[[ $n == *+=* ]] && continue;
			[[ ${n:0:1} = "#" ]] && continue;

			ti=${i%=*} ti=${ti%% *}
			tn=${n%=*} tn=${tn%% *}

			# replace
                        if [[ $ti == "$tn" ]]; then
				i=$(echo "$i" | sed -e "s/[[:space:]]\+/ /g")
				n=$(echo "$n" | sed -e "s/[[:space:]]\+/ /g")
				sed -i -e "s|$n|$i|" "$dst"
                                merge=false
                                break;
                        fi
                done < "$src"

		# merge
                if [[ $merge == true ]] && [[ ${i:0:1} != "#" ]]; then
			i=$(echo "$i" | sed -e "s/[[:space:]]\+/ /g")
			echo "$i" >> "$dst";
                fi
	done < "$cmp"
}

function parse_conf_machine () {
	local dst=$BUILD_LOCAL_CONF
        local src="$YOCTO_MACHINE_CONFIGS/local.conf"
	local cmp="$YOCTO_MACHINE_CONFIGS/$BB_TARGET_MACHINE.conf"

	[[ ! -f $src ]] && exit 1;

	msg ""
	msg "local.conf [MACHINE]"
	msg " - copy    = $src"

	cp "$src" "$dst"

	rep="\"$BUILD_MACHINE_NAME\""
	sed -i "s/^MACHINE.*/MACHINE = $rep/" "$dst"

	msg " - merge   = $cmp"
	msg " - to      = $dst\n"

	echo "" >> "$dst"
	echo "# PARSING: $cmp" >> "$dst"
	merge_conf_file "$src" "$cmp" "$dst"

	for i in "${!BUILD_LOCAL_CONF_CONFIGURE[@]}"; do
		key="$i"
		rep="\"${BUILD_LOCAL_CONF_CONFIGURE[$i]//\//\\/}\""
		sed -i "s/^$key =.*/$key = $rep/" "$dst"
	done
	echo "# PARSING DONE" >> "$dst"
}

function parse_conf_image () {
        local dst=$BUILD_LOCAL_CONF
	local srcs=( $YOCTO_FEATURE_CONFIGS/${BB_TARGET_IMAGE##*-}.conf )

	for i in $BB_TARGET_FEATURES; do
		srcs+=( $YOCTO_FEATURE_CONFIGS/$i.conf )
	done

	for i in "${srcs[@]}"; do
		[[ ! -f $i ]] && continue;
		msg "local.conf [IMAGE]"
		msg " - merge   = $i"
		msg " - to      = $dst\n"

		echo "" >> "$dst"
		echo "# PARSING: $i" >> "$dst"
		merge_conf_file "$dst" "$i" "$dst"
		echo "# PARSING DONE" >> "$dst"
        done
}

function parse_conf_sdk () {
        local dst=$BUILD_LOCAL_CONF
        local src=$YOCTO_FEATURE_CONFIGS/sdk.conf

	[[ $BB_TARGET_SDK != true ]] && return;

	msg "local.conf [SDK]"
	msg " - merge   = $src"
	msg " - to      = $dst\n"

	echo "" >> "$dst"
	echo "# PARSING: $src" >> "$dst"
	merge_conf_file "$dst" "$src" "$dst"
	echo "# PARSING DONE" >> "$dst"
}

function parse_conf_opts () {
	local dst=$BUILD_LOCAL_CONF
	local rep="\"$BB_TARGET_IMAGE\""

	sed -i "s/^INITRAMFS_IMAGE.*/INITRAMFS_IMAGE = $rep/" "$dst"

	[[ -z $BB_JOBS ]] && return;
	if grep -q BB_NUMBER_THREADS "$dst"; then
		rep="\"$BB_JOBS\""
		sed -i "s/^BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = $rep/" "$dst"
	else
		echo "" >> "$BUILD_LOCAL_CONF"
		echo "BB_NUMBER_THREADS = \"${BB_JOBS}\"" >> "$dst"
	fi
}

function parse_conf_bblayer () {
	local src="$YOCTO_MACHINE_CONFIGS/bblayers.conf"
        local dst=$BUILD_LAYER_CONF

	msg "bblayers.conf"
	msg " - copy    = $src"
	msg " - to      = $dst\n"
	[[ ! -f $src ]] && exit 1;

        cp -a "$src" "$dst"
	local rep="\"${BSP_YOCTO_DIR//\//\\/}\""
	sed -i "s/^BSPPATH :=.*/BSPPATH := $rep/" "$dst"
}

function menu_target () {
	local table=$1 feature=$2
	local result=$3 # return value
	local select
	local -a entry

	for i in ${table}; do
		stat="OFF"
		entry+=( "$i" )
		entry+=( "$feature  " )
		[[ $i == "${!result}" ]] && stat="ON";
		entry+=( "$stat" )
	done

	if ! which whiptail > /dev/null 2>&1; then
		echo "Please install the whiptail"
		exit 1
	fi

	select=$(whiptail --title "Target $feature" \
		--radiolist "Choose a $feature" 0 50 ${#entry[@]} -- "${entry[@]}" \
		3>&1 1>&2 2>&3)
	[[ -z $select ]] && exit 1;

	eval "$result=(\"${select}\")"
}

function menu_sdk () {
	local result=$1 # return value
	local default=""

	[[ ${!result} == true ]] && default="--defaultno";
	if (whiptail --title "Image type" --yesno --yes-button "rootfs" --no-button "sdk" \
		$default "Build image type" 8 78); then
		eval "$result=(\"false\")"
	else
		eval "$result=(\"true\")"
	fi
}

function menu_feature () {
	local table=$1 feature=$2
	local result=$3 # return value
	local message="*** Depend on order ***\n\n"
	local entry select

	for i in ${table}; do
		[[ $i == "$(echo $BB_TARGET_IMAGE | cut -d'-' -f 3-)" ]] && continue;
		[[ $i == *"sdk"* ]] && continue;
		entry+=" ${i}\n"
	done

	message+=${entry}
	select=$(whiptail --inputbox "$message" 0 78 "${!result}" --nocancel \
			--title "Add $feature" 3>&1 1>&2 2>&3)
	select=$(echo "$select" | tr " " " ")

	eval "$result=(\"${select}\")"
}

function menu_save () {
	if ! (whiptail --title "Save/Exit" --yesno "Save" 8 78); then
		exit 1;
	fi
}

function set_config_value () {
	local file=$1 machine=$2 image=$3 features=$4 sdk=$5

cat > "$file" <<EOF
MACHINE = $machine
IMAGE = $image
FEATURES = $features
SDK = $sdk
EOF
}

function get_config_value () {
	local file=$1 machine=$2 image=$3 features=$4 sdk=$5
	local str

	str=$(sed -n '/^\<MACHINE\>/p' "$file"); ret=$(echo "$str" | cut -d'=' -f 2)
	eval "$machine=(\"${ret# *}\")"
	str=$(sed -n '/^\<IMAGE\>/p' "$file"); ret=$(echo "$str" | cut -d'=' -f 2)
	eval "$image=(\"${ret# *}\")"
	str=$(sed -n '/^\<FEATURES\>/p' "$file"); ret=$(echo "$str" | cut -d'=' -f 2)
	eval "$features=(\"${ret# *}\")"

	if [[ $sdk ]]; then
		str=$(sed -n '/^\<SDK\>/p' "$file"); ret=$(echo "$str" | cut -d'=' -f 2)
		eval "$sdk=(\"${ret# *}\")";
	fi
}

function parse_build_config () {
	[[ -n $BB_TARGET_MACHINE ]] && setup_env;

	if  [[ -z $BB_TARGET_MACHINE ]] && [[ -e $BUILD_CONFIG ]]; then
		get_config_value "$BUILD_CONFIG" BB_TARGET_MACHINE BB_TARGET_IMAGE BB_TARGET_FEATURES
	elif [[ -n $BB_TARGET_MACHINE ]] && [[ -e $BUILD_TARGET_CONFIG ]]; then
		get_config_value "$BUILD_TARGET_CONFIG" BB_TARGET_MACHINE BB_TARGET_IMAGE BB_TARGET_FEATURES
	fi
}

function check_build_config () {
	local newconfig="${BB_TARGET_MACHINE}:${BB_TARGET_IMAGE}:"
	local oldconfig
	local machine
	local match=false

        if [[ ! -f $BUILD_LOCAL_CONF ]]; then
                err " Not build setup: '$BUILD_LOCAL_CONF' ..."
                err " $> source poky/oe-init-build-env <build dir>/<machin type>"
		exit 1;
	fi

	[[ -n $BB_TARGET_FEATURES ]] && newconfig+="$BB_TARGET_FEATURES";
	if [[ $BB_TARGET_SDK == true ]];
	then newconfig+=":true";
	else newconfig+=":false";
	fi

	if [[ -e $BUILD_TARGET_CONFIG ]]; then
		local m i f s
		get_config_value "$BUILD_TARGET_CONFIG" m i f s
		oldconfig="${m}:${i}:${f}:${s}"
	fi

	[[ -e $BUILD_CONFIG ]] && rm -f "$BUILD_CONFIG";
	[[ -e $BUILD_TARGET_CONFIG ]] && rm -f "$BUILD_TARGET_CONFIG";

	set_config_value "$BUILD_CONFIG" "$BB_TARGET_MACHINE" "$BB_TARGET_IMAGE" "$BB_TARGET_FEATURES" "$BB_TARGET_SDK"
	set_config_value "$BUILD_TARGET_CONFIG" "$BB_TARGET_MACHINE" "$BB_TARGET_IMAGE" "$BB_TARGET_FEATURES" "$BB_TARGET_SDK"

	machine=$(echo "$(grep ^MACHINE "$BUILD_LOCAL_CONF")" | cut -d'"' -f 2 | tr -d ' ')
	if [[ ${#MACHINE_SUPPORT[@]} -ne 0 ]]; then
		for n in "${MACHINE_SUPPORT[@]}"; do
			if [[ $machine == "$n" ]]; then
				match=true
				break;
			fi
		done
	fi

	# return 1: require re-configiuration
	if [[ $newconfig == "$oldconfig" ]] && [[ $match == true ]]; then
		echo 0;	return
	else
		echo 1;	return
	fi
}

function show_info () {
	message="$BB_TARGET_MACHINE $BB_TARGET_IMAGE"

	if [[ -n $BB_TARGET_FEATURES ]]; then
		message+=" -i "
		message+=$(echo "${BB_TARGET_FEATURES}" | tr " " ",")
	fi
	[[ $BB_TARGET_SDK == true ]] && message+=" -S";

	msg ""
	msg " [MACHINE]"
	msg "\t- PATH  = $(echo "$YOCTO_MACHINE_CONFIGS" | sed 's|'$BSP_ROOT_DIR'/||')"
	msg "\t- AVAIL =${AVAIL_MACHINE_TABLE}"
	msg " "
	msg " [IMAGE]"
	msg "\t- PATH  = $(echo "$YOCTO_IMAGE_ROOTFS" | sed 's|'$BSP_ROOT_DIR'/||')"
	msg "\t- AVAIL =${AVAIL_IMAGE_TABLE}"
	msg " "
	msg " [FEATURES]"
	msg "\t- PATH  = $(echo "$YOCTO_FEATURE_CONFIGS" | sed 's|'$BSP_ROOT_DIR'/||')"
	msg "\t- AVAIL =${AVAIL_FEATURE_TABLE}"
	msg ""
	msg " [RECIPE]"
	msg "\t- Recipe alias:"
	for i in "${!BB_RECIPE_ALIAS[@]}"; do
		msg "\t  ${BB_RECIPE_ALIAS[$i]}"
	done
	msg ""

	if [[ -n $BB_TARGET_MACHINE ]] && [[ -n $BB_TARGET_IMAGE ]]; then
	BUILD_TARGET_DIR="$YOCTO_BUILD_DIR/build-${BB_TARGET_MACHINE}"
	msg " [CONFIG]"
	msg "\tMACHINE   = $BB_TARGET_MACHINE"
	msg "\tIMAGE     = $BB_TARGET_IMAGE"
	msg "\tFEATURES  = $BB_TARGET_FEATURES"
	msg "\tSDK       = $BB_TARGET_SDK"
	msg ""
	msg " Bitbake Setup :"
	msg "  $> source $YOCTO_DISTRO/oe-init-build-env $BUILD_TARGET_DIR"
	msg ""
	msg " Shell build   :"
	msg "  $> ./nxp3220_tools/scripts/$(basename "$0") $message\n"
	fi
}

function copy_result_image () {
	local deploy retdir

	deploy=$BUILD_TARGET_DIR/tmp/deploy/images/$BUILD_MACHINE_NAME
	if [[ ! -d $deploy ]]; then
		err " No such directory : $deploy"
		exit 1
	fi

	retdir="$(echo "$BB_TARGET_IMAGE" | cut -d'.' -f 1)"
	BUILD_DEPLOY_DIR=$deploy
	BUILD_RESULT_DIR=${BUILD_IMAGE_DIR}-${retdir##*-}
	BUILD_RESULT_LINK=$BSP_RESULT_LINK_NAME

	if ! mkdir -p "$BUILD_RESULT_DIR"; then exit 1; fi
	if ! cd "$deploy"; then exit 1; fi

	for file in "${BSP_RESULT_FILES[@]}"; do
		[[ $file == *BUILD_MACHINE_NAME* ]] && \
			file=$(echo "$file" | sed "s/BUILD_MACHINE_NAME/$BUILD_MACHINE_NAME/")

		local files
		files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			[[ ! -e $n ]] && continue;

			to="$BUILD_RESULT_DIR/$n"
			if [[ -d $n ]]; then
				mkdir -p "$to"
				continue
			fi

			if [[ -f $to ]]; then
				ts="$(stat --printf=%y "$n" | cut -d. -f1)"
				td="$(stat --printf=%y "$to" | cut -d. -f1)"
				[[ $ts == "$td" ]] && continue;
			fi

			cp -a "$n" "$to"
		done
	done
}

function copy_result_sdk () {
	local deploy retdir

	deploy="$BUILD_TARGET_DIR/tmp/deploy/sdk"
	if [[ ! -d $deploy ]]; then
		err " No such directory : $deploy"
		exit 1
	fi

	retdir="$(echo "$BB_TARGET_IMAGE" | cut -d'.' -f 1)"
	BUILD_DEPLOY_DIR=$deploy
	BUILD_RESULT_DIR=${BUILD_SDK_DIR}-${retdir##*-}
	BUILD_RESULT_LINK=$BSP_SDK_LINK_NAME

	if ! mkdir -p "$BUILD_RESULT_DIR"; then exit 1; fi

	cp -a "$deploy/*" "$BUILD_RESULT_DIR/"
}

function copy_result_tools () {
	local retdir

	retdir="$(echo $BB_TARGET_IMAGE | cut -d'.' -f 1)"
	BUILD_RESULT_DIR="${BUILD_IMAGE_DIR}-${retdir##*-}"

	if ! mkdir -p "$BUILD_RESULT_DIR"; then exit 1; fi
	if ! cd "$BSP_ROOT_DIR"; then exit 1; fi

	for file in "${BSP_RESULT_TOOLS[@]}"; do
		local files

		files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			if [[ -d $n ]]; then
				continue
			fi

			to="$BUILD_RESULT_DIR/$(basename "$n")"
			if [[ -f $to ]]; then
				ts="$(stat --printf=%y "$n" | cut -d. -f1)"
				td="$(stat --printf=%y "$to" | cut -d. -f1)"
				[[ ${ts} == "${td}" ]] && continue;
			fi
			cp -a "$n" "$to"
		done
	done
}

function link_result () {
	local link=$BUILD_RESULT_LINK
	local ret

	[[ -z $link ]] && return;

	if ! cd "$BSP_RESULT_TOP"; then exit 1; fi

	ret=$(basename "$BUILD_RESULT_DIR")
	[[ -e $link ]] && [[ $(readlink $link) == "$ret" ]] && return;

	rm -f "$link";
	ln -s "$ret" "$link"
}

CMD_PARSE=false
CMD_COPY=false
BB_OPTION=""
BB_JOBS=
BB_RECIPE=""
BB_CMD=""

function parse_arguments () {
	ARGS=$(getopt -o lSfhpt:i:c:o:j:v -- "$@");
    	eval set -- "$ARGS";

    	while true; do
		case "$1" in
		-l )
			show_info
			exit 0
			;;
		-t )
			for i in "${!BB_RECIPE_ALIAS[@]}"; do
				key=$(echo "${BB_RECIPE_ALIAS[$i]}" | cut -d'=' -f 1 | tr -d ' ')
				[[ $key != "$2" ]] && continue;
				BB_RECIPE=$(echo "${BB_RECIPE_ALIAS[$i]}" | cut -d'=' -f 2 | tr -d ' ')
				shift 2;
				break;
			done
			if [[ -z $BB_RECIPE ]]; then
				BB_RECIPE=$2; shift 2;
			fi
			;;
		-i )
			local arr=(${2//,/ })
			BB_TARGET_FEATURES=$(echo "${arr[*]}" | tr ' ' ' ')
			shift 2
			;;
		-c )
			for i in "${!BB_COMMAND_ALIAS[@]}"; do
				[[ $i != "$2" ]] && continue;
				BB_CMD="-c ${BB_COMMAND_ALIAS[$i]}"; shift 2;
				break;
			done
			if [[ -z $BB_CMD ]]; then
				BB_CMD="-c $2"; shift 2;
			fi
			;;
		-S )	BB_TARGET_SDK=true; shift 1;;
		-v )	BB_OPTION+="-v "; shift 1;;
		-o )	BB_OPTION+="$2 "; shift 2;;
		-j )	BB_JOBS=$2; shift 2;;
		-f )	CMD_PARSE=true;	shift 1;;
		-p )	CMD_COPY=true; shift 1;;
		-h )	usage
			exit 1
			;;
		-- )
			break ;;
		esac
	done
}

function setup_bitbake () {
	setup_env
	mkdir -p "$YOCTO_BUILD_DIR"

	# run oe-init-build-env
	source "$YOCTO_DISTRO/oe-init-build-env" "$BUILD_TARGET_DIR" >/dev/null 2>&1
}

function run_build () {
	msg ""
	msg " MACHINE   = $BB_TARGET_MACHINE"
	msg " IMAGE     = $BB_TARGET_IMAGE"
	msg " FEATURES  = $BB_TARGET_FEATURES"
	msg " SDK       = $BB_TARGET_SDK"
	msg " Recipe    = $BB_RECIPE"
	msg " Command   = $BB_CMD"
	msg " Option    = $BB_OPTION"
	msg " Image dir = $BUILD_TARGET_DIR/tmp/deploy/images/$BUILD_MACHINE_NAME"
	msg " SDK   dir = $BUILD_TARGET_DIR/tmp/deploy/sdk"

	if [[ $CMD_COPY == false ]]; then
		if [[ -n $BB_RECIPE ]]; then
			BB_TARGET=$BB_RECIPE
		else
			BB_TARGET=$BB_TARGET_IMAGE
			[ $BB_TARGET_SDK == true ] && BB_CMD="-c populate_sdk"
		fi

		local cmd;
		cmd="$BB_TARGET $BB_CMD $BB_OPTION"
		cmd="$(echo "$cmd" | sed 's/^[ \t]*//;s/[ \t]*$//')"
		cmd="$(echo "$cmd" | sed 's/\s\s*/ /g')"

		msg ""
		msg " Bitbake Setup :"
		msg " $> source $YOCTO_DISTRO/oe-init-build-env $BUILD_TARGET_DIR\n"
		msg " Bitbake Build :"
		msg " $> bitbake $cmd"
		msg ""

		if ! bitbake $cmd; then exit 1; fi
	fi

	if [[ -z $BB_CMD ]]; then
		if [[ $BB_TARGET_SDK == false ]]; then
			copy_result_image
			copy_result_tools
		else
			copy_result_sdk
		fi

		link_result
		msg ""
		msg " DEPLOY     : $BUILD_DEPLOY_DIR"
		msg " RESULT     : $BUILD_RESULT_DIR"
		msg " Link       : $BSP_RESULT_TOP/$BUILD_RESULT_LINK"
	fi

	msg ""
	msg " Bitbake Setup :"
	msg " $> source $YOCTO_DISTRO/oe-init-build-env $BUILD_TARGET_DIR"
	msg "\n"
}

###############################################################################
# Run build
###############################################################################

parse_avail_target "$YOCTO_MACHINE_CONFIGS" "conf" AVAIL_MACHINE_TABLE MACHINE_SUPPORT
parse_avail_target "$YOCTO_FEATURE_CONFIGS" "conf" AVAIL_FEATURE_TABLE
parse_avail_target "$YOCTO_IMAGE_ROOTFS" "bb" AVAIL_IMAGE_TABLE

if [[ $1 == "menuconfig" ]] || [[ -z $BB_TARGET_MACHINE ]] || [[ -z $BB_TARGET_IMAGE ]]; then
	parse_build_config
fi

parse_arguments "$@"

if [[ $1 == "menuconfig" ]]; then
	menu_target "$AVAIL_MACHINE_TABLE" "$AVAIL_MACHINE" BB_TARGET_MACHINE
	menu_target "$AVAIL_IMAGE_TABLE" "$AVAIL_IMAGE" BB_TARGET_IMAGE
	menu_feature "$AVAIL_FEATURE_TABLE" "$AVAIL_FEATURE" BB_TARGET_FEATURES
	menu_save
fi

check_avail_target "$BB_TARGET_MACHINE" "$AVAIL_MACHINE_TABLE" "$AVAIL_MACHINE"
check_avail_target "$BB_TARGET_IMAGE" "$AVAIL_IMAGE_TABLE" "$AVAIL_IMAGE"
check_avail_target "$BB_TARGET_FEATURES" "$AVAIL_FEATURE_TABLE" "$AVAIL_FEATURE"

setup_bitbake

_ret=$(check_build_config)
if [[ $_ret == 1 ]] || [[ $CMD_PARSE == true ]]; then
	parse_conf_machine
	parse_conf_image
	parse_conf_sdk
	parse_conf_bblayer
fi

parse_conf_opts

if [[ $1 == "menuconfig" ]]; then
	msg "---------------------------------------------------------------------------"
	msg "$(sed -e 's/^/ /' < "$BUILD_CONFIG")"
	msg "---------------------------------------------------------------------------"
	exit 0;
fi

run_build
