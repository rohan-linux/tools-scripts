#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#

BASE_DIR=$(realpath $(dirname $(realpath "$BASH_SOURCE"))/../../../..)
RESULT_DIR=${BASE_DIR}/vendor/nexell/out/result
[[ ! -z $TARGET_RESULT ]] && RESULT_DIR=${BASE_DIR}/vendor/nexell/out/${TARGET_RESULT};
TOOL_DIR=${BASE_DIR}/tools/nxp3220

TOOL_BINGEN="${TOOL_DIR}/bin/bingen"
TOOL_BINECC="${TOOL_DIR}/bin/nandbingen"
TOOL_BOOTPARAM="${TOOL_DIR}/scripts/mk_bootparam.sh"
TOOL_MKUBIFS="${TOOL_DIR}/scripts/mk_ubifs.sh"
TOOLCHAIN_BOOTLOADER="${TOOL_DIR}/crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin/arm-none-eabi-"
TOOLCHAIN_LINUX="${TOOL_DIR}/crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"
#TOOLCHAIN_LINUX="arm-none-eabi-"

# secure keys
SECURE_BOOTKEY="${TOOL_DIR}/files/secure/secure-bootkey.pem"
SECURE_USERKEY="${TOOL_DIR}/files/secure/secure-userkey.pem"
SECURE_BL1_ENCKEY="${TOOL_DIR}/files/secure/secure-bl1-enckey.txt"
SECURE_BL32_ENCKEY="${TOOL_DIR}/files/secure/secure-bl32-enckey.txt"
SECURE_BL1_IVECTOR=73FC7B44B996F9990261A01C9CB93C8F
SECURE_BL32_IVECTOR=73FC7B44B996F9990261A01C9CB93C8F

# b1 configs
# Add to build source at target script:
# TARGET_BL1_DIR=$(realpath $(dirname $(realpath "$BASH_SOURCE"))/../../..)/firmwares/bl1-nxp3220
BL1_DIR=${TARGET_BL1_DIR}
[[ -z $TARGET_BL1_DIR ]] && BL1_DIR=${BASE_DIR}/vendor/nexell/bl1/bl1-nxp3220-binary;
BL1_BIN="bl1-nxp3220.bin"
BL1_LOADADDR=0xFFFF0000
BL1_NSIH="${TOOL_DIR}/files/nsih_bl1.txt"

# b2 configs
BL2_DIR=${BASE_DIR}/vendor/nexell/firmware/bl2-nxp3220
BL2_BIN="bl2-${TARGET_BL2_BOARD}.bin"
BL2_LOADADDR=0xFFFF9000
BL2_NSIH="${BL2_DIR}/reference-nsih/$TARGET_BL2_NSIH"
BL2_CHIP=${TARGET_BL2_CHIP}
BL2_BOARD=${TARGET_BL2_BOARD}
BL2_PMIC=${TARGET_BL2_PMIC}

# b32 configs
BL32_DIR=${BASE_DIR}/vendor/nexell/firmware/bl32-nxp3220
BL32_BIN="bl32.bin"
BL32_LOADADDR=${TARGET_BL32_LOADADDR}
BL32_NSIH="${BL32_DIR}/reference-nsih/nsih_general.txt"

# uboot configs
UBOOT_DIR=${BASE_DIR}/vendor/nexell/u-boot/u-boot-2018.5
UBOOT_BIN="u-boot.bin"
UBOOT_LOADADDR=0x43c00000
UBOOT_NSIH="${TOOL_DIR}/files/nsih_uboot.txt"
UBOOT_DEFCONFIG=${TARGET_UBOOT_DEFCONFIG}
UBOOT_LOGO_BMP="${TOOL_DIR}/files/logo.bmp"

# kernel configs
KERNEL_DIR=${BASE_DIR}/vendor/nexell/kernel/kernel-4.14
KERNEL_DEFCONFIG=${TARGET_KERNEL_DEFCONFIG}
KERNEL_BIN=${TARGET_KERNEL_IMAGE}
KERNEL_DTB_BIN=${TARGET_KERNEL_DTB}.dtb

# buildroot configs
BR2_DIR=${BASE_DIR}/vendor/nexell/buildroot
BR2_DEFCONFIG=${TARGET_BR2_DEFCONFIG}

