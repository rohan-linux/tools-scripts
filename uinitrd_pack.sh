#!/bin/bash
CURRENT_DIR=$PWD
IMAGE_DIR=$1
IMAGE_OUT=$2

if [ $# -ne 2 ]; then
	echo "Usage: $0 [SRC initrd dir] [DST uInitrd image]"
	echo ""
	echo " - Pack uInitrd(image formats designed for the U-Boot firmware) with fakeroot"
	exit 1;
fi

if [ ! -d $IMAGE_DIR ]; then
	echo "No such directory $IMAGE_DIR"
	exit 1;
fi

IMAGE_DIR=$(realpath "$IMAGE_DIR")
IMAGE_OUT=$(realpath "$IMAGE_OUT")
IMAGE_GZ=$(realpath "$(dirname "$IMAGE_DIR")/initrd.gz")

echo "Compress: $IMAGE_DIR"
echo "     To : $IMAGE_GZ"

# this is pure magic (it allows us to pretend to be root)
# make image with fakeroot to preserve the permission
cd $IMAGE_DIR
find . | fakeroot cpio -H newc -o | gzip -c > $IMAGE_GZ
cd $CURRENT_DIR

# make uinitrd image
echo ""
echo "Packing : $IMAGE_GZ"
echo "     To : $IMAGE_OUT"

# mkimage options
UBOOT_MKIMAGE=mkimage
ARCH=arm
IMAGE_TYPE=ramdisk
SYSTEM=linux
COMPRESS=none #gzip
IMAGE_TYPE=ramdisk

$UBOOT_MKIMAGE -A $ARCH -O $SYSTEM -T $IMAGE_TYPE -C $COMPRESS -a 0 -e 0 -n $IMAGE_TYPE -d $IMAGE_GZ $IMAGE_OUT
