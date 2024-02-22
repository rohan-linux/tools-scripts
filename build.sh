#!/bin/bash
#
# CMAKE:
#   declare -A BS_TARGET_ELEMENT=(
#       ['target_name']="<name>"                    # required : build target name
#       ['build_type']="cmake or make or linux"     # required : build type [cmake, make, linux]
#
#       ['source_directory']="<source directory>"   # required : build source directory
#
#       ['build_directory']="<build directory>"     # optional : build output directory
#       ['build_prepare']="<shell function>"        # optional : prepare build shell function (before config)
#       ['build_config']="<build configuration >"   # required : if type is linux, specify defconfig
#       ['build_option']="<build option>"           # required : build options
#       ['build_images']="<build image>"            # optional : build target images, support multiple image with shell array
#       ['build_finalize']="<shell function>"       # optional : finalize build shell function (after build)
#
#       ['install_directory']="<install directory>" # optional : build image's install directory
#       ['install_option']="<install option>"       # optional : install options
#       ['install_images']="<output image>"         # optional : build output image names to install,
#                                                   #            must be full path, support multiple image with shell array
#                                                   #            NOTE. If the type is 'cmake' and 'install_images' is empty,
#                                                                      cmake builder will install using the command
#                                                                      cmake --install <build_directory> --prefix <install_directory>
#       ['install_names']="<install renames>"       # optional : copies name to 'install_directory',
#       ['install_complete']="<shell function>"     # optional : shell function (after install)
#    )
#

eval "$(locale | sed -e 's/\(.*\)=.*/export \1=en_US.UTF-8/')"
BS_SHELL_DIR=$(dirname "$(realpath "${0}")")

###############################################################################
# Set Build project shell script
###############################################################################
BS_PROJECT_DIR="$(realpath "${BS_SHELL_DIR}/../project")"
BS_PROJECT_CFG="${BS_PROJECT_DIR}/.bs_config"
BS_PROJECT_EXTEN='bs' # project file extention '*.bs'
BS_PROJECT_SH=""
BS_EDITOR='vim' # editor with '-e' option

###############################################################################
# Build Functions
BS_BUILD_ORDER_CMAKE=('prepare' 'config' 'build' 'finalize' 'install' 'complete')
# shellcheck disable=SC2034
declare -A BS_BUILDER_CMAKE=(
	['type']="cmake"
	['config']=bs_cmake_config
	['build']=bs_cmake_build
	['command']=bs_cmake_command
	['clean']=bs_cmake_clean
	['delete']=bs_generic_delete
	['install']=bs_cmake_install
	['prepare']=bs_generic_func
	['finalize']=bs_generic_func
	['complete']=bs_generic_func
	['order']=${BS_BUILD_ORDER_CMAKE[*]}
)

BS_BUILD_ORDER_MAKE=('prepare' 'build' 'finalize' 'install' 'complete')
# shellcheck disable=SC2034
declare -A BS_BUILDER_MAKE=(
	['type']="make"
	['build']=bs_make_build
	['command']=bs_make_command
	['clean']=bs_make_clean
	['delete']=bs_generic_delete
	['install']=bs_generic_install
	['prepare']=bs_generic_func
	['finalize']=bs_generic_func
	['complete']=bs_generic_func
	['order']=${BS_BUILD_ORDER_MAKE[*]}
)

BS_BUILD_ORDER_LINUX=('prepare' 'defconfig' 'build' 'finalize' 'install' 'complete')
# shellcheck disable=SC2034
declare -A BS_BUILDER_LINUX=(
	['type']="linux"
	['defconfig']=bs_linux_defconfig
	['menuconfig']=bs_linux_menuconfig
	['build']=bs_linux_build
	['command']=bs_linux_command
	['clean']=bs_linux_clean
	['delete']=bs_generic_delete
	['install']=bs_generic_install
	['prepare']=bs_generic_func
	['finalize']=bs_generic_func
	['complete']=bs_generic_func
	['order']=${BS_BUILD_ORDER_LINUX[*]}
)

BS_BUILDER_LISTS=(BS_BUILDER_CMAKE BS_BUILDER_MAKE BS_BUILDER_LINUX)

_BUILD_TARGET=""
_BUILD_IMAGE=""
_BUILD_VERBOSE=false
_BUILD_OPTION=""
_BUILD_COMMAND=""
_BUILD_FORCE=false
_BUILD_JOBS="-j$(grep -c processor /proc/cpuinfo)"