# images configs
IMAGE_TYPE=${TARGET_IMAGE_TYPE}
IMAGE_BOOT_SIZE=${TARGET_BOOT_IMAGE_SIZE}
IMAGE_ROOT_SIZE=${TARGET_ROOT_IMAGE_SIZE}
IMAGE_DATA_SIZE=${TARGET_DATA_IMAGE_SIZE}
IMAGE_MISC_SIZE=${TARGET_MISC_IMAGE_SIZE}

# copy to result
BSP_TOOL_FILES=(
	"${TOOL_DIR}/scripts/partmap_fastboot.sh"
	"${TOOL_DIR}/scripts/partmap_diskimg.sh"
	"${TOOL_DIR}/scripts/usb-down.sh"
	"${TOOL_DIR}/scripts/configs/udown.bootloader.sh"
	"${TOOL_DIR}/scripts/configs/udown.bootloader-secure.sh"
	"${TOOL_DIR}/bin/linux-usbdownloader"
	"${TOOL_DIR}/bin/simg2dev"
	"${TOOL_DIR}/files/partmap_*.txt"
	"${TOOL_DIR}/scripts/swu_image.sh"
	"${TOOL_DIR}/scripts/swu_hash.py"
	"${TOOL_DIR}/files/secure/secure-bootkey.pem"
	"${TOOL_DIR}/files/secure/secure-userkey.pem"
	"${TOOL_DIR}/files/secure/secure-jtag-hash.txt"
	"${TOOL_DIR}/files/secure/efuse_cfg-aes_enb.txt"
	"${TOOL_DIR}/files/secure/efuse_cfg-verify_enb-hash0.txt"
	"${TOOL_DIR}/files/secure/efuse_cfg-sjtag_enb.txt"
)

function make_image () {
	local label=$1 dir=$2 size=$3
	local out=${dir}.img

	if [[ ${IMAGE_TYPE} == "ext4" ]]; then
		bash -c "make_ext4fs -L $label -s -b 4k -l $size $out $dir";
	elif [[ ${IMAGE_TYPE} == "ubi" ]]; then
		bash -c "${TOOL_MKUBIFS} -r $dir -v $label -i 0 -l $size -p ${FLASH_PAGE_SIZE} -b ${FLASH_BLOCK_SIZE} -c ${FLASH_DEVICE_SIZE}";
	else
		err "Not support image type: ${IMAGE_TYPE}"
		exit 1;
	fi
}

###############################################################################
# build commands
###############################################################################

function post_build_bl1 () {
	local binary=${BL1_DIR}/${BL1_BIN}
	local outdir=${BL1_DIR}

	if [[ ! -z $TARGET_BL1_DIR ]]; then
		binary=${BL1_DIR}/out/${BL1_BIN}
		outdir=${BL1_DIR}/out
	fi

	# Copy encrypt keys
	cp ${SECURE_BL1_ENCKEY} ${outdir}/$(basename $SECURE_BL1_ENCKEY)
	cp ${SECURE_BOOTKEY} ${outdir}/$(basename $SECURE_BOOTKEY)
	cp ${SECURE_USERKEY} ${outdir}/$(basename $SECURE_USERKEY)

	SECURE_BL1_ENCKEY=${outdir}/$(basename $SECURE_BL1_ENCKEY)
	SECURE_BOOTKEY=${outdir}/$(basename $SECURE_BOOTKEY)
	SECURE_USERKEY=${outdir}/$(basename $SECURE_USERKEY)

        # Encrypt binary : $BIN.enc
	msg " ENCRYPT: ${binary} -> ${binary}.enc"
       openssl enc -e -nosalt -aes-128-cbc -in ${binary} -out ${binary}.enc \
		-K $(cat ${SECURE_BL1_ENCKEY}) -iv ${SECURE_BL1_IVECTOR};

        # (Encrypted binary) + NSIH : $BIN.bin.enc.raw
	msg " BINGEN : ${binary}.enc -> ${binary}.enc.raw"
        ${TOOL_BINGEN} -k bl1 -n ${BL1_NSIH} -i ${binary}.enc \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} -l ${BL1_LOADADDR} -s ${BL1_LOADADDR} -t;

        # Binary + NSIH : $BIN.raw
	msg " BINGEN : ${binary} -> ${binary}.raw"
        ${TOOL_BINGEN} -k bl1 -n ${BL1_NSIH} -i ${binary} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} -l ${BL1_LOADADDR} -s ${BL1_LOADADDR} -t;

	cp ${SECURE_BL1_ENCKEY} ${RESULT_DIR}
	cp ${SECURE_BOOTKEY}.pub.hash.txt ${RESULT_DIR}

	cp ${binary}.raw ${RESULT_DIR}
	cp ${binary}.enc.raw ${RESULT_DIR}
}

