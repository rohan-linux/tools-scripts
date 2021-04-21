#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

function usage() {
	echo  -e "\033[0;33m usage:\033[0m"
	echo  -e "\033[0;33m  $> source env_setup_br2sdk.sh <SDK PATH>\033[0m"
	echo  -e ""
	echo  -e "\033[0;33m--------------------------------------------------- \033[0m"
	echo  -e "\033[0;33m Setup Buildroot SDK before env_setup_br2sdk.sh !!!\033[0m"
	echo  -e "\033[0;33m--------------------------------------------------- \033[0m"
	echo  -e "\033[0;33m Build Buildroot SDK:\033[0m"
	echo  -e "\033[0;33m  $> cd <buildroot> \033[0m"
	echo  -e "\033[0;33m  $> make sdk \033[0m"
	echo  -e "\033[0;33m \033[0m"
	echo  -e "\033[0;33m Install Buildroot SDK:\033[0m"
	echo  -e "\033[0;33m  $> tar zxvf <buildroot>/output/images/arm-buildroot-linux-gnueabihf_sdk-buildroot.tar.gz -C <SDK PATH>\033[0m"
	echo  -e "\033[0;33m  $> cd <SDK PATH>/arm-buildroot-linux-gnueabihf_sdk-buildroot\033[0m"
	echo  -e "\033[0;33m  $> ./relocate-sdk.sh \033[0m"
	echo  -e "\033[0;33m--------------------------------------------------- \033[0m"
}

if [ "$#" -ne 1 ]; then
	echo  -e "\033[0;31m Set SDK PATH !!!\033[0m"
	echo  -e ""
	usage;
	exit 0
fi

if [[ $1 == "-h" ]]; then
	usage;
	exit 0
fi

SDK_PATH=`readlink -e -n $1`
if [ ! -e $SDK_PATH ]; then
	echo  -e "\033[0;31m Not such SDK PATH: $SDK_PATH !!!\033[0m"
	exit 0
fi

SDK_CROSS_COMPILE_PREFIX=arm-linux-gnueabihf
SDK_TARGET_OPTION="-march=armv7ve -mfpu=neon -mfloat-abi=hard -mcpu=cortex-a7"

$SDK_PATH/usr/bin/$SDK_CROSS_COMPILE_PREFIX-gcc -v >/dev/null 2>&1
if [ $? -ne 0 ]; then
	echo  -e "\033[0;31m Not such: $SDK_PATH/usr/bin/$SDK_CROSS_COMPILE_PREFIX-gcc !!!\033[0m"
	exit 0
fi

export PATH=$SDK_PATH/usr/bin:$PATH

export TARGET_PREFIX=$SDK_CROSS_COMPILE_PREFIX-
export SDKTARGETSYSROOT=`${TARGET_PREFIX}gcc -print-sysroot`
export CPATH=$SDKTARGETSYSROOT/usr/include:$CPATH
export PKG_CONFIG_SYSROOT_DIR=$SDKTARGETSYSROOT
export PKG_CONFIG_PATH=$SDKTARGETSYSROOT/usr/lib/pkgconfig
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1
export CC="${TARGET_PREFIX}gcc $SDK_TARGET_OPTION --sysroot=$SDKTARGETSYSROOT"
export CXX="${TARGET_PREFIX}g++ $SDK_TARGET_OPTION --sysroot=$SDKTARGETSYSROOT"
export CPP="${TARGET_PREFIX}gcc -E $SDK_TARGET_OPTION --sysroot=$SDKTARGETSYSROOT"
export AS=${TARGET_PREFIX}as
export LD="${TARGET_PREFIX}ld  --sysroot=$SDKTARGETSYSROOT"
export GDB=${TARGET_PREFIX}gdb
export STRIP=${TARGET_PREFIX}strip
export RANLIB=${TARGET_PREFIX}ranlib
export OBJCOPY=${TARGET_PREFIX}objcopy
export OBJDUMP=${TARGET_PREFIX}objdump
export AR=${TARGET_PREFIX}ar
export NM=${TARGET_PREFIX}nm
export M4=m4
export CONFIGURE_FLAGS="--target=$SDK_CROSS_COMPILE_PREFIX --host=$SDK_CROSS_COMPILE_PREFIX --build=x86_64-linux --with-libtool-sysroot=$SDKTARGETSYSROOT"
export CFLAGS=" -O2 -pipe -g -feliminate-unused-debug-types "
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O1 -Wl,--hash-style=gnu -Wl,--as-needed"
export CPPFLAGS=""
export KCFLAGS="--sysroot=$SDKTARGETSYSROOT"
export ARCH=arm
export CROSS_COMPILE=$TARGET_PREFIX
