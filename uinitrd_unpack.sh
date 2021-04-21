#!/bin/bash

IMAGE_IN=$1
IMAGE_DIR=$2
[ -z $IMAGE_DIR ] && IMAGE_DIR=initrd;

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
	echo "Usage: $0 [SRC uInitrd image] [DST initrd dir]"
	echo ""
	echo " - Unpack uInitrd(image formats designed for the U-Boot firmware) with fakeroot"
	exit 1;
fi

if [ ! -f $IMAGE_IN ]; then
	echo "No such file `realpath "$IMAGE_IN"`"
	exit 1;
fi

[ -d $IMAGE_DIR ] && rm -rf $IMAGE_DIR;
mkdir -p $IMAGE_DIR

IMAGE_IN=$(realpath "$IMAGE_IN")
IMAGE_DIR=$(realpath "$IMAGE_DIR")
IMAGE_GZ=$(realpath "$(dirname "$IMAGE_DIR")/initrd.gz")

echo "Unpacking : $IMAGE_IN"
echo "       To : $IMAGE_GZ"

[ -f $IMAGE_GZ ] && rm $IMAGE_GZ;
dd if=$IMAGE_IN of=$IMAGE_GZ skip=64 bs=1

echo ""
echo "Uncompress: $IMAGE_GZ"
echo "       To : $IMAGE_DIR"

cd $IMAGE_DIR
zcat $IMAGE_GZ | cpio -id