function post_build_bl2 () {
        # Binary + NSIH : $BIN.raw
	msg " BINGEN : ${BL2_BIN} -> ${BL2_BIN}.raw"
        ${TOOL_BINGEN} -k bl2 -n ${BL2_NSIH} -i ${BL2_DIR}/out/${BL2_BIN} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} -l ${BL2_LOADADDR} -s ${BL2_LOADADDR} -t;

        cp ${BL2_DIR}/out/${BL2_BIN}.raw ${RESULT_DIR}/bl2.bin.raw;
}

function post_build_bl32 () {
	# Copy encrype keys
	cp ${SECURE_BL32_ENCKEY}  ${BL32_DIR}/out/$(basename $SECURE_BL32_ENCKEY)
	cp ${SECURE_BOOTKEY} ${BL32_DIR}/out/$(basename $SECURE_BOOTKEY)
	cp ${SECURE_USERKEY} ${BL32_DIR}/out/$(basename $SECURE_USERKEY)

	SECURE_BL32_ENCKEY=${BL32_DIR}/out/$(basename $SECURE_BL32_ENCKEY)
	SECURE_BOOTKEY=${BL32_DIR}/out/$(basename $SECURE_BOOTKEY)
	SECURE_USERKEY=${BL32_DIR}/out/$(basename $SECURE_USERKEY)

        # Encrypt binary : $BIN.enc
	msg " ENCRYPT: ${BL32_BIN} -> ${BL32_BIN}.enc"
	openssl enc -e -nosalt -aes-128-cbc \
		-in ${BL32_DIR}/out/${BL32_BIN} -out ${BL32_DIR}/out/${BL32_BIN}.enc \
		-K $(cat ${SECURE_BL32_ENCKEY}) -iv ${SECURE_BL32_IVECTOR};

        # (Encrypted binary) + NSIH : $BIN.enc.raw
	msg " BINGEN : ${BL32_BIN}.enc -> ${BL32_BIN}.enc.raw"
        ${TOOL_BINGEN} -k bl32 -n ${BL32_NSIH} -i ${BL32_DIR}/out/${BL32_BIN}.enc \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} \
		-l ${BL32_LOADADDR} -s ${BL32_LOADADDR} -t -e;

        # Binary + NSIH : $BIN.raw
	msg " BINGEN : ${BL32_BIN} -> ${BL32_BIN}.raw"
        ${TOOL_BINGEN} -k bl32 -n ${BL32_NSIH} -i ${BL32_DIR}/out/${BL32_BIN} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} \
		-l ${BL32_LOADADDR} -s ${BL32_LOADADDR} -t;

	cp ${SECURE_BL32_ENCKEY} ${RESULT_DIR}

	cp ${BL32_DIR}/out/${BL32_BIN}.raw ${RESULT_DIR}
	cp ${BL32_DIR}/out/${BL32_BIN}.enc.raw ${RESULT_DIR}
}

function post_build_uboot () {
	msg " BINGEN : ${UBOOT_BIN} -> ${UBOOT_BIN}.raw"
        ${TOOL_BINGEN} -k bl33 -n ${UBOOT_NSIH} -i ${UBOOT_DIR}/${UBOOT_BIN} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} \
		-l ${UBOOT_LOADADDR} -s ${UBOOT_LOADADDR} -t;

	cp ${UBOOT_DIR}/${UBOOT_BIN}.raw ${RESULT_DIR}

	# create param.bin
	${TOOL_BOOTPARAM} ${UBOOT_DIR} ${TOOLCHAIN_LINUX} ${RESULT_DIR}
}

function post_build_modules () {
	mkdir -p ${RESULT}/modules
	find ${KERNEL_DIR} -name *.ko | xargs cp -t ${RESULT}/modules
}

function make_boot_image () {
	BOOT_DIR=$RESULT_DIR/boot

	if ! mkdir -p ${BOOT_DIR}; then exit 1; fi

	cp -a ${RESULT_DIR}/${KERNEL_BIN} ${BOOT_DIR};
	cp -a ${RESULT_DIR}/${KERNEL_DTB_BIN} ${BOOT_DIR};
	[[ -f ${UBOOT_LOGO_BMP} ]] && cp -a ${UBOOT_LOGO_BMP} ${BOOT_DIR};

	make_image "boot" "$BOOT_DIR" "$IMAGE_BOOT_SIZE"
}

