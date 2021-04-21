#!/bin/bash
#
# $1: uboot path
# $2: CROSS_COMPILE name (ex. arm-eabi-)
# $3: result path to copy params_env.bin/.txt
#

function mkboot_param() {
	UBOOT=$1
	CROSSTOOL=$2
	RESULT=$3
	OBJDUMP=${CROSSTOOL}objdump
	OBJCOPY=${CROSSTOOL}objcopy
	READELF=${CROSSTOOL}readelf

	echo "BOOT PARAM: $UBOOT"

	if [ ! -d "$UBOOT" ]; then
		echo -e "\033[47;31m No such : '$UBOOT' ... \033[0m"
		exit 1
	fi

	cd $UBOOT
        cp `find ./env -name "common.o"` copy_env_common.o
	[ $? -ne 0 ] && exit 1;

        SECTION_NAME=".rodata.default_environment"
        set +e
        SECTION_ENV=`${OBJDUMP} -h copy_env_common.o | grep $SECTION_NAME`
        if [ "$SECTION_ENV" = "" ]; then
                SECTION_NAME=".rodata"
        fi

        ${OBJCOPY} -O binary --only-section=${SECTION_NAME} `find . -name "copy_env_common.o"`
        ${READELF} -s `find ./env -name "common.o"` | \
		grep default_environment | \
		awk '{print "dd if=./copy_env_common.o of=./default_env.bin bs=1 skip=$[0x" $2 "] count=" $3 }' | \
		bash
        sed -e '$!s/$/\\/g;s/\x0/\n/g' ./default_env.bin | \
		 tee params_env.txt > /dev/null

	tools/mkenvimage -s 16384 -o params_env.bin params_env.txt

        if [ -f params_env.txt ]; then
		cp params_env.txt ${RESULT}
        fi

        if [ -f params_env.bin ]; then
		cp params_env.bin ${RESULT}
        fi
}

mkboot_param $1 $2 $3
