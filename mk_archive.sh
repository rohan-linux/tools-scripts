#!/bin/bash

declare -A DECOMPRESS_TYPE=(
        ["gzip"]="decompress_gzip"
        ["lz4"]="decompress_lz4"
        ["cpio"]="unpack_cpio"
) 

declare -A COMPRESS_TYPE=(
        ["gzip"]="compress_gzip"
        ["lz4"]="compress_lz4"
        ["cpio"]="pack_cpio"
) 

__archive_input=""
__archive_output=""
__archive_type=()
__concat_image=() # [input] [input] [output]

function err () { echo -e "\033[0;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

PROGNAME=${0##*/}
function usage() {
	echo " Usage: $PROGNAME [options]"
        echo ""
	echo -e "  -i [input]                input"
	echo -e "  -o [output]               output"
	echo -e "  -t [archive] [compress]   set the sompression type for the input."
	echo -e "  -c [in] [in] [out]        concatenate [in] and [in] to [out] with, need to '-t' "
        echo ""
	echo -e "  <compress>:"
	for i in "${!DECOMPRESS_TYPE[@]}"; do
                 echo -e "\t $i";
	done
        echo -e "  <decompress>:"
	for i in "${!DECOMPRESS_TYPE[@]}"; do
                 echo -e "\t $i";
	done
	echo ""
}

function unpack_cpio () {
	local in=${1} out=${2}

	[[ -d ${out} ]] && rm -rf ${out}
	if ! mkdir -p "${out}"; then
		err "Failed make dir: ${out}"
		exit 1;
	fi

        in=$(realpath ${in})
        msg "Unpack cpio: ${in} -> ${out}"

        # -i            : Extract files from an archive
        # -d            : Create leading directories where needed 
        # -m            : Retain previous file modification times when creating files
        # -v            : Verbosely list the files processed
        # -F FILE-NAME  : Use this FILE-NAME instead of standard input
        # ---------------------------------------------------------------------
        # dump
        # cpio -it < [cpio file]
        # ---------------------------------------------------------------------
	cd ${out} && cpio -idmv -F ${in} & wait
}

function decompress_gzip () {
	local in=${1} out=${2}
	local tmp=${in}

	if [[ $(basename ${in}) != "gz" ]]; then
		mv ${in} ${in}.gz
		in=${in}.gz
	fi 

	msg "Decompress gzip: ${in}"
	gunzip -k ${in} & wait

	extract_image "${tmp}" "${out}"

	rm -rf ${tmp}
	[[ ${tmp} != ${in} ]] && mv ${in} ${tmp}
}

function decompress_lz4 () {
	local in=${1} out=${2}
	local out=${__archive_input}.decomp

	msg "Decompress lz4: ${in}"
	lz4 -d "${in}" "${out}" & wait

	extract_image "${out}" "${out}"
	rm -rf ${out}
}

function extract_image () {
	local in=${1} out=${2}
        local success=false

        if [[ -z ${in} ]] || [[ -z ${out} ]]; then
                err "None input($in} or output(${out} !!!"
        	exit 1
        fi

        if [[ ! -f $(realpath ${in}) ]]; then
		err "Not found compressed image: $(realpath ${in})"
		exit 1
	fi	

	comp=$(file ${in} | cut -d ':' -f 2)
	for t in "${!DECOMPRESS_TYPE[@]}"; do
		if echo "${comp}" | grep -qwi "${t}"; then
			${DECOMPRESS_TYPE[${t}]} "${in}" "${out}"
                        return
		fi
	done

        echo "Not support: ${1} (${comp})"
	for i in "${!DECOMPRESS_TYPE[@]}"; do
                 echo -e "\t $i";
	done
}

function pack_cpio () {
	local in=${1} out=${2} type=( ${@:3} )

        if [[ ! -d $(realpath ${in}) ]]; then
                err "Is not directory to cpio: $(realpath ${in})"
                exit 1;
        fi

        msg "Pack cpio: ${in} -> ${out} [${type[@]}]"
        in=$(realpath ${in})
        out=$(realpath ${out})
        pushd $(pwd) > /dev/null 2>&1
	cd ${in}

        find . | cpio --quiet -o -H newc > ${out}
        popd > /dev/null 2>&1

        archive_image "${out}" "${out}" "${type[@]:1}"
}

function compress_gzip () {
	local in=${1} out=${2} type=( ${@:3} )

	msg "Compress gzip: ${in} [${type[@]}]"

        gzip -f ${in}
        mv ${in}.gz ${out}

        archive_image "${in}" "${out}" "${type[@]:1}"
}

function compress_lz4 () {
	local in=${1} out=${2} type=( ${@:3} )

	msg "Compress lz4: ${in} [${type[@]}]"

        # "-l" compressed with legacy flag (v0.1-v0.9)
        #      must be set this flags to boot kernel)
        # "-9" High Compression
	lz4 -l -9 ${in} ${in}.lz4 & wait
        mv ${in}.lz4 ${out}

        archive_image "${in}" "${out}" "${type[@]:1}"
}

function archive_image () {
        local in=${1} out=${2}
        local type=( ${@:3} )

        if [[ -z ${in} ]] || [[ -z ${out} ]]; then
                err "None input($in} or output(${out} !!!"
        	exit 1;
        fi

        if [[ ! -f $(realpath ${in}) ]] && [[ ! -d $(realpath ${in}) ]]; then
		err "Not found input file or directory: $(realpath ${in})"
                exit 1;
        fi

        [[ -z "${type[@]}" ]] && return;

        for m in "${type[@]}"; do
                for t in "${!COMPRESS_TYPE[@]}"; do
	        	if [[ ${m} == ${t} ]]; then
		        	${COMPRESS_TYPE[${t}]} "${in}" "${out}" "${type[@]}"
        			return
	        	fi
                done
	done

        echo "Not support: ${1} (${comp})"
	for i in "${!COMPRESS_TYPE[@]}"; do
                 echo -e "\t $i";
	done
}

function concat_image () {
        local input=( "${@}" )
        local in1=${input[0]} in2=${input[1]} out=${input[2]}
        local type=( ${@:4} )
        local t1=tmp1 t2=tmp2
        local pass=false

        if [[ -z "${type[@]}" ]]; then
               usage
               exit 1;
        fi

 	comp=$(file ${in1} | cut -d ':' -f 2); pass=false
	for t in "${!DECOMPRESS_TYPE[@]}"; do
		if echo "${comp}" | grep -qwi "${t}"; then
			${DECOMPRESS_TYPE[${t}]} "${in1}" "${t1}"
                        pass=true 
		fi
                [[ ${pass} == true ]] && break;
	done

 	comp=$(file ${in2} | cut -d ':' -f 2); pass=false
        for t in "${!DECOMPRESS_TYPE[@]}"; do
		if echo "${comp}" | grep -qwi "${t}"; then
			${DECOMPRESS_TYPE[${t}]} "${in2}" "${t2}"
                        pass=true 
		fi
                [[ ${pass} == true ]] && break;
	done

        if ! cp -a ${t1}/* ${t2}; then exit 1; fi

        archive_image "${t2}" "${out}" "${type[@]}"

        [[ -d ${t1} ]] && rm -rf ${t1}
        [[ -d ${t2} ]] && rm -rf ${t2}
}

function parse_args () {
	while getopts "i:o:t:c:h" opt; do
	case $opt in
	i )	__archive_input="${OPTARG}";;
	o )	__archive_output="${OPTARG}";;
	t )     __archive_type=("${OPTARG}")
                until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
	                __archive_type+=("$(eval "echo \${$OPTIND}")")
		        OPTIND=$((OPTIND + 1))
                done
                ;;
	c )     __concat_image=("${OPTARG}")
                until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
	                __concat_image+=("$(eval "echo \${$OPTIND}")")
		        OPTIND=$((OPTIND + 1))
                done
                ;;

	h )	usage;
		exit 1;;
        * )	usage;
		exit 1;;
	esac
	done
}

parse_args "${@}"

if [[ -n ${__concat_image[@]} ]]; then
        concat_image "${__concat_image[@]}" "${__archive_type[@]}"
        exit 0;
fi

if [[ -n ${__archive_type[@]} ]]; then
        archive_image "${__archive_input}" "${__archive_output}" "${__archive_type[@]}"
else
        extract_image "${__archive_input}" "${__archive_output}"
fi

