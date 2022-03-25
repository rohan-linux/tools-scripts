#!/bin/bash
#
# build disk image
#

declare -A DISK_OPTIONS=(
        ["diskdir"]=""
        ["output"]=""
        ["output"]="disk"
        ["size"]=""
        ["loop"]="loop1"
        ["format"]="ext4"
        ["node"]=false
        ["compress"]="none"
)

declare -A COMPRESS_FORMAT=(
        ["gzip"]="compress_gzip"
        ["lz4"]="compress_lz4"
)

BS_SIZE=1024
MOUNT_DIR="mnt"

function err () { echo -e "\033[0;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

function hn_to_byte() {
	local val=${1}
	local ret=${2} # store calculated byte
	local delmi="" mulitple=0

	case "${val}" in
	*K* ) delmi='K'; mulitple=1024;;
	*k* ) delmi='k'; mulitple=1024;;
	*M* ) delmi='M'; mulitple=1048576;;
	*m* ) delmi='m'; mulitple=1048576;;
	*G* ) delmi='G'; mulitple=1073741824;;
	*g* ) delmi='g'; mulitple=1073741824;;
	-- ) ;;
	esac

	if [ ! -z ${delmi} ]; then
		val=$(echo ${val}| cut -d${delmi} -f 1)
		val=`expr ${val} \* $mulitple`
		eval "$ret=\"${val}\""
	fi
}

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

function sudo_perm () {
	_user_=$(id | sed 's/^uid=//;s/(.*$//')
    if [[ 0 != ${_user_} ]]; then
        msg " Require root permission"
        _sudo_=${1}
        eval "${_sudo_}='sudo'"	# return sudo
        # test
        sudo losetup -a >> /dev/null
	fi
}

function path_access () {
	local path=${1}

	if [[ -z ${path} ]] || [[ ! -d ${path} ]]; then
		msg " Not found: ${path} ...."
		exit 1;
	fi

	if [[ ! -w "${path}" ]]; then
		err " You do not have write permission"
		err " Check permission: '${path}'"
		exit 1;
	fi
}

function make_devnode () {
	local dir=${1}

        sudo_perm _SUDO_

	msg "[Make devnode]"
	###
	# make device nodes in /dev
	###
	devpath=${dir}/dev

	# miscellaneous one-of-a-kind stuff
	[[ ! -c "${devpath}/console" ]] && ${_SUDO_} mknod ${devpath}/console	c 5 1;
	[[ ! -c "${devpath}/full"    ]] && ${_SUDO_} mknod ${devpath}/full 	c 1 7;
	[[ ! -c "${devpath}/kmem"    ]] && ${_SUDO_} mknod ${devpath}/kmem 	c 1 2;
	[[ ! -c "${devpath}/mem"     ]] && ${_SUDO_} mknod ${devpath}/mem 	c 1 1;
	[[ ! -c "${devpath}/null"    ]] && ${_SUDO_} mknod ${devpath}/null 	c 1 3;
	[[ ! -c "${devpath}/port"    ]] && ${_SUDO_} mknod ${devpath}/port 	c 1 4;
	[[ ! -c "${devpath}/random"  ]] && ${_SUDO_} mknod ${devpath}/random 	c 1 8;
	[[ ! -c "${devpath}/urandom" ]] && ${_SUDO_} mknod ${devpath}/urandom 	c 1 9;
	[[ ! -c "${devpath}/zero"    ]] && ${_SUDO_} mknod ${devpath}/zero 	c 1 5;
	[[ ! -c "${devpath}/tty"     ]] && ${_SUDO_} mknod ${devpath}/tty 	c 5 0
	[[ ! -h "${devpath}/core"    ]] && ln -s /proc/kcore ${devpath}/core;

	# loop devs
	for i in `seq 0 7`; do
		[[ ! -b "${devpath}/loop${i}" ]] && ${_SUDO_} mknod ${devpath}/loop${i} b 7 ${i};
	done

	# ram devs
	for i in `seq 0 9`; do
		[[ ! -b "${devpath}/ram${i}" ]] && ${_SUDO_} mknod ${devpath}/ram${i} b 1 ${i}
	done

	# ttys
	for i in `seq 0 9`; do
		[[ ! -c "${devpath}/tty${i}" ]] && ${_SUDO_} mknod ${devpath}/tty${i} c 4 ${i}
	done
}

