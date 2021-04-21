#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)/../.."
TARGET=nxp3220

DN_IMAGES=(
	"TARGET: $TARGET"
	"bl1   : -b $RESULTDIR/bl1-nxp3220.bin.raw"
	"bl2   : -b $RESULTDIR/bl2.bin.raw"
#	"sss   : -b $RESULTDIR/sss.raw"
	"bl32  : -b $RESULTDIR/bl32.bin.raw"
	"uboot : -b $RESULTDIR/u-boot.bin.raw"
)

DN_ENC_IMAGES=(
	"TARGET: $TARGET"
	"bl1   : -b $RESULTDIR/bl1-nxp3220.bin.enc.raw"
	"bl2   : -b $RESULTDIR/bl2.bin.raw"
#	"sss   : -b $RESULTDIR/sss.raw"
	"bl32  : -b $RESULTDIR/bl32.bin.raw"
	"uboot : -b $RESULTDIR/u-boot.bin.raw"
)