function logerr() { echo -e "\033[1;31m$*\033[0m"; }
function logmsg() { echo -e "\033[0;33m$*\033[0m"; }
function logext() {
	echo -e "\033[1;31m$*\033[0m"
	exit 1
}

function bs_prog_start() {
	local spin='-\|/' pos=0
	local delay=0.3 start=${SECONDS}
	while true; do
		local hrs=$(((SECONDS - start) / 3600))
		local min=$(((SECONDS - start - hrs * 3600) / 60))
		local sec=$(((SECONDS - start) - hrs * 3600 - min * 60))
		pos=$(((pos + 1) % 4))
		printf "\r\t: Progress |${spin:$pos:1}| %d:%02d:%02d" ${hrs} ${min} ${sec}
		sleep ${delay}
	done
}

function bs_prog_kill() {
	local pid=${BS_PROG_ID}
	if pidof "${pid}"; then return; fi
	if [[ ${pid} -ne 0 ]] && [[ -e /proc/${pid} ]]; then
		kill "${pid}" 2>/dev/null
		wait "${pid}" 2>/dev/null
		echo ""
	fi
}

function bs_prog_run() {
	bs_prog_kill
	bs_prog_start &
	echo -en " ${!}"
	BS_PROG_ID=${!}
}

trap bs_prog_kill EXIT

function bs_exec() {
	local exec=${1} err

	# remove first,last space and set multiple space to single space
	exec="$(echo "${exec}" | sed 's/^[ \t]*//;s/[ \t]*$//;s/\s\s*/ /g')"
	logmsg " $ ${exec}"

	if [[ ${_BUILD_VERBOSE} == true ]]; then
		bash -c "${exec}"
		err=${?}
	else
		bs_prog_run
		bash -c "${exec}" >/dev/null 2>&1
		err=${?}
		bs_prog_kill
	fi

	return ${err}
}

function bs_generic_install() {
	declare -n args="${1}"
	local dstdir=${args['install_directory']}
	local dstimg=() dstname=()
	local exec

	IFS=" " read -r -a dstimg <<<"${args['install_images']}"
	IFS=" " read -r -a dstname <<<"${args['install_names']}"

	[[ -z ${dstimg[*]} ]] && return

	if ! mkdir -p "${dstdir}"; then exit 1; fi

	# print install images
	for i in ${!dstimg[*]}; do
		if [[ ! -f "${dstimg[${i}]}" ]] && [[ ! -d "${dstimg[${i}]}" ]]; then
			logerr "   No such file or directory: '${dstimg[${i}]}'"
			if [[ ${_BUILD_FORCE} == true ]]; then
				# remove element
				unset 'dstimg[i]'
				continue
			fi
			return 1
		fi
		logmsg "   ${dstimg[${i}]} > $(realpath "${dstdir}/${dstname[${i}]}")"
	done

	[[ ${_BUILD_VERBOSE} == false ]] && bs_prog_run

	# copy install images
	for i in ${!dstimg[*]}; do
		# delete target directory
		if [[ -z ${dstname[$i]} ]] && [[ -d ${dstimg[$i]} ]] &&
			[[ -d "${dstdir}/$(basename "${dstimg[$i]}")" ]]; then
			bash -c "rm -rf ${dstdir}/$(basename "${dstimg[$i]}")"
		fi
		exec="cp -a ${dstimg[$i]} $(realpath "${dstdir}/${dstname[$i]}")"
		if [[ ${_BUILD_VERBOSE} == true ]]; then
			bash -c "${exec}"
			err=${?}
		else
			bash -c "${exec}" >/dev/null 2>&1
			err=${?}
		fi
	done

	[[ ${_BUILD_VERBOSE} == false ]] && bs_prog_kill

	return "${err}"
}

