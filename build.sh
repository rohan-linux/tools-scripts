#!/bin/bash
#
# CMAKE:
#    declare -A BS_TARGET_ELEMENT=(
# 	    ['type']="cmake or make or linux"       # required : build type [cmake, make, linux]
# 	    ['name']="<name>"                       # required : build target name
# 	    ['source']="<source directory>"         # required : build source directory
# 	    ['config']="<configuration >"           # required : if type is cmake (cmake config) or linux (defconfig)
# 	    ['option']="<build option>"             # required : build options
# 	    ['image']="<build image>"               # optional : build target image names, support multiple image with shell array
# 	    ['build']="<build directory>"           # optional : build output directory
# 	    ['output']="<output image>"             # optional : build output image name to install,
# 	                                                         must be full path, support multiple image with shell array
# 	    ['result']="<result directory>"         # optional : build image's install directory
# 	    ['install']="<install image>"           # optional : copy name to 'result' dir
# 	    ['prebuild']="<shell function>"         # optional : pre build shell script function (before config)
# 	    ['postbuild']="<shell function>"        # optional : post build shell script function (after install)
#    )
#

eval "$(locale | sed -e 's/\(.*\)=.*/export \1=en_US.UTF-8/')"

BSP_DIR="$(realpath $(dirname $(realpath "$BASH_SOURCE"))/../..)"
export BSP_DIR=${BSP_DIR}

function logerr () { echo -e "\033[1;31m$*\033[0m"; }
function logmsg () { echo -e "\033[0;33m$*\033[0m"; }
function logext () { echo -e "\033[1;31m$*\033[0m"; exit -1; }

###############################################################################
# Set Build Script
###############################################################################

BS_SCRIPT_DIR="${BSP_DIR}/tools/project"
BS_SCRIPT_CFG="${BSP_DIR}/.bs_config"
BS_SCRIPT_EXTEN='*.bs'
BS_SCRIPT=""
BS_EDITOR='vim'	# editor with '-e' option

###############################################################################
# Build Script Build Functions
BS_OP_SEQ_CMAKE=( 'prebuild' 'config' 'build' 'install' 'postbuild' )
declare -A BS_OP_CMAKE=(
	['type']="cmake"
	['config']=bs_cmake_config
	['build']=bs_cmake_build
	['command']=bs_cmake_command
	['clean']=bs_cmake_clean
	['delete']=bs_generic_delete
	['install']=bs_generic_install
	['prebuild']=bs_generic_func
	['postbuild']=bs_generic_func
	['sequence']=${BS_OP_SEQ_CMAKE[*]}
)

BS_OP_SEQ_MAKE=( 'prebuild' 'build' 'install' 'postbuild' )
declare -A BS_OP_MAKE=(
	['type']="make"
	['build']=bs_make_build
	['command']=bs_make_command
	['clean']=bs_make_clean
	['delete']=bs_generic_delete
	['install']=bs_generic_install
	['prebuild']=bs_generic_func
	['postbuild']=bs_generic_func
	['sequence']=${BS_OP_SEQ_MAKE[*]}
)

BS_OP_SEQ_LINUX=( 'prebuild' 'defconfig' 'build' 'install' 'postbuild' )
declare -A BS_OP_LINUX=(
	['type']="linux"
	['defconfig']=bs_linux_defconfig
	['menuconfig']=bs_linux_menuconfig
	['build']=bs_linux_build
	['command']=bs_linux_command
	['clean']=bs_linux_clean
	['delete']=bs_generic_delete
	['install']=bs_generic_install
	['prebuild']=bs_generic_func
	['postbuild']=bs_generic_func
	['sequence']=${BS_OP_SEQ_LINUX[*]}
)

BS_OP_LISTS=( BS_OP_CMAKE BS_OP_MAKE BS_OP_LINUX )

_BUILD_TARGET=""
_BUILD_IMAGE=""
_BUILD_VERBOSE=false
_BUILD_OPTION=""
_BUILD_COMMAND=""
_BUILD_JOBS="-j$(grep -c processor /proc/cpuinfo)"

function bs_prog_start () {
	local spin='-\|/' pos=0
	local delay=0.3 start=${SECONDS}
	while true; do
		local hrs=$(( (SECONDS-start)/3600 ));
		local min=$(( (SECONDS-start-hrs*3600)/60 ));
		local sec=$(( (SECONDS-start)-hrs*3600-min*60 ))
		pos=$(( (pos + 1) % 4 ))
		printf "\r\t: Progress |${spin:$pos:1}| %d:%02d:%02d" ${hrs} ${min} ${sec}
		sleep ${delay}
	done
}

