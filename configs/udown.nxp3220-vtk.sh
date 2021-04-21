#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)/../.."
RESULTDIR="$BASEDIR/result"
TARGET=nxp3220

DN_IMAGES=(
	"TARGET: $TARGET"
	"BOARD : vtk"
	"bl1   : -b $RESULTDIR/bl1-nxp3220.bin.raw"
	"bl2   : -b $RESULTDIR/bl2-vtk.bin.raw"
#	"sss   : -b $RESULTDIR/sss.raw"
	"bl32  : -b $RESULTDIR/bl32.bin.raw"
	"uboot : -b $RESULTDIR/u-boot.bin.raw"
	"kernel: -f $RESULTDIR/zImage"
	"dtb   : -f $RESULTDIR/nxp3220-vtk.dtb"
)

DN_ENC_IMAGES=(
	"TARGET: $TARGET"
	"BOARD : vtk"
	"bl1   : -b $RESULTDIR/bl1-nxp3220.bin.enc.raw"
	"bl2   : -b $RESULTDIR/bl2-vtk.bin.raw"
#	"sss   : -b $RESULTDIR/sss.raw"
	"bl32  : -b $RESULTDIR/bl32.bin.enc.raw"
	"uboot : -b $RESULTDIR/u-boot.bin.raw"
	"kernel: -f $RESULTDIR/zImage"
	"dtb   : -f $RESULTDIR/nxp3220-vtk.dtb"
)
