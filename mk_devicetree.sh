#!/bin/bash
__input=""
__output=""

PROGNAME=${0##*/}
function usage() {
	echo " Usage: $PROGNAME -i <input> -o <output>"	
        echo ""
        echo " -i <input>  : input  extend is .dts or .dtb"
        echo " -o <output> : output extend is .dts or .dtb"
	echo ""
}

function dts_to_dtb ()
{
        local in=${1} out=${2}
        bash -c "dtc -I dts -O dtb -o ${out} ${in}" 
}

function dtb_to_dts ()
{
        local in=${1} out=${2}
        bash -c "dtc -I dtb -O dts -o ${out} ${in}" 
}

function parse_args () {
	while getopts "i:o:h" opt; do
	case $opt in
	i )	__input="${OPTARG}";;
	o )	__output="${OPTARG}";;
	h )	usage;
		exit 1;;
        * )	usage;
		exit 1;;
	esac
	done
}

parse_args "$@"

if [[ -z "${__input}" ]] || [[ -z "${__output}" ]]; then
	usage
	exit 1
fi

if [[ "${__input##*.}" == "dts" ]] && [[ "${__output##*.}" == "dtb" ]]; then
        dts_to_dtb ${__input} ${__output}
        exit 0; 
fi

if [[ "${__input##*.}" == "dtb" ]] && [[ "${__output##*.}" == "dts" ]]; then
        dtb_to_dts ${__input} ${__output}
        exit 0; 
fi

usage
