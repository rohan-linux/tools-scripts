#!/bin/bash

declare -A COMPRESS_FORMAT=(
        ["gzip"]="decompress_gzip"
        ["lz4"]="decompress_lz4"
        ["cpio"]="extract_cpio"
) 

function err () { echo -e "\033[0;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

function extract_cpio () {
	local img=${1} dir=${2}

	[[ -d ${dir} ]] && rm -rf ${dir}
	if ! mkdir -p "${dir}"; then
		err "Failed make dir: ${dir}"
		exit 1;
	fi

        img=$(realpath $img)
        msg "Extract cpio: ${img} -> ${dir}"

        # -i            : Extract files from an archive
        # -d            : Create leading directories where needed
        # -m            : Retain previous file modification times when creating files
        # -v            : Verbosely list the files processed
        # -F FILE-NAME  : Use this FILE-NAME instead of standard input
        # ---------------------------------------------------------------------
        # dump
        # cpio -it < [cpio file]
        # ---------------------------------------------------------------------
	cd ${dir} && cpio -idmv -F ${img} & wait
}

function decompress_gzip () {
	local img=${1} dir=${2}
	local out=${img}

	msg "Decompress gzip: ${img}"
	if [[ $(basename ${img}) != "gz" ]]; then
		mv ${img} ${img}.gz
		img=${img}.gz
	fi 

	gunzip -k ${img} & wait

	extract_image "${out}" "${dir}"
	rm -rf ${out}
	[[ ${out} != ${img} ]] && mv ${img} ${out}
}

function decompress_lz4 () {
	local img=${1} dir=${2}
	local out=${__compress_image}.decomp

	msg "Decompress lz4: ${img}"
	lz4 -d "${img}" "${out}" & wait

	extract_image "${out}" "${dir}"
	rm -rf ${out}
}

function extract_image () {
	local img=${1} dir=${2}

	if [[ ! -f ${img} ]]; then
		err "Not found compress image: ${img}"
		exit 1
	fi	

	comp=$(file ${img} | cut -d ':' -f 2)
	for decomp in "${!COMPRESS_FORMAT[@]}"; do
		if echo "${comp}" | grep -qwi "${decomp}"; then
			${COMPRESS_FORMAT[${decomp}]} "${img}" "${dir}"
			return
		fi
	done

	echo -en "Not support compress: "
	for i in "${!COMPRESS_FORMAT[@]}"; do
                 echo -en " '$i'";
	done
	echo ""
        echo "-> $(file ${img})"
}

PROGNAME=${0##*/}
function usage() {
	echo " Usage: $PROGNAME -c <compressed img> -d <decompress dir>"
        echo ""
	echo -e "  - Support:"
	for i in "${!COMPRESS_FORMAT[@]}"; do
                 echo -e "\t $i";
	done
	echo ""
}

__compress_image=""
__decompress_dir=""

function parse_args () {
	while getopts "c:d:h" opt; do
	case $opt in
	c )	__compress_image="${OPTARG}";;
	d )	__decompress_dir="${OPTARG}";;
	h )	usage;
		exit 1;;
        * )	usage;
		exit 1;;
	esac
	done
}

parse_args "$@"
if [[ -z "${__compress_image}" ]] || [[ -z "${__decompress_dir}" ]]; then
	usage
	exit 1
fi
extract_image "${__compress_image}" "${__decompress_dir}"

