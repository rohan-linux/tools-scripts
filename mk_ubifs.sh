#!/bin/bash
#
# build file systems

# command-line settable variables

function usage()
{
	echo "usage: `basename $0`"
	echo "  -r input root filesystem for ubi image"
	echo "  -v ubi volume/image name"
	echo "  -l ubi volume size"
	echo "  -i ubi volume id"
	echo "  -p flash page size"
	echo "  -s flash sub page size (default page size)"
	echo "  -b flash block size"
	echo "  -c flash size"
	echo "  -z ubifs compress format (lzo, favor_lzo, zlib, default lzo)"
}

function convert_hn_to_byte() {
	local val=$1
	local ret=$2 # store calculated byte
	local delmi="" mulitple=0

	case "$val" in
	*K* ) delmi='K'; mulitple=1024;;
	*k* ) delmi='k'; mulitple=1024;;
	*M* ) delmi='M'; mulitple=1048576;;
	*m* ) delmi='m'; mulitple=1048576;;
	*G* ) delmi='G'; mulitple=1073741824;;
	*g* ) delmi='g'; mulitple=1073741824;;
	-- ) ;;
	esac

	if [ ! -z $delmi ]; then
		val=$(echo $val| cut -d$delmi -f 1)
		val=`expr $val \* $mulitple`
		eval "$ret=\"${val}\""
	fi
}

function create_ubi_ini_file() {
	local ini_file=$1 image=$2 vname=$3 vid=$4 vsize=$5

	echo \[ubifs\] > $ini_file
	echo mode=ubi >> $ini_file
	echo image=$image >> $ini_file
	echo vol_id=$vid >> $ini_file
	echo vol_size=$vsize >> $ini_file
	echo vol_type=dynamic >> $ini_file
	echo vol_name=$vname >> $ini_file
	echo vol_flags=autoresize >> $ini_file
}

