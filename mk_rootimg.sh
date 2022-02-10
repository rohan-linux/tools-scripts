#!/bin/bash
#
# build ram root image
#
BASE_DIR="$(realpath $(dirname $(realpath "$BASH_SOURCE"))/../..)"
ROOT_IMAGE="initrd.img"

declare -A ROOT_OPTIONS=(
        ["rootdir"]=""
        ["output"]=""
        ["gzip"]=false
        ["uinitrd"]=false
        ["arch"]="arm"
	# ramdisk option
        ["ramdisk"]=false
        ["disk_sz"]=0 # ramdisk option
        ["format"]=ext2 # ramdisk option
)

BIN_MKIMAGE="mkimage"

function sudo_permission()
{
	_user_=$(id | sed 's/^uid=//;s/(.*$//')
    if [ 0 != $_user_ ]; then
    	echo " Require root permission"
        _sudo_=$1
        eval "$_sudo_='sudo'"	# return sudo
        # test
        sudo losetup -a >> /dev/null
	fi
}

function build_ramdisk()
{
	local root=${ROOT_OPTIONS["rootdir"]}
	local output=${ROOT_OPTIONS["output"]}
	local disksz=${ROOT_OPTIONS["disk_sz"]}
	local gzip=${ROOT_OPTIONS["gzip"]}
	local rootsz=$(echo $(du -s ${root}) | cut -f1 -d" ")
	local mnt=$(basename "${ROOT_OPTIONS["rootdir"]}")

	# check path's status and permission
	if [[ -z "${root}" ]] || [[ -z "${output}" ]]; then 
	    echo " Not set root(${root}) or output(${output}) ..."
	    exit 1
	fi

	if [ -f ${output} ]; then rm -f ${output}; fi

	root=$(cd ${root} && pwd)

	echo ""
	echo -e " Make ramdisk "
	echo " root      = ${root}, size:${rootsz}"
	echo " output    = ${output}"
	echo " disk size = ${disksz}"

	if [ "${rootsz}" -gt "${disksz}" ]; then
		echo    ""
		echo -e " FAIL: ${root}(${rootsz}) is over ramdisk image(${disksz}) \n"
		exit 1;
	fi

	sudo_permission _SUDO_

	# umount previos mount
	mount | grep -q ${output}
	if [ $? -eq 0 ]; then
		$_SUDO_ umount ${mnt}
	else
		if ! mkdir -p ${mnt}; then exit 1; fi
	fi

	# build ramdisk
	dd if=/dev/zero of=${output} bs=1k count=${disksz} > /dev/null 2> /dev/null;
	yes | mke2fs  ${output} > /dev/null 2> /dev/null;

	# mount ramdisk
	$_SUDO_ mount -o loop ${output} ${mnt};

	# copy files
	$_SUDO_ cp -a ${root}/* ${mnt}/

	# exit ramdisk
	sleep 1	
	$_SUDO_ umount ${mnt};
	gzip -f ${output}
	chmod 666 ${output}.gz
	rm -rf ${mnt}
}

function build_cpio () {
	local root=${ROOT_OPTIONS["rootdir"]}
	local output=${ROOT_OPTIONS["output"]}
	local gzip=${ROOT_OPTIONS["gzip"]}
	local uinitrd=${ROOT_OPTIONS["uinitrd"]}
	local arch=${ROOT_OPTIONS["arch"]}

	if [[ -z "${root}" ]] || [[ -z "${output}" ]]; then 
	    echo " Not set root(${root}) or output(${output}) ..."
	    exit 1
	fi

	root=$(cd ${root} && pwd)
	dir=$(cd "$(dirname "$0")" && pwd)
	local rootsz=$(echo $(du -sh ${root}) | cut -f1 -d" ")

	echo ""
	echo " root   = ${root}, size:${rootsz}"
	echo " output = ${output}"

	cd ${root}

	if [[ ${uinitrd} == true ]]; then
		if [[ -x ${BIN_MKIMAGE} ]]; then
			echo "Can't execute ${BIN_MKIMAGE} for uInitrd image !!!!"
			exit 1
		fi

		find . | cpio --quiet -o -H newc | gzip -9 > initrd.img
		${BIN_MKIMAGE} -A ${arch}  -O linux -T ramdisk -C gzip -a 0 -e 0 -n initramfs -d initrd.img ${output}
		rm initrd.img
	else
		if [[ ${gzip} == true ]]; then
		find . | fakeroot cpio --quiet -o -H newc | gzip -9 > ${output}
		else
		find . | fakeroot cpio --quiet -o -H newc > ${output}
		fi
		echo ""
	      # echo " Add bootcommand 'root=/dev/ram0 rw initrd=<ADDR>,<SIZE> rdinit=/sbin/init.sh'"
	      #	echo "  EX> 'root=/dev/ram0 rw initrd=0x4a000000,16M rdinit=/sbin/init.sh'"
	fi
}

function usage () {
	echo -e " Usage: $(basename ${0}) [options]"
	echo -e " Make ramdisk image or rmafs cpio(initrd/uInitrd) image"
	echo -e ""
	echo -e "  -d [disk size]\t build ramdisk image with disk size, default is ramfs cpio image"
	echo -e "  -r [root]\t set root directory"
	echo -e "  -o [output]\t output image name"
	echo -e "  -z\t\t gzip image (default ${ROOT_OPTIONS["gzip"]})"
	echo -e "  -u [arch]\t set architecture for the uInitrd with mkimage (${OT_OPTIONS["arch"]}"
}

while getopts 'hr:o:zude:' opt
do
	case ${opt} in
	r) ROOT_OPTIONS["rootdir"]=$OPTARG ;;
	o) ROOT_OPTIONS["output"]=$OPTARG ;;
	z) ROOT_OPTIONS["gzip"]=true ;;
	u) ROOT_OPTIONS["uinitrd"]=true
	   ROOT_OPTIONS["arch"]=$OPTARG;;
        u) ROOT_OPTIONS["ramdisk"]=true
	   ROOT_OPTIONS["disk_sz"]=$OPTARG;;
	h | *)
		usage
		exit 1;;
		esac
done

if [[ ${ROOT_OPTIONS["ramdisk"]} == true ]]; then
	build_ramdisk
else	
	build_cpio
fi

