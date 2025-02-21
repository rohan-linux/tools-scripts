#!/bin/bash
#

function logerr() { echo -e "\033[1;31m$*\033[0m"; }
function logmsg() { echo -e "\033[0;33m$*\033[0m"; }
function logext() {
	echo -e "\033[1;31m$*\033[0m"
	exit 1
}

function usage() {
	echo "usage: $(basename $0) <option>"
	echo ""
	echo "option:"
	echo -e "\t-d\t\tu-boot path"
	echo -e "\t-c\t\tCROSS_COMPILE name (ex. aarch64-none-linux-gnu-)"
	echo -e "\t-o\t\toutput directory"
	echo -e "\t-n\t\tenvironment binary name (default ${_env_bin_name})"
	echo -e "\t-s\t\tenvironment binary size (default ${_env_bin_size})"
	echo ""
}

function make_bootenv() {
	local objdump=${_cross_compile}objdump
	local objcopy=${_cross_compile}objcopy
	local readelf=${_cross_compile}readelf
	local envname=${_env_bin_name}
	local tmpdir="tmp"
	local section_name=".rodata.default_environment"
	local section_env=""

	_uboot_build_dir=$(realpath ${_uboot_build_dir})
	if [[ ! -d "${_uboot_build_dir}" ]]; then
		logext "No such u-boot: '${_uboot_build_dir}' ..."
	fi
	if [[ -z "${_cross_compile}" ]]; then
		logerr "Not set CROSS_COMPILE with '-c' option ..."
		usage
		exit 1
	fi

	logmsg " U-Boot: ${_uboot_build_dir}, ENV size: ${_env_bin_size}"

	pushd $(pwd) >/dev/null 2>&1
	cd ${_uboot_build_dir}

	mkdir -p ${tmpdir}
	cp env/common.o ${tmpdir}/copy_common.o
	[[ $? -ne 0 ]] && exit 1

	set +e
	section_env=$(${objdump} -h ${tmpdir}/copy_common.o | grep $section_name)
	[[ "$section_env" = "" ]] && section_name=".rodata"

	envname=${tmpdir}/${envname}

	${objcopy} -O binary --only-section=${section_name} ${tmpdir}/copy_common.o
	${readelf} -s "env/common.o" | grep "default_environment" |
		awk -v tmp="${tmpdir}" '{print "dd if=\"" tmp "/copy_common.o\" of=\"" tmp "/default_env.bin\" bs=1 skip=$[0x" $2 "] count=" $3 }' | bash
	sed -e '$!s/$/\\/g;s/\x0/\n/g' ${tmpdir}/default_env.bin |
		tee ${envname}.env >/dev/null

	tools/mkenvimage -s ${_env_bin_size} -o ${envname}.bin ${envname}.env

	logmsg " output:"
	[[ -f "${envname}.env" ]] && logmsg " - ${_uboot_build_dir}/${envname}.env"
	[[ -f "${envname}.bin" ]] && logmsg " - ${_uboot_build_dir}/${envname}.bin"

	if [[ ! -d ${_env_output_dir} ]]; then
		logerr "Not set output directory: ${_env_output_dir}"
		usage
		popd >/dev/null 2>&1
		exit 1
	fi

	if [[ -f "${envname}.env" ]]; then
		cp ${envname}.env ${_env_output_dir}
		logmsg " - copy ${envname}.env -> ${_env_output_dir}"
	fi

	if [[ -f ${envname}.bin ]]; then
		cp ${envname}.bin ${_env_output_dir}
		logmsg " - copy ${envname}.bin -> ${_env_output_dir}"
	fi

	popd >/dev/null 2>&1
}

_uboot_build_dir=""
_env_output_dir=""
_cross_compile=""
_env_bin_name="u-boot_env"
_env_bin_size=16384

function parse_args() {
	while getopts "d:c:o:n:s:h" opt; do
		case ${opt} in
		d)	_uboot_build_dir="${OPTARG}" ;;
		c)	_cross_compile="${OPTARG}" ;;
		o)	_env_output_dir="${OPTARG}" ;;
		n)	_env_bin_name="${OPTARG}" ;;
		s)	_env_bin_size="${OPTARG}" ;;
		h)	usage
			exit 0
			;;
		*)	exit 1 ;;
		esac
	done
}

parse_args "${@}"
make_bootenv
