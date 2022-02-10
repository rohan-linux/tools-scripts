#!/bin/bash
#
# build disk image
#

declare -A DISK_OPTIONS=(
        ["disk"]=""
        ["out"]=""
        ["name"]="disk"
        ["size"]=""
        ["devloop"]="loop1"
        ["mount"]="mnt"
        ["format"]="ext4"
        ["mknode"]=false
)
BS_SIZE=1024

function convert_hn_to_byte() {
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

#
# get sudo permission
#
# return "sudo"
#
function sudo_permission () {
	_user_=$(id | sed 's/^uid=//;s/(.*$//')
    if [[ 0 != ${_user_} ]]; then
    	echo " Require root permission"
        _sudo_=${1}
        eval "${_sudo_}='sudo'"	# return sudo
        # test
        sudo losetup -a >> /dev/null
	fi
}
sudo_permission _SUDO_

function path_status () {
	local path=${1}
	if [[ -z ${path} ]] || [[ ! -d ${path} ]]; then
		echo -e " - check path: ${path} ...."
		exit 1;
	fi

	if [[ ! -w "${path}" ]]; then
		echo -e " You do not have write permission"
		echo -e " Check permission: '${path}'"
		exit 1;
	fi
}

#
# make device node files
#
# input parameters
# ${1}	= device path
#
function build_mkdev () {
	local dir=${1}

	echo ""
	echo -n " [ Make Device Node: '${dir}'..."
	###
	# make device nodes in /dev
	###
	devpath=${dir}/dev
	path_status ${dir}

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
	echo -e "\t Done]"
}

function build_disk () {
	local disk="${DISK_OPTIONS["disk"]}"
	local name="${DISK_OPTIONS["name"]}"
	local size="${DISK_OPTIONS["size"]}"
	local devloop="${DISK_OPTIONS["devloop"]}"
	local format="${DISK_OPTIONS["format"]}"
	local mntdir="${DISK_OPTIONS["mount"]}"
	local outdir="${DISK_OPTIONS["out"]}"
	local mknode="${DISK_OPTIONS["mknode"]}"
	local rootsz=$(echo $(du -s ${disk}) | cut -f1 -d" ")

	convert_hn_to_byte ${size} size

	# check path's status and permission
	path_status ${disk}
	path_status ${outdir}

	if [[ -z ${name} ]]; then name=disk; fi
	if [[ -z ${format} ]]; then format=ext2; fi
	if [[ -f ${name}.gz ]]; then rm -f ${name}.gz; fi

	outdir=$(cd ${outdir} && pwd)
	disk=$(cd ${disk} && pwd)
	[[ -z ${size} ]] && size=$(du -sb ${disk} | cut -f 1);

	echo ""
	echo -e " Make disk "
	echo " disk from   = ${disk}"
	echo " copy to     = ${outdir}/${name}"
	echo " image size  = ${size}"
      #	echo " loop node   = $devloop"
      #	echo " fs format   = ${format}"

	if [[ "${rootsz}" -gt "${size}" ]]; then
		echo    ""
		echo -e " FAIL: ${disk}(${rootsz}) is over disk image(${size}) \n"
		exit 1;
	fi

	# umount previos mount
	mount | grep -q ${name}
	if [[ $? -eq 0 ]]; then
		${_SUDO_} umount ${mntdir}
	else
		mkdir -p ${mntdir}
	fi

	path_status ${mntdir}

	# build disk
	dd if=/dev/zero of=${name} bs=${BS_SIZE} count=`expr ${size} / ${BS_SIZE}`;
	yes | mke2fs  ${name} > /dev/null 2> /dev/null;

	# mount disk
	${_SUDO_} mount -o loop ${name} ${mntdir};

	# copy files
	${_SUDO_} cp -a ${disk}/* ${mntdir}/

	# build device nodes
	if [[ ${mknode} == true ]]; then
		build_mkdev ${mntdir}
	fi

	# exit disk
	sleep 1	
	${_SUDO_} umount ${mntdir};
	gzip -f ${name}
	chmod 666 ${name}.gz
	rm -rf ${mntdir}

	# copy image
	if [[ ! -z ${outdir} ]] && [[ -d ${outdir} ]]; then
		cp -f ${name}.gz ${outdir}/${name}
		rm ${name}.gz
	fi
}

function usage () {
	echo "usage: $(basename ${0})"
	echo "Make Disk Tool"
	echo "------------------------------------------------------------------------------"
	echo "root.img"
	echo " - bootcommand : console=ttyX,<baudrate> root=/dev/ram0 rw initrd=<addr>,<size>M disk=<size>"
	echo "------------------------------------------------------------------------------"
	echo "  -r disk path to build disk"
	echo "  -o out directory"
	echo "  -n disk name (${DISK_OPTIONS["name"]})"
	echo "  -s disk size, k,m,g (${DISK_OPTIONS["size"]})"
#	echo "  -l set loop device (default loop1)"
#	echo "  -f disk format (default ext2)"
	echo "  -d build device node (default no)"
	echo "  clean : remove rm *.img"
}

while getopts 'hr:o:n:s:l:f:de:' opt
do
	case ${opt} in
	r) DISK_OPTIONS["disk"]=$OPTARG ;;
	o) DISK_OPTIONS["out"]=$OPTARG ;;
	n) DISK_OPTIONS["name"]=$OPTARG ;;
	s) DISK_OPTIONS["size"]=$OPTARG ;;
	l) DISK_OPTIONS["devloop"]=$OPTARG ;;
	f) DISK_OPTIONS["format"]=$OPTARG ;;
	d) DISK_OPTIONS["mknode"]=true ;;
	h | *)
		usage
		exit 1;;
		esac
done

# no input parameter
# no input parameter
if [[ -z "${1}" ]]; then 
	usage; exit 1; 
fi

# clean
if [ "clean" = "${1}" ]; then
	echo "make clean, rm *.img"
	rm -f *.img
	exit 1;
fi

build_disk