function bs_generic_delete() {
	declare -n args="${1}"
	local srcdir=${args['source_directory']} outdir=${args['build_directory']}
	local exec="rm -rf ${outdir}"

	[[ -z ${outdir} ]] && return 0
	[[ $(realpath "${srcdir}") == $(realpath "${outdir}") ]] && return 0

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_generic_func() {
	declare -n args="${1}"
	local type="${2}" fn=""

	[[ ${type} == "prepare" ]] && fn=${args['build_prepare']}
	[[ ${type} == "finalize" ]] && fn=${args['build_finalize']}
	[[ ${type} == "complete" ]] && fn=${args['install_complete']}

	[[ -z ${fn} ]] && return 0

	if [[ $(type -t "${fn}") == "function" ]]; then
		${fn} "${1}" "${type}"
	else
		bs_exec "${fn}"
	fi

	return ${?}
}

function bs_cmake_config() {
	declare -n args="${1}"
	local outdir=${args['build_directory']}

	[[ -z ${outdir} ]] && outdir="${args['source_directory']}/build"

	local exec=("cmake"
		"-S ${args['source_directory']}"
		"-B ${outdir}"
		"${args['build_config']}"
		"${_BUILD_OPTION}")

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_cmake_build() {
	declare -n args="${1}"
	declare -n outimg=args['build_images']
	local outdir=${args['build_directory']}
	local exec=()

	[[ -z ${outdir} ]] && outdir="${args['source_directory']}/build"

	exec=("cmake"
		"--build ${outdir}"
		"${args['build_option']}" "${_BUILD_OPTION}")

	if [[ ${_BUILD_IMAGE} ]]; then
		exec+=("-t ${_BUILD_IMAGE}")
	elif [[ "${outimg}" ]]; then
		exec+=("-t ${outimg}")
	fi

	bs_exec "${exec[*]} ${_BUILD_JOBS}"

	return ${?}
}

function bs_cmake_command() {
	declare -n args="${1}"
	local cmd="${2}"
	local outdir=${args['build_directory']}
	local exec=("cmake" "--build ${outdir}" "${_BUILD_OPTION}" "${cmd}")

	[[ -z ${cmd} ]] && return 1
	[[ -z ${outdir} ]] && outdir="${args['source_directory']}/build"

	bs_exec "${exec[*]} ${_BUILD_JOBS}"

	return ${?}
}

function bs_cmake_clean() {
	declare -n args="${1}"
	local exec=("cmake"
		"--build ${args['build_directory']}"
		"${_BUILD_OPTION}"
		"--target clean")

	[[ -z ${args['build_directory']} ]] && return 1

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_cmake_install() {
	declare -n args="${1}"
	local dstimg=args['install_images']
	local exec=("cmake" "--install ${args['build_directory']}")

	# If the type is 'cmake' and 'install_images' is not empty,
	# cmake builder will copyies 'install_images' files to 'result' directory
	# with the name 'install'
	if [[ ${dstimg} ]]; then
		bs_generic_install "${1}"
		return ${?}
	fi

	[[ -n ${args['install_directory']} ]] && exec+=("--prefix ${args['install_directory']}")

	exec+=("${args['install_option']}" "${_BUILD_OPTION}")

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_make_build() {
	declare -n args="${1}"
	local srcdir=${args['source_directory']}
	declare -n outimg=args['build_images']
	local exec=("make"
		"-C ${srcdir}"
		"${args['build_option']}" "${_BUILD_OPTION}")

	if [[ -n ${_BUILD_IMAGE} ]]; then
		bs_exec "${exec[*]} ${_BUILD_IMAGE} ${_BUILD_JOBS}"
		return ${?}
	fi

	if [[ ${outimg} ]]; then
		for i in ${outimg}; do
			if ! bs_exec "${exec[*]} ${i} ${_BUILD_JOBS}"; then
				return 2
			fi
		done
		return 0
	fi

	bs_exec "${exec[*]} ${_BUILD_JOBS}"

	return ${?}
}

function bs_make_command() {
	declare -n args="${1}"
	local cmd="${2}"
	local srcdir=${args['source_directory']}
	local exec=("make"
		"-C ${srcdir}"
		"${args['build_option']}" "${_BUILD_OPTION}")

	[[ -z ${cmd} ]] && return 1

	if [[ -n ${_BUILD_IMAGE} ]]; then
		bs_exec "${exec[*]} ${_BUILD_IMAGE} ${cmd} ${_BUILD_JOBS}"
		return ${?}
	fi

	bs_exec "${exec[*]} ${_BUILD_JOBS}"

	return ${?}
}

function bs_make_clean() {
	declare -n args="${1}"
	local exec=("make" "-C ${args['source_directory']}"
		"${args['build_option']}" "${_BUILD_OPTION}" "clean")

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_linux_defconfig() {
	declare -n args="${1}"
	local srcdir=${args['source_directory']} outdir=${args['build_directory']}
	local exec=("make" "-C ${srcdir}")

	if [[ -n ${outdir} ]]; then
		exec+=("O=${outdir}")
	else
		outdir=${srcdir}
	fi

	if [[ -f "${outdir}/.config" ]]; then
		logmsg " - skip defconfig, exist '${outdir}/.config' ..."
		return 0
	fi

	exec+=("${args['build_option']}" "${_BUILD_OPTION}" "${args['build_config']}")

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_linux_menuconfig() {
	declare -n args="${1}"
	local srcdir=${args['source_directory']} outdir=${args['build_directory']}
	local exec=("make" "-C ${srcdir}")

	if [[ -n ${outdir} ]]; then
		exec+=("O=${outdir}")
	else
		outdir=${srcdir}
	fi

	# check default config
	if [[ ! -d "$(realpath "${outdir}")" || ! -f "$(realpath "${outdir}")/.config" ]]; then
		if ! bs_linux_defconfig "${1}"; then
			return 1
		fi
	fi

	exec+=("${args['build_option']}" "menuconfig")

	_BUILD_VERBOSE=true
	bs_exec "${exec[*]}"

	return ${?}
}

function bs_linux_build() {
	declare -n args="${1}"
	local srcdir=${args['source_directory']} outdir=${args['build_directory']}
	local exec=("make" "-C ${srcdir}")

	if [[ -n ${outdir} ]]; then
		exec+=("O=${outdir}")
	else
		outdir=${srcdir}
	fi

	# check default config
	if [[ ! -d "$(realpath "${outdir}")" || ! -f "$(realpath "${outdir}")/.config" ]]; then
		if ! bs_linux_defconfig "${1}"; then
			return 1
		fi
	fi

	exec+=("${args['build_option']}" "${_BUILD_OPTION}")

	if [[ -n ${_BUILD_IMAGE} ]]; then
		bs_exec "${exec[*]} ${_BUILD_IMAGE} ${_BUILD_JOBS}"
		return ${?}
	fi

	if [[ -n ${args['build_images']} ]]; then
		for i in ${args['build_images']}; do
			if ! bs_exec "${exec[*]} ${i} ${_BUILD_JOBS}"; then
				return 2
			fi
		done
	else
		# buildroot has no image names
		bs_exec "${exec[*]} ${_BUILD_JOBS}"
	fi

	return 0
}

function bs_linux_command() {
	declare -n args="${1}"
	local cmd="${2}"
	local srcdir=${args['source_directory']} outdir=${args['build_directory']}
	local exec=("make" "-C ${srcdir}")

	[[ -z ${cmd} ]] && return 1

	if [[ -n ${outdir} ]]; then
		exec+=("O=${outdir}")
	fi

	[[ ${cmd} == *"menuconfig"* ]] && _BUILD_VERBOSE=true

	exec+=("${args['build_option']}" "${_BUILD_OPTION}" "${cmd}" "${_BUILD_JOBS}")

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_linux_clean() {
	declare -n args="${1}"
	local exec=("make" "-C ${args['source_directory']}")

	[[ -n ${args['build_directory']} ]] && exec+=("O=${args['build_directory']}")

	exec+=("${args['build_option']}" "${_BUILD_OPTION}" "clean")

	bs_exec "${exec[*]}"

	return ${?}
}

function bs_builder_assign() {
	declare -n t="${1}"

	[[ -n ${t['builder']} ]] && return

	for l in "${BS_BUILDER_LISTS[@]}"; do
		declare -n list=${l}
		if [[ ${t['build_type']} == "${list['type']}" ]]; then
			t['builder']=${l}
			break
		fi
	done
}

function bs_project_load() {
	local val

	if [[ ! -f ${BS_PROJECT_CFG} ]]; then
		logerr " Not found ${BS_PROJECT_CFG}"
		return 1
	fi

	val=$(sed -n '/^\<CONFIG\>/p' "${BS_PROJECT_CFG}")
	val=$(echo "${val}" | cut -d'=' -f 2)
	BS_PROJECT_SH="${val//[[:space:]]/}"

	if [[ ! -f ${BS_PROJECT_SH} ]]; then
		logerr "Not found project : ${BS_PROJECT_SH}"
		return 1
	fi

	return 0
}

function bs_project_save() {
	local project=${1}

	if [[ -z ${project} || ! -f ${project} ]]; then
		logerr " Invalid project : ${project}"
		return 1
	fi

	project=$(realpath "${project}")
	logmsg " UPDATE\t: ${project} [${BS_PROJECT_CFG}]"

	# save project config
	cat >"${BS_PROJECT_CFG}" <<EOF
CONFIG = ${project}
EOF
	return 0
}

function bs_project_show() {
	for t in "${BS_TARGETS[@]}"; do
		bs_builder_assign "${t}"

		declare -n target=${t}
		declare -n builder=${target['builder']}
		declare -n order=builder['order']

		logmsg "${target['target_name']}"
		logmsg " - images\t: ${target['build_images']}"
		logmsg " - order\t: ${order}"
	done
}

function bs_project_edit() {
	${BS_EDITOR} "${BS_PROJECT_SH}"
}

function bs_menuconfig() {
	local path=${BS_PROJECT_DIR}
	local -a plist entry
	local array project

	# get project lists
	array=$(find "${path}" -type f -name "*.${BS_PROJECT_EXTEN}")
	for i in ${array}; do
		plist+=("${i}")
	done

	# get porject menu lists
	for i in "${plist[@]}"; do
		stat="OFF"
		entry+=("$(basename "${i}")")
		entry+=(" ")
		[[ ${i} == "${BS_PROJECT_SH}" ]] && stat="ON"
		entry+=("${stat}")
	done

	if [[ -z ${entry[*]} ]]; then
		logerr " Not found build projects in ${path}"
		exit 1
	fi

	if ! which whiptail >/dev/null 2>&1; then
		logext " Please install the whiptail"
	fi

	project=$(whiptail --title "Target project" \
		--radiolist "Select build project : ${BS_PROJECT_DIR}" 0 50 ${#entry[@]} -- "${entry[@]}" \
		3>&1 1>&2 2>&3)
	[[ -z ${project} ]] && exit 1

	BS_PROJECT_SH="${BS_PROJECT_DIR}/${project}"
	if ! (whiptail --title "Save/Exit" --yesno "Save" 8 78); then
		exit 1
	fi

	bs_project_save "${BS_PROJECT_SH}"
}

function bs_usage() {
	echo " Usage:"
	echo -e "\t$(basename "${0}") <option>"
	echo ""
	echo " option:"
	echo -e "\t-m \t\t menuconfig to select project"
	echo -e "\t-p [project]\t set build project."
	echo -e "\t-t [target]\t set build project's target."
	echo -e "\t-i [image]\t select build target."
	echo -e "\t-c [command]\t run commands supported by target."
	echo -e "\t-o [option]\t add option to build,config,install (each step)."
	echo -e "\t-f \t\t force build the next target even if a build error occurs"
	echo -e "\t-j [jobs]\t set build jobs"
	echo -e "\t-l\t\t listup targets in project"
	echo -e "\t-e\t\t edit build project : ${BS_PROJECT_SH}"
	echo -e "\t-v\t\t build verbose"
	echo ""

	echo " Build commands supported by target type :"
	for i in "${BS_BUILDER_LISTS[@]}"; do
		declare -n t=${i}
		echo -ne "\033[0;33m* ${t['type']}\t| commands : \033[0m"
		for n in "${!t[@]}"; do
			[[ ${n} == "type" ]] && continue
			[[ ${n} == "name" ]] && continue
			[[ ${n} == "order" ]] && continue
			[[ ${n} == "command" ]] && continue
			echo -ne "\033[0;33m${n} \033[0m"
		done
		echo -ne "\033[0;33m'misc command' \033[0m"
		echo ""
		echo -ne "\033[0;33m* \t| order    : ${t['order']}\033[0m"
		echo ""
	done
}

function bs_build_args() {
	local _bs_project=''
	local _bs_info=false _bs_edit=false

	bs_project_load

	while getopts "mp:t:i:c:o:j:flevh" opt; do
		case ${opt} in
		m)
			bs_menuconfig
			exit 0
			;;
		p) _bs_project="${OPTARG}" ;;
		t) _BUILD_TARGET="${OPTARG}" ;;
		i) _BUILD_IMAGE="${OPTARG}" ;;
		c) _BUILD_COMMAND=${OPTARG} ;;
		l) _bs_info=true ;;
		o) _BUILD_OPTION="${OPTARG}" ;;
		f) _BUILD_FORCE=true ;;
		j) _BUILD_JOBS="-j${OPTARG}" ;;
		e) _bs_edit=true ;;
		v) _BUILD_VERBOSE=true ;;
		h)
			bs_usage
			exit 0
			;;
		*) exit 1 ;;
		esac
	done

	if [[ -n ${_bs_project} ]]; then
		! bs_project_save "${_bs_project}" && exit 1
		! bs_project_load && exit 1
	fi

	if [[ ${_bs_info} == true ]]; then
		# shellcheck disable=SC1090
		source "${BS_PROJECT_SH}"
		bs_project_show
		exit 0
	fi
	if [[ ${_bs_edit} == true ]]; then
		bs_project_edit
		exit 0
	fi
}

