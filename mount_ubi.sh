#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#
BASEDIR=$(cd "$(dirname "$0")" && pwd)

UBI_IMAGE=""
FLASH_PAGE_SIZE=2048
FLASH_SUB_PAGE_SIZE=$FLASH_PAGE_SIZE
MOUNT_DIR=$BASEDIR/mnt
UBI_VOLUME_ID=0

function usage() {
	echo "Usage: `basename $0` [options]"
	echo ""
	echo "Require : mtd-utils"
	echo "[options]"
	echo "  -u : UBI detach and unload modules related with ubi"
	echo "  -f : ubi image file to mount"
	echo "  -m : mount directory (default mnt)"
	echo "  -i : ubi volume id to ubi format with '/dev/ubi0_<volume id> (default $UBI_VOLUME_ID : /dev/ubi0_$UBI_VOLUME_ID)"
	echo "  -p : page size (default $FLASH_PAGE_SIZE)"
	echo "  -s : sub page size (default $FLASH_SUB_PAGE_SIZE)"
	echo ""
}

function nandsim_load() {
	# moudles: nand nand_sim nand_ids nand_ecc nand_bch bch bch mtd
	echo -e "\033[0;33m  Load: nandsim moudles\033[0m"
	sudo modprobe nandsim \
		first_id_byte=0x20 \
		second_id_byte=0xaa \
		third_id_byte=0x00 \
		fourth_id_byte=0x15
	[ $? -ne 0 ] && exit 1;

	echo -e "\033[0;33m  Flash: erase\033[0m"
	sudo flash_erase /dev/mtd0 0 0
	[ $? -ne 0 ] && exit 1;
}

function nandsim_unload() {
	echo -e "\033[0;33m  Unload: nandsim nand nand_ecc nand_bch bch nand_ids cmdlinepart mtd\033[0m"
	sudo rmmod nandsim nand nand_ecc nand_bch bch nand_ids cmdlinepart mtd > /dev/null 2>&1
}

function ubi_load() {
	echo -e "\033[0;33m  Load: UBI module\033[0m"
	sudo modprobe ubi mtd=0
}

function ubi_unload() {
	echo -e "\033[0;33m  Unload: UBI \033[0m"
	sudo rmmod ubifs ubi > /dev/null 2>&1
}

function ubi_detach() {
	echo -e "\033[0;33m  UBI detach\033[0m"
	sudo ubidetach /dev/ubi_ctrl -m 0  > /dev/null 2>&1
}

function ubi_attach() {
	local sub_page_size=$1

	echo -e "\033[0;33m  UBI attach: $sub_page_size\033[0m"
	sudo ubiattach /dev/ubi_ctrl -m 0 -O $sub_page_size
}

function ubi_format() {
	local ubi_image=$1 page_size=$2 sub_page_size=$3

	echo -e "\033[0;33m  UBI format : $ubi_image ($page_size:$sub_page_size)\033[0m"
	sudo ubiformat /dev/mtd0 -f $ubi_image -s $sub_page_size
	[ $? -ne 0 ] && exit 1;
}

function ubi_mount() {
	local ubi_image=$1
	local mount_dir=$2
	local volume_id=$3
	local ubi_dev=/dev/ubi0_$volume_id

	if [ ! -e $ubi_dev ]; then
		echo -e "\033[0;31m Not found ubi device : $ubi_dev\033[0m"
		echo -e "\033[0;31m check volume id: $volume_id\033[0m"
	fi

	mkdir -p $mount_dir
	[ $? -ne 0 ] && exit 1;

	sudo mount $ubi_dev $mount_dir
	echo -e "\033[0;33m  Mount: $ubi_image -> $mount_dir \033[0m"
}

function ubi_umount() {
	local mount_dir=`mount | grep ubi | cut -d ' ' -f 3`

	if [[ -z $mount_dir ]]; then
		return
	fi

	echo -e "\033[0;33m  Umount: $mount_dir \033[0m"
	sudo umount $mount_dir > /dev/null 2>&1
}

function mount_ubi_image() {
	local ubi_image=$1
	local mount_dir=$2
	local volume_id=$3
	local page_size=$4
	local sub_page_size=$5

	if [[ ! -f $ubi_image ]]; then
		echo -e "\033[0;31m Not found ubi image : $ubi_image \033[0m"
		exit 1
	fi

	nandsim_load
	ubi_load
	ubi_detach
	ubi_format $ubi_image $page_size $sub_page_size
	ubi_attach $sub_page_size
	ubi_mount $ubi_image $mount_dir $volume_id
}

UBI_UNLOAD=false

while getopts 'huf:m:i:p:s:' opt
do
        case $opt in
        u ) UBI_UNLOAD=true;;
	f ) UBI_IMAGE=$OPTARG;;
	m ) MOUNT_DIR=$OPTARG;;
	i ) UBI_VOLUME_ID=$OPTARG;;
	p ) FLASH_PAGE_SIZE=$OPTARG;;
	s ) FLASH_SUB_PAGE_SIZE=$OPTARG;;
        h | *)
        	usage
		exit 1;;
	esac
done

if [ $UBI_UNLOAD == true ]; then
	ubi_umount
	ubi_detach
	ubi_unload
	nandsim_unload
else
	mount_ubi_image $UBI_IMAGE $MOUNT_DIR $UBI_VOLUME_ID $FLASH_PAGE_SIZE $FLASH_SUB_PAGE_SIZE
fi