function bs_prog_kill () {
	local pid=${BS_PROG_ID}
	if pidof ${pid}; then return; fi
	if [[ ${pid} -ne 0 ]] && [[ -e /proc/${pid} ]]; then
		kill "${pid}" 2> /dev/null
		wait "${pid}" 2> /dev/null
		echo ""
	fi
}

function bs_prog_run () {
	bs_prog_kill
	bs_prog_start &
	echo -en " ${!}"
	BS_PROG_ID=${!}
}

trap bs_prog_kill EXIT

function bs_exec () {
	local exec=${1} err

	# remove first,last space and set multiple space to single space
	exec="$(echo "${exec}" | sed 's/^[ \t]*//;s/[ \t]*$//')"
	exec="$(echo "${exec}" | sed 's/\s\s*/ /g')"

	logmsg " $ ${exec}"

	if [[ ${_BUILD_VERBOSE} == true ]]; then
		bash -c "${exec}"
		err=${?}
	else
		bs_prog_run
		bash -c "${exec}" > /dev/null 2>&1
		err=${?}
		bs_prog_kill
	fi

	return ${err}
}

function bs_generic_install () {
	declare -n args="${1}"
	local out=( ${args['output']} ) dst=( ${args['install']} )
	local dir=${args['result']}

	[[ -z ${out} ]] && return;
	if ! mkdir -p "${dir}"; then exit 1; fi

	for (( i = 0 ; i < ${#out[*]} ; i++ )) ; do
		local obj=$(realpath "${dir}/${dst[$i]}")
		logmsg "   ${out[$i]} > ${obj}"
	done

	[[ ${_BUILD_VERBOSE} == false ]] && bs_prog_run;

	for (( i = 0 ; i < ${#out[*]} ; i++ )) ; do
		# delete target directory
		if [[ -z ${dst[$i]} ]] && [[ -d ${out[$i]} ]] &&
		   [[ -d "${dir}/$(basename "${out[$i]}")" ]]; then
			bash -c "rm -rf ${dir}/$(basename "${out[$i]}")"
		fi
		local obj=$(realpath "${dir}/${dst[$i]}")
		local exec="cp -a ${out[$i]} ${obj}"
		if [[ ${_BUILD_VERBOSE} == true ]]; then
			bash -c "${exec}"
			err=${?}
		else
			bash -c "${exec}" > /dev/null 2>&1
			err=${?}
		fi
	done

	[[ ${_BUILD_VERBOSE} == false ]] && bs_prog_kill;

	return ${err}
}

function bs_generic_delete () {
	declare -n args="${1}"
	local srcdir=${args['source']} outdir=${args['build']}
	local exec="rm -rf ${outdir}"

	[[ -z ${outdir} ]] && return 0;
	[[ $(realpath ${srcdir}) == $(realpath ${outdir}) ]] && return 0;

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_generic_func () {
	declare -n args="${1}"
	local type="${2}"
	local fn=${args[${type}]}

	[[ -z ${fn} ]] && return 0;

	if [[ $(type -t "${fn}") == "function" ]]; then
		${fn} ${1} "${type}"
	else
		bs_exec "${fn}"
	fi

	return ${?}
}

function bs_cmake_config () {
	declare -n args="${1}"
	local exec=( "cmake"
				 "-S ${args['source']}"
				 "-B ${args['build']}"
				 "${args['config']}"
				 "${_BUILD_OPTION}" )

	[[ -z ${args['build']} ]] && return 1;

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_cmake_build () {
	declare -n args="${1}"
	local outdir=${args['build']}
	local image=( ${args['image']} )
	local exec=( "cmake" "--build ${outdir}" "${_BUILD_OPTION}" )

	[[ -z ${outdir} ]] && return 1;

	if [[ ${_BUILD_IMAGE} ]]; then
		exec+=( "-t ${_BUILD_IMAGE}" );
	elif [[ ${image} ]]; then
		exec+=( "-t ${image[*]}" );
	fi

	bs_exec "${exec[*]} ${_BUILD_JOBS}"

	return ${?}
}

function bs_cmake_command () {
	declare -n args="${1}"
	local command="${2}"
	local outdir=${args['build']}
	local exec=( "cmake" "--build ${outdir}" "${_BUILD_OPTION}" )

	[[ -z ${command} || -z ${outdir} ]] && return 1;

	exec+=( "-t ${command}" );
	bs_exec "${exec[*]} ${_BUILD_JOBS}"

	return ${?}
}

function bs_cmake_clean () {
	declare -n args="${1}"
	local exec=( "cmake"
				 "--build ${args['build']}"
				 "--target clean" )

	[[ -z ${args['build']} ]] && return 1;

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_make_build () {
	declare -n args="${1}"
	local srcdir=${args['source']} option=${args['option']}
	local image=( ${args['image']} )
	local exec=( "make"
				 "-C ${srcdir}"
				 "${option}"
				 "${_BUILD_OPTION}" )

	if [[ -n ${_BUILD_IMAGE} ]]; then
		bs_exec "${exec[*]} ${_BUILD_IMAGE} ${_BUILD_JOBS}"
		return ${?}
	fi

	if [[ ${image} ]]; then
		for i in ${image[*]}; do
			bs_exec "${exec[*]} ${i} ${_BUILD_JOBS}"
			[[ ${?} -ne 0 ]] && return 2;
		done
		return 0
	fi
	
	bs_exec "${exec[*]} ${_BUILD_JOBS}"

	return ${?}
}

function bs_make_command () {
	declare -n args="${1}"
	local command="${2}"
	local srcdir=${args['source']} option=${args['option']}
	local exec=( "make"
				 "-C ${srcdir}"
				 "${option}"
				 "${_BUILD_OPTION}" )

	[[ -z ${command} ]] && return 1;

	if [[ -n ${_BUILD_IMAGE} ]]; then
		bs_exec "${exec[*]} ${_BUILD_IMAGE} ${command} ${_BUILD_JOBS}"
		return ${?}
	fi

	bs_exec "${exec[*]} ${_BUILD_JOBS}"

	return ${?}
}

function bs_make_clean () {
	declare -n args="${1}"
	local exec=( "make"
				 "-C ${args['source']}"
				 "${args['option']}"
				 "clean" )

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_linux_defconfig () {
	declare -n args="${1}"
	local srcdir=${args['source']} outdir=${args['build']}
	local path="${srcdir}"
	local exec=( "make" "-C ${srcdir}" )

	if [[ -n ${outdir} ]]; then
		path=${outdir}
		exec+=( "O=${path}" );
	fi

	if [[ -f "${path}/.config" ]]; then
		logmsg " - skip defconfig, exist '${path}/.config' ..."
		return 0;
	fi

	exec+=( "${args['option']}"
			"${_BUILD_OPTION}"
			"${args['config']}" )

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_linux_menuconfig () {
	declare -n args="${1}"
	local srcdir=${args['source']} outdir=${args['build']}
	local path="${srcdir}"
	local exec=( "make" "-C ${srcdir}" )

	if [[ -n ${outdir} ]]; then
		path=${outdir}
		exec+=( "O=${path}" );
	fi

	# check default config
	if [[ ! -d "$(realpath ${path})" || ! -f "$(realpath ${path})/.config" ]]; then
		if ! bs_linux_defconfig ${1}; then
			return 1;
		fi
	fi

	exec+=( "${args['option']}" "menuconfig" )

	_BUILD_VERBOSE=true
	bs_exec "${exec[*]}"

	return ${?}
}

function bs_linux_build () {
	declare -n args="${1}"
	local srcdir=${args['source']} outdir=${args['build']}
	local path="${srcdir}"
	local exec=( "make" "-C ${srcdir}" )

	if [[ -n ${outdir} ]]; then
		path=${outdir}
		exec+=( "O=${path}" );
	fi

	# check default config
	if [[ ! -d "$(realpath ${path})" || ! -f "$(realpath ${path})/.config" ]]; then
		if ! bs_linux_defconfig ${1}; then
			return 1;
		fi
	fi

	exec+=( "${args['option']}" "${_BUILD_OPTION}" )

	if [[ -n ${_BUILD_IMAGE} ]]; then
		bs_exec "${exec[*]} ${_BUILD_IMAGE} ${_BUILD_JOBS}"
		return ${?}
	fi

	if [[ -n ${args['image']} ]]; then
		for i in ${args['image']}; do
			bs_exec "${exec[*]} ${i} ${_BUILD_JOBS}"
			[[ ${?} -ne 0 ]] && return 2;
		done
	else
		# buildroot has no image names
		bs_exec "${exec[*]} ${_BUILD_JOBS}"
	fi

	return 0
}

function bs_linux_command () {
	declare -n args="${1}"
	local command="${2}"
	local srcdir=${args['source']} outdir=${args['build']}
	local path="${srcdir}"
	local exec=( "make" "-C ${srcdir}" )

	[[ -z ${command} ]] && return 1;

	if [[ -n ${outdir} ]]; then
		path=${outdir}
		exec+=( "O=${path}" );
	fi

	[[ ${command} == *"menuconfig"* ]] && _BUILD_VERBOSE=true;

	exec+=( "${args['option']}"
			"${_BUILD_OPTION}"
			"${command}"
			"${_BUILD_JOBS}" )

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_linux_clean () {
	declare -n args="${1}"
	local exec=( "make" "-C ${args['source']}" )

	[[ -n ${args['build']} ]] && exec+=( "O=${args['build']}" );

	exec+=( "${args['option']}" "clean" )

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_op_assign () {
	declare -n t="${1}"

	[[ -n ${t['op']} ]] && return;

	for l in "${BS_OP_LISTS[@]}"; do
		declare -n list=${l}
		if [[ ${t['type']} == ${list['type']} ]]; then
			t['op']=${l};
			break
		fi
	done
}

function bs_script_get () {
	if [[ ! -f ${BS_SCRIPT_CFG} ]]; then
		logerr " Not found ${BS_SCRIPT_CFG}"
		return -1;
	fi

	local val=$(sed -n '/^\<CONFIG\>/p' "${BS_SCRIPT_CFG}");
	val=$(echo "${val}" | cut -d'=' -f 2)

	BS_SCRIPT=$(echo "${val}" | sed 's/[[:space:]]//g')
	if [[ ! -f ${BS_SCRIPT} ]]; then
		logerr "Not found script : ${BS_SCRIPT}"
		return -1;
	fi

	logmsg " Config\t: ${BS_SCRIPT_CFG}"
	logmsg " Script\t: ${BS_SCRIPT}\n"

	return 0;
}

function bs_script_set () {
	local script=${1}

	if [[ -z ${script}  || ! -f ${script} ]]; then
		logerr " Invalid script : ${script}"
		return;
	fi

	script=$(realpath ${script})
	logmsg " SAVE\t : '${script}' [${BS_SCRIPT_CFG}]"

	# save script config
cat > "${BS_SCRIPT_CFG}" <<EOF
CONFIG = ${script}
EOF
}

function bs_menuconfig () {
	local path=${BS_SCRIPT_DIR}
	local -a prog_lits entry
	local project

	# get script lists
	IFS=$'\n'
	local array=($(find ${path} -type f -name "*${BS_SCRIPT_EXTEN}"))
	unset IFS
	for i in ${array[*]}; do
		prog_lits+=( ${i} )
	done

	# get porject menu lists
	for i in ${prog_lits[*]}; do
		stat="OFF"
		entry+=( "$(basename "${i}")" )
		entry+=( " " )
		[[ ${i} == "${BS_SCRIPT}" ]] && stat="ON";
		entry+=( "${stat}" )
	done

	if [[ -z ${entry} ]]; then
		logerr " Not found build scripts in ${path}"
		exit 1;
	fi

	if ! which whiptail > /dev/null 2>&1; then
		logext " Please install the whiptail"
	fi

	project=$(whiptail --title "Target script" \
		--radiolist "Select build script : ${BS_SCRIPT_DIR}" 0 50 ${#entry[@]} -- "${entry[@]}" \
		3>&1 1>&2 2>&3)
	[[ -z ${project} ]] && exit 1;

	BS_SCRIPT="${BS_SCRIPT_DIR}/${project}"
	if ! (whiptail --title "Save/Exit" --yesno "Save" 8 78); then
		exit 1;
	fi

	bs_script_set "${BS_SCRIPT}"
}

function bs_script_show () {
	if [[ -z ${BS_TARGETS} ]]; then
		logerr " Not defined targets : BS_TARGETS in ${BS_SCRIPT} !!!"
		exit 1;
	fi

	for t in "${BS_TARGETS[@]}"; do
		bs_op_assign ${t}

		declare -n target=${t}
		declare -n op=${target['op']}
		local -a seq=( ${op['sequence']} )

		logmsg "${target['name']}";
		logmsg " - images\t: ${target['image']}";
		logmsg " - sequence\t: ${seq[*]}";
	done
}

function bs_script_edit () {
	${BS_EDITOR} "${BS_SCRIPT}"
}

function bs_usage () {
	echo " Usage:"
	echo -e "\t$(basename "${0}") <option>"
	echo ""
	echo " option:"
	echo -e  "\t-m \t select script with menuconfig"
	echo -e  "\t-s [script]\t set build script."
	echo -e  "\t-t [target]\t build script's target."
	echo -e  "\t-i [image]\t build target's image."
	echo -e  "\t-c [command]\t build commands supported by target."
	echo -e  "\t-o [option]\t add option to build or config."
	echo -e  "\t-j [jobs]\t set build jobs"
	echo -e  "\t-l\t\t show build script's lists"
	echo -e  "\t-e\t\t edit build script : ${BS_SCRIPT}"
	echo -e  "\t-v\t\t build verbose"
	echo ""

	echo " Build commands supported by target type :"
	local -a op_lists=( ${BS_OP_LISTS[*]} )
	for i in "${op_lists[@]}"; do
		declare -n t=${i}
		echo -ne "\033[0;33m* ${t['name']}\t| \033[0m";
		for n in "${!t[@]}"; do
			[[ ${n} == "type" ]] && continue;
			[[ ${n} == "name" ]] && continue;
			[[ ${n} == "sequence" ]] && continue;
			[[ ${n} == "command" ]] && continue;
			echo -ne "\033[0;33m${n} \033[0m";
		done
		echo -ne "\033[0;33m'target commands' \033[0m";
		echo ""
	done
}

function bs_build_args () {
	while getopts "ms:t:i:c:o:j:levh" opt; do
	case ${opt} in
		m ) bs_menuconfig; exit 0;;
		s )	bs_script_set "${OPTARG}";;
		t )	_BUILD_TARGET="${OPTARG}";;
		i )	_BUILD_IMAGE="${OPTARG}";;
		c )	_BUILD_COMMAND=${OPTARG};;
		l )	bs_script_show; exit 0;;
		o )	_BUILD_OPTION="${OPTARG}";;
		j ) _BUILD_JOBS="-j${OPTARG}";;
		e )	bs_script_edit; exit 0;;
		v )	_BUILD_VERBOSE=true;;
		h )	bs_usage; exit 0;;
		*)	exit 1;;
	esac
	done
}

function bs_build_check () {
	if [[ -n ${_BUILD_TARGET} ]]; then
		local found=false
		local -a list
		for i in "${BS_TARGETS[@]}"; do
			declare -n target=${i}
			list+=( "'${target['name']}'" )
			if [[ ${target['name']} == ${_BUILD_TARGET} ]]; then
				found=true
				break;
			fi
		done
		if [[ ${found} == false ]]; then
			logerr " Error, unknown target : ${_BUILD_TARGET} [ ${list[*]} ]"
			exit 1;
		fi
	fi
}

function bs_build_run() {
	bs_build_check

	for t in ${BS_TARGETS[@]}; do
		bs_op_assign ${t}

		declare -n target="${t}"
		declare -n op=${target['op']}
		local status="unknown"
		local command=${_BUILD_COMMAND}

		if [[ -n ${_BUILD_TARGET} &&
			  ${target['name']} != ${_BUILD_TARGET} ]]; then
			continue;
		fi

		if [[ ! -d ${target['source']} ]]; then
			logerr " Error! not found source : '${target['name']}', ${target['source']} !"
			continue
		fi

		if [[ -n ${command} ]]; then
			if printf '%s\0' "${!op[@]}" | grep -qwz ${command}; then
				func=${op[${command}]}
			else
				func=${op['command']}
			fi
			[[ -z ${func} ]] && logext " Not, implement command: '${command}'";
	
			printf "\033[1;32m %-10s : %-10s\033[0m\n" ${target['name']} ${command}
			${func} target "${command}"
			if [[ ${?} -ne 0 ]]; then
				logext " Error, Set verbose(-v) to print error log !"
			fi
			status="done"
		else
			local -a seq=( ${op['sequence']} )
			for c in ${seq[*]}; do
				func=${op[${c}]}
				if [[ -z ${func} ]]; then
					logext " Not implement op : '${c}'"
				fi

				if [[ ${func} == 'bs_generic_func' ]]; then
					if [[ ${c} == 'prebuild'  && -z ${target['prebuild']} ]] ||
					   [[ ${c} == 'postbuild' && -z ${target['postbuild']} ]]; then
						continue;
					fi
				fi

				printf "\033[1;32m %-10s : %-10s\033[0m\n" ${target['name']} ${c}
				${func} target "${c}"
				if [[ ${?} -ne 0 ]]; then
					logext " Error! Set verbose(-v) to print error log !"
				fi
				status="done"
			done
		fi

		if [[ ${status} == "unknown" ]]; then
			logerr " Not support command: '${c}' for '${target['name']}'\n"
			bs_script_show
		fi
	done
}

if ! bs_script_get; then
	bs_menuconfig;
fi

if [[ -z ${BS_SCRIPT} ]]; then
	logerr " Not selected build script !!!"
	exit 0;
fi

source ${BS_SCRIPT}

bs_build_args "${@}"
bs_build_run
