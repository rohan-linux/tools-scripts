#!/bin/bash
#
# build root image
#

declare -A RAMFS_OPTIONS=(
        ["rootdir"]=""
        ["output"]=""
        ["compress"]="none"
        ["uinitrd"]=false
        ["arch"]="arm"
)

declare -A COMPRESS_FORMAT=(
        ["gzip"]="compress_gzip"
        ["lz4"]="compress_lz4"
) 

BIN_MKIMAGE="mkimage"

function err () { echo -e "\033[0;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

function compress_gzip () {
        gzip ${1}
        mv ${1}.gz ${1}
}

function compress_lz4 () {
        # "-l" compressed with legacy flag (v0.1-v0.9)
        #      must be set this flags to boot kernel)
        # "-9" High Compression
	lz4 -l -9 ${1} ${1}.lz4 & wait
        mv ${1}.lz4 ${1}
}

function pack_cpio () {
	local root=${RAMFS_OPTIONS["rootdir"]}
	local output=${RAMFS_OPTIONS["output"]}
	local compress=${RAMFS_OPTIONS["compress"]}
	local uinitrd=${RAMFS_OPTIONS["uinitrd"]}
	local arch=${RAMFS_OPTIONS["arch"]}

	if [[ -z "${root}" ]] || [[ -z "${output}" ]]; then 
	    err " Not set root(${root}) or output(${output}) ..."
	    exit 1
	fi

	root=$(cd ${root} && pwd)
        output=$(realpath ${output})
	local rootsz=$(echo $(du -sh ${root}) | cut -f1 -d" ")

	msg " [CPIO]"
	msg " root     = ${root}, size:${rootsz}"
        msg " output   = ${output}"
        msg " compress = $(echo ${compress} | cut -d ':' -f1)"

        pushd $(pwd) > /dev/null 2>&1
	cd ${root}

	if [[ ${uinitrd} == true ]]; then
		if [[ -x ${BIN_MKIMAGE} ]]; then
			err "Can't execute ${BIN_MKIMAGE} for uInitrd image !!!!"
			exit 1
		fi

              # find . | cpio --quiet -o -H newc | gzip -9 > initrd.img
              # ${BIN_MKIMAGE} -A ${arch}  -O linux -T ramdisk -C gzip -a 0 -e 0 -n initramfs -d initrd.img ${output}
                compress=$(echo ${compress} | cut -d ':' -f1)
		find . | cpio --quiet -o -H newc > ${output}
                popd > /dev/null 2>&1
                mv ${output} temp.img
		${BIN_MKIMAGE} -A ${arch}  -O linux -T ramdisk -C ${compress} -a 0 -e 0 -n initramfs -d temp.img ${output}
		rm temp.img
	else
		find . | fakeroot cpio --quiet -o -H newc > ${output}
                popd > /dev/null 2>&1
                if [[ ${compress} != "none" ]]; then
                        compress=$(echo ${compress} | cut -d ':' -f2)
                        ${compress} ${output};
                fi
	fi
}

function usage () {
	echo -e " Usage: $(basename ${0}) [options]"
	echo -e " Make ramfs image (initrd/uInitrd) : cpio format"
	echo -e ""
	echo -e "  -r [root]\t set root directory"
	echo -e "  -o [output]\t output image name"
	echo -e "  -c [compress]\t compress: ${!COMPRESS_FORMAT[@]}"
        echo -e "  -u [arch]\t uInitrd: set architecture for the uInitrd with mkimage (${RAMFS_OPTIONS["arch"]})"
}

while getopts 'hr:o:u:c:' opt
do
	case ${opt} in
	r) RAMFS_OPTIONS["rootdir"]=${OPTARG}
           ;;
	o) RAMFS_OPTIONS["output"]=${OPTARG}
           ;;
	c) 
                for i in "${!COMPRESS_FORMAT[@]}"; do
                        [[ ${OPTARG} == ${i} ]] && RAMFS_OPTIONS["compress"]=${i}:${COMPRESS_FORMAT[${i}]}
                done
                if [[ ${RAMFS_OPTIONS["compress"]} == "none" ]]; then
			err "Not support compress: ${OPTARG} !!!"
                        usage
                        exit 1;
                fi
                ;;
	u) RAMFS_OPTIONS["uinitrd"]=true
	   RAMFS_OPTIONS["arch"]=${OPTARG}
           ;;
	h | *)
		usage
		exit 1;;
		esac
done

pack_cpio