function build_disk () {
	local disk="${DISK_OPTIONS["diskdir"]}"
	local output="${DISK_OPTIONS["output"]}"
	local size="${DISK_OPTIONS["size"]}"
	local loop="${DISK_OPTIONS["loop"]}"
	local format="${DISK_OPTIONS["format"]}"
	local node="${DISK_OPTIONS["node"]}"
	local compress=${DISK_OPTIONS["compress"]}

	if [[ -z "${disk}" ]] || [[ -z "${output}" ]]; then
	    err " Not set disk (${disk}) or output(${output}) ..."
	    exit 1
	fi

	hn_to_byte ${size} size

	# check path's status and permission
	path_access ${disk}

	if [[ -z "${disk}" ]] || [[ -z "${output}" ]]; then
	    err " Not set disk(${disk}) or output(${output}) ..."
	    exit 1
	fi
	local disksz=$(echo $(du -sb ${disk}) | cut -f1 -d" ")
        [[ -z ${size} ]] && size=$((( (${disksz} + 1048576 - 1) / 1048576 ) *1048576));

        msg "[Disk]"
        msg " disk       = ${disk}"
        msg " output     = ${output}"
        msg " disk  size = ${disksz}"
        msg " image size = ${size} : ${DISK_OPTIONS["size"]}"
        msg " loop node  = ${loop}"
        msg " format     = ${format}"
        msg " compress   = $(echo ${compress} | cut -d ':' -f1)"

	if [[ ${disksz} -gt ${size} ]]; then
		err " FAIL: ${disk}(${disksz}) is over disk image(${size})"
		exit 1;
	fi

        sudo_perm _SUDO_

	# umount previos mount
	mount | grep -q ${output}
	if [[ $? -eq 0 ]]; then
		${_SUDO_} umount ${MOUNT_DIR}
	else
		mkdir -p ${MOUNT_DIR}
	fi

	path_access ${MOUNT_DIR}

	# build disk
	dd if=/dev/zero of=${output} bs=${BS_SIZE} count=`expr ${size} / ${BS_SIZE}`;
	yes | mke2fs  ${output} > /dev/null 2> /dev/null;

	# mount disk
	${_SUDO_} mount -o loop ${output} ${MOUNT_DIR};

	# copy files
	${_SUDO_} cp -a ${disk}/* ${MOUNT_DIR}/

	# build device nodes
	if [[ ${node} == true ]]; then
		make_devnode ${MOUNT_DIR}
	fi

	# exit disk
	sleep 1	
	${_SUDO_} umount ${MOUNT_DIR};
	rm -rf ${MOUNT_DIR}
        if [[ ${compress} != "none" ]]; then
                compress=$(echo ${compress} | cut -d ':' -f2)
               ${compress} ${output};
        fi
}

function usage () {
	echo -e " Usage: $(basename ${0}) [options]"
	echo -e " Make disk image"
        echo -e " "
	echo -e "  -r [dir]\t disk path"
	echo -e "  -o [output]\t output image output"
	echo -e "  -s disk size, k,m,g"
#	echo -e "  -l set loop device (default loop1)"
#	echo -e "  -f disk format (default ext2)"
	echo -e "  -c [compress]\t compress: ${!COMPRESS_FORMAT[@]}"
	echo -e "  -d build device node (default no)"
}

while getopts 'hr:o:s:l:f:c:d' opt
do
	case ${opt} in
	r) DISK_OPTIONS["diskdir"]=$OPTARG
           ;;
	o) DISK_OPTIONS["output"]=$OPTARG
           ;;
	s) DISK_OPTIONS["size"]=$OPTARG
           ;;
#	l) DISK_OPTIONS["loop"]=$OPTARG
#          ;;
#	f) DISK_OPTIONS["format"]=$OPTARG
#          ;;
	d) DISK_OPTIONS["node"]=true
           ;;
        c)
                for i in "${!COMPRESS_FORMAT[@]}"; do
                        [[ ${OPTARG} == ${i} ]] && DISK_OPTIONS["compress"]=${i}:${COMPRESS_FORMAT[${i}]}
                done
                if [[ ${DISK_OPTIONS["compress"]} == "none" ]]; then
			err "Not support compress: ${OPTARG} !!!"
                        usage
                        exit 1;
                fi
                ;;

	h | *)
		usage
		exit 1;;
		esac
done

build_disk