function bs_build_check() {
	if [[ -z ${BS_TARGETS} ]]; then
		logerr " None BS_TARGETS : ${BS_PROJECT_SH} !!!"
		exit 1
	fi

	# Check build target
	if [[ -n ${_BUILD_TARGET} ]]; then
		local found=false
		local -a list
		for i in "${BS_TARGETS[@]}"; do
			declare -n target=${i}
			list+=("'${target['target_name']}'")
			if [[ ${target['target_name']} == "${_BUILD_TARGET}" ]]; then
				found=true
				break
			fi
		done
		if [[ ${found} == false ]]; then
			logerr " Error, unknown target : ${_BUILD_TARGET} [ ${list[*]} ]"
			exit 1
		fi
	fi
}

function bs_build_run() {
	for t in "${BS_TARGETS[@]}"; do
		bs_builder_assign "${t}"

		declare -n target="${t}"
		declare -n builder=${target['builder']}
		local status="unknown"
		local command=${_BUILD_COMMAND}

		if [[ -n ${_BUILD_TARGET} &&
			${target['target_name']} != "${_BUILD_TARGET}" ]]; then
			continue
		fi

		if [[ ! -d ${target['source_directory']} ]]; then
			logerr " Error! not found source : '${target['target_name']}', ${target['source_directory']} !"
			continue
		fi

		if [[ -n ${command} ]]; then
			if printf '%s\0' "${!builder[@]}" | grep -E -qwz "(${command})"; then
				func=${builder[${command}]}
			else
				func=${builder['command']}
			fi
			[[ -z ${func} ]] && logext " Not, implement command: '${command}'"

			printf "\033[1;32m %-10s : %-10s\033[0m\n" "${target['target_name']}" "${command}"
			if ! ${func} target "${command}"; then
				logext "-- Error, build verbose(-v) to print error log, build target --"
			fi
			status="done"
		else
			declare -n order=builder['order']
			for c in ${order}; do
				func=${builder[${c}]}
				if [[ -z ${func} ]]; then
					logext " Not implement builder : '${c}'"
				fi

				if [[ ${c} == 'prepare' && -z ${target['build_prepare']} ]] ||
					[[ ${c} == 'finalize' && -z ${target['build_finalize']} ]] ||
					[[ ${c} == 'complete' && -z ${target['install_complete']} ]]; then
					continue
				fi

				printf "\033[1;32m %-10s : %-10s\033[0m\n" "${target['target_name']}" "${c}"
				if ! ${func} target "${c}"; then
					logerr "-- Error, build verbose(-v) to print error log, build all --"
					if [[ ${_BUILD_FORCE} == true ]]; then
						logerr "-- Continue the build forcefully --"
						continue
					fi
					exit 1
				fi
				status="done"
				echo ""
			done
		fi

		if [[ ${status} == "unknown" ]]; then
			logerr "-- Not support command: '${c}' for '${target['target_name']}'\n"
			bs_project_show
		fi
	done
}

###############################################################################
# Start Build !!!
###############################################################################

bs_build_args "${@}"

if [[ -z ${BS_PROJECT_SH} ]]; then
	logerr " Not selected build project !!!"
	exit 0
fi

logmsg " PROJECT    : '${BS_PROJECT_SH}'\n"
# shellcheck disable=SC1090
source "${BS_PROJECT_SH}"

bs_build_check
bs_build_run
