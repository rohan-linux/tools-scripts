#!/bin/bash
# Copyright (c) 2019 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#

function usage() {
	echo "usage: `basename $0` [options] "
	echo ""
	echo "  -l : library directory"
	echo "  -d : set install directory to make install (DESTDIR=)"
	echo "  -p : set prefix for configure (--prefix=)"
	echo "  -t : set cross tool path (ex: <PATH>/arm-linux-gnueabihf)"
	echo ""
}

function setup_crosstool() {
	local crosstool=$1

	[[ -z $crosstool ]] && return;

	if [[ -z $(readlink -e -n "$(dirname "$tool")") ]]; then
		echo -e "\033[47;31m No such 'TOOL': $(dirname "$crosstool") \033[0m"
		exit 1
	fi

	export PATH=`readlink -e -n $(dirname $crosstool)`:$PATH
}

function make_library() {
	local library=`realpath $1`
	local destdir=`realpath $2`
	local prefix=$3
	local crosstool=$4
	local option=""

	if [[ ! -d $library ]]; then
		echo  -e "\033[0;33m No such: $library\033[0m"
               	exit 1;
        fi

	setup_crosstool $crosstool

	echo -e "\033[0;33m================================================================== \033[0m"
	echo -e "\033[0;33mLIBRARY: `realpath $library`\033[0m"
	echo -e "\033[0;33m================================================================== \033[0m"

	cd $library

	[[ ! -z $prefix ]] && option="--prefix=$prefix";
	if [[ ! -z $crosstool ]]; then
		option="$option --host=$(basename "$crosstool")"
	fi

	./autogen.sh $option; [ $? -ne 0 ] && exit 1;
	# ./configure $option

	make;
	[ $? -ne 0 ] && exit 1;

        if [[ ! -z $destdir ]] && [[ ! -d $destdir ]]; then
		echo  -e "\033[0;33m No such install dir: $destdir\033[0m"
		exit 1;
        fi

	if [[ ! -z $destdir ]]; then
		make install DESTDIR=$destdir
	else
		make install
	fi
}

LIBRARY=""
PREFIX=""
DESTDIR=""
TOOLCHAIN=""

while getopts 'hl:d:p:t:' opt
do
        case $opt in
        l ) LIBRARY=$OPTARG;;
	d ) DESTDIR=$OPTARG;;
        p ) PREFIX=$OPTARG;;
	t ) TOOLCHAIN=$OPTARG;;
        h | *)
        	usage
		exit 1;;
		esac
done

make_library "$LIBRARY" "$DESTDIR" "$PREFIX" "$TOOLCHAIN"