function make_ubi_image()
{
	local root=`realpath $1`
	local vname=$2 vid=$3 vsize=$4 compress=$5
	local page_size=$6 sub_page_size=$7 block_size=$8 flash_size=$9

	if [[ -z $page_size ]] || [[ -z $block_size ]] || [[ -z $flash_size ]]; then
		echo -e "\033[0;31m Check page size:$page_size/block size:$block_size/flash size:$flash_size\033[0m"
        fi

	if [[ ! -d $root ]]; then
		echo -e "\033[0;31m Not found root: $root\033[0m"
		exit 1;
	fi

        if [[ -z $root ]] || [[ -z $vname ]] || [ -z $vsize ]; then
		echo -e "\033[0;31m Check root image:$root/volume name:$vname/volume size:$vsize\033[0m"
        fi

	if [[ $compress != "lzo" ]] && [[ $compress != "favor_lzo" ]] &&
	   [[ $compress != "zlib" ]]; then
		echo -e "\033[0;31m Not support compress: $compress\033[0m"
		exit 1;
	fi

	# check mkfs.ubifs capability
	mkfs.ubifs --h | grep -q "space-fixup"
	if [ $? -eq 1 ]; then
		echo -e "\033[0;31m mkfs.ubifs not support option "-F" for space-fixup\033[0m"
		exit 1;
	fi

	if [ -z $sub_page_size ] || [ $sub_page_size -eq 0 ]; then
                sub_page_size=$page_size
        fi

	convert_hn_to_byte $block_size block_size
	convert_hn_to_byte $flash_size flash_size
	convert_hn_to_byte $vsize vsize

	#
        # Calcurate UBI varialbe
        # Refer to http://processors.wiki.ti.com/index.php/UBIFS_Support
        #
        local LEB=`expr $block_size - \( 2 \* $page_size \)`
        local PEB=$block_size
        local BLC=`expr $flash_size / $block_size`
        local RPB=`expr \( 20 \* $BLC \) / 1024`
        local RPC=`expr $PEB - $LEB`
        local TPB=`expr $vsize / $PEB`
        local OVH=`expr \( \( $RPB + 4 \) \* $PEB \) + \( $RPC \* \( $TPB - $RPB - 4 \) \)`
	local OVB=`expr $OVH / $PEB`
	local avail_size=`expr $vsize - $OVH`
        local max_block_count=`expr $avail_size / $LEB`

	local DIR=$(dirname $root)
        local ubi_fs=`realpath -s $DIR/$vname.ubifs`
        local ubi_image=`realpath -s $DIR/$vname.img`
	local ubi_ini=`realpath -s $DIR/ubi.$vname.ini`

	echo -e "\033[0;33m ROOT dir = $root\033[0m"
	echo -e "\033[0;33m UBI fs = $ubi_fs\033[0m"
	echo -e "\033[0;33m UBI image = $ubi_image\033[0m"
	echo -e "\033[0;33m UBI Ini = $ubi_ini\033[0m"
	echo -e "\033[0;33m UBI Volume name = $vname\033[0m"
	echo -e "\033[0;33m UBI Volume id = $vid\033[0m"
	echo -e "\033[0;33m UBI Volume size = $(($avail_size/1024/1024))MiB ($(($vsize/1024/1024))MiB)\033[0m"
	echo -e "\033[0;33m UBI Compression = $compress\033[0m"
	echo -e "\033[0;33m UBI Logical Erase Block size = $((LEB/1024))KiB\033[0m"
	echo -e "\033[0;33m UBI Maximum Logical Erase Block counts= $max_block_count\033[0m"
	echo -e "\033[0;33m UBI Overhead = $OVB ($TPB)\033[0m"
	echo -e "\033[0;33m UBI Reserved size = $(($OVH/1024/1024))MiB\033[0m"
	echo -e "\033[0;33m Flash Page size = $page_size\033[0m"
	echo -e "\033[0;33m Flash Sub page size = $sub_page_size\033[0m"
	echo -e "\033[0;33m Flash Block size = $((block_size/1024))KiB\033[0m"
	echo -e "\033[0;33m Flash size = $((flash_size/1024/1024))MiB\033[0m"

	create_ubi_ini_file $ubi_ini $ubi_fs $vname $vid $((avail_size/1024/1024))MiB

	mkfs.ubifs -r $root -o $ubi_fs -m $page_size -e $LEB -c $max_block_count -F

	ubinize -o $ubi_image \
		-m $page_size -p $block_size -s $sub_page_size \
		$ubi_ini
}

UBI_IMAGE_ROOT=""
UBI_VOLUME_NAME=""
UBI_VOLUME_ID=0
UBI_COMPRESS="lzo"
FLASH_PAGE_SIZE=0
FLASH_SUB_PAGE_SIZE=0
FLASH_BLOCK_SIZE=0
FLASH_DEVICE_SIZE=0

while getopts 'hp:s:b:c:r:v:l:i:z:' opt
do
        case $opt in
	p ) FLASH_PAGE_SIZE=$OPTARG;;
	s ) FLASH_SUB_PAGE_SIZE=$OPTARG;;
	b ) FLASH_BLOCK_SIZE=$OPTARG;;
	c ) FLASH_DEVICE_SIZE=$OPTARG;;
	r ) UBI_IMAGE_ROOT=$OPTARG;;
	v ) UBI_VOLUME_NAME=$OPTARG;;
	l ) UBI_VOLUME_SIZE=$OPTARG;;
	i ) UBI_VOLUME_ID=$OPTARG;;
	z ) UBI_COMPRESS=$OPTARG;;
	h | *)
		usage
		exit 1;;
	esac
done

make_ubi_image "$UBI_IMAGE_ROOT" \
		"$UBI_VOLUME_NAME" \
		"$UBI_VOLUME_ID" \
		"$UBI_VOLUME_SIZE" \
		"$UBI_COMPRESS" \
		"$FLASH_PAGE_SIZE" \
		"$FLASH_SUB_PAGE_SIZE" \
		"$FLASH_BLOCK_SIZE" \
		"$FLASH_DEVICE_SIZE"