function make_root_image () {
	make_image "rootfs" "$RESULT_DIR/rootfs" "$IMAGE_ROOT_SIZE"
}

function make_data_image () {
	[[ -z ${IMAGE_DATA_SIZE} ]] || [[ ${IMAGE_TYPE} == "ubi" ]] && return;
	[[ ! -d $RESULT_DIR/userdata ]] && mkdir -p $RESULT_DIR/userdata;

	make_image "userdata" "$RESULT_DIR/userdata" "$IMAGE_DATA_SIZE"
}

function copy_tools () {
	for file in "${BSP_TOOL_FILES[@]}"; do
		[[ -d $file ]] && continue;
		cp -a $file ${RESULT_DIR}
	done
}

function link_result () {
	local link=result
	local ret=$(basename $RESULT_DIR)

	msg " RETDIR : $RESULT_DIR"
	cd $(dirname $RESULT_DIR)
	[[ -e $link ]] && [[ $(readlink $link) == $ret ]] && return;

	rm -f $link;
	ln -s $ret $link
}

function clean_result () {
	local link=result
	local ret=$(basename $RESULT_DIR)

	msg " CLEAR RETDIR : $RESULT_DIR"
	cd $(dirname $RESULT_DIR)

	rm -f "$link";
	rm -rf "$ret";
}

###############################################################################
# Build Image and Targets
###############################################################################

BUILD_IMAGES=(
	"CROSS_TOOL = ${TOOLCHAIN_LINUX}",
	"RESULT_DIR = ${RESULT_DIR}",
	"bl1   	=
		CROSS_TOOL  	: ${TOOLCHAIN_BOOTLOADER},
		MAKE_PATH	: ${BL1_DIR},
		SCRIPT_LATE 	: post_build_bl1,
		MAKE_JOBS  	: 1", # must be 1
	"bl2   	=
		CROSS_TOOL  	: ${TOOLCHAIN_BOOTLOADER},
		MAKE_PATH  	: ${BL2_DIR},
		MAKE_OPTION	: CHIPNAME=${BL2_CHIP} BOARD=${BL2_BOARD} PMIC=${BL2_PMIC},
		SCRIPT_LATE 	: post_build_bl2,
		MAKE_JOBS  	: 1", # must be 1
	"bl32  =
		CROSS_TOOL  	: ${TOOLCHAIN_BOOTLOADER},
		MAKE_PATH  	: ${BL32_DIR},
		SCRIPT_LATE	: post_build_bl32,
		MAKE_JOBS  	: 1", # must be 1
	"uboot 	=
		MAKE_PATH  	: ${UBOOT_DIR},
		MAKE_CONFIG	: ${UBOOT_DEFCONFIG},
		RESULT_FILE	: u-boot.bin,
		SCRIPT_LATE	: post_build_uboot"
	"br2   	=
		MAKE_PATH  	: ${BR2_DIR},
		MAKE_CONFIG	: ${BR2_DEFCONFIG},
		RESULT_FILE	: output/target,
		RESULT_NAME  	: rootfs",
	"kernel	=
		MAKE_ARCH  	: arm,
		MAKE_PATH  	: ${KERNEL_DIR},
		MAKE_CONFIG	: ${KERNEL_DEFCONFIG},
		MAKE_TARGET 	: ${KERNEL_BIN},
		RESULT_FILE	: arch/arm/boot/${KERNEL_BIN}",
	"dtb   	=
		MAKE_ARCH  	: arm,
		MAKE_PATH  	: ${KERNEL_DIR},
		MAKE_TARGET 	: ${KERNEL_DTB_BIN},
		MAKE_NOT_CLEAN  : true,
		RESULT_FILE	: arch/arm/boot/dts/${KERNEL_DTB_BIN}",

	"bootimg =
		SCRIPT_LATE 	: make_boot_image",

	"rootimg =
		SCRIPT_LATE 	: make_root_image",

	"dataimg =
		SCRIPT_LATE 	: make_data_image",

	"tool  =
		SCRIPT_LATE	: copy_tools",

	"ret    =
		SCRIPT_LATE	: link_result,
		SCRIPT_CLEAN	: clean_result",
)
