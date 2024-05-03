#!/bin/bash
#
# CMAKE:
#   declare -A BS_TARGET_ELEMENT=(
#       ['target_name']="<name>"                    # required : build target name
#       ['build_type']="cmake or make or linux"     # required : build type [cmake, meson, make, linux]
#
#       ['source_directory']="<source directory>"   # required : build source directory
#
#       ['build_directory']="<build directory>"     # optional : build output directory
#       ['build_prepare']="<shell function>"        # optional : prepare build shell function (before config)
#       ['build_config']="<build configuration >"   # required : if type is linux, specify defconfig
#       ['build_option']="<build option>"           # required : build options
#       ['build_images']="<build image>"            # optional : build target images, support multiple image with shell array
#       ['build_function']="<shell build>"          # required : shell script function to support 'build_type':'shell'
#       ['build_finalize']="<shell function>"       # optional : finalize build shell function (after build)
#
#       ['install_directory']="<install directory>" # optional : build image's install directory
#       ['install_option']="<install option>"       # optional : install options
#       ['install_images']="<output image>"         # optional : build output image names to install,
#                                                   #            must be full path, support multiple image with shell array
#                                                   #            NOTE. If the type is 'cmake' and 'install_images' is empty,
#                                                                      cmake system will install using the command
#                                                                      cmake --install <build_directory> --prefix <install_directory>
#       ['install_names']="<install renames>"       # optional : copies name to 'install_directory',
#       ['install_function']="<shell build>"        # optional : shell script function to support 'build_type':'shell'
#       ['install_complete']="<shell function>"     # optional : shell function (after install)
#    )
#

###############################################################################
# Set build shell script
###############################################################################
eval "$(locale | sed -e 's/\(.*\)=.*/export \1=en_US.UTF-8/')"

BS_CONFIG_DIR="$(pwd)/tools/project"
BS_CONFIG_CFG="$(pwd)/.bs_config"
BS_EXTETION='bs' # config file extention '*.bs'
BS_CONFIG=""
BS_EDITOR='vim' # editor with '-e' option

###############################################################################
# Build Functions
BS_SYSTEM_CMAKE_ORDER=('prepare' 'config' 'build' 'finalize' 'install' 'complete')
# shellcheck disable=SC2034
declare -A BS_SYSTEM_CMAKE=(
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
	['order']=${BS_SYSTEM_CMAKE_ORDER[*]}
)

BS_SYSTEM_MESON_ORDER=('prepare' 'config' 'build' 'finalize' 'install' 'complete')
# shellcheck disable=SC2034
declare -A BS_SYSTEM_MESON=(
	['type']="meson"
	['config']=bs_meson_setup
	['build']=bs_meson_build
	['command']=bs_meson_command
	['clean']=bs_meson_clean
	['delete']=bs_generic_delete
	['install']=bs_meson_install
	['prepare']=bs_generic_func
	['finalize']=bs_generic_func
	['complete']=bs_generic_func
	['order']=${BS_SYSTEM_MESON_ORDER[*]}
)

BS_SYSTEM_MAKE_ORDER=('prepare' 'build' 'finalize' 'install' 'complete')
# shellcheck disable=SC2034
declare -A BS_SYSTEM_MAKE=(
	['type']="make"
	['build']=bs_make_build
	['command']=bs_make_command
	['clean']=bs_make_clean
	['delete']=bs_generic_delete
	['install']=bs_generic_install
	['prepare']=bs_generic_func
	['finalize']=bs_generic_func
	['complete']=bs_generic_func
	['order']=${BS_SYSTEM_MAKE_ORDER[*]}
)

BS_SYSTEM_LINUX_ORDER=('prepare' 'defconfig' 'build' 'finalize' 'install' 'complete')
# shellcheck disable=SC2034
declare -A BS_SYSTEM_LINUX=(
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
	['order']=${BS_SYSTEM_LINUX_ORDER[*]}
)

BS_SYSTEM_SHELL_ORDER=('prepare' 'build' 'finalize' 'install' 'complete')
# shellcheck disable=SC2034
declare -A BS_SYSTEM_SHELL=(
	['type']="shell"
	['build']=bs_shell_build
	['command']=bs_shell_build
	['install']=bs_shell_install
	['prepare']=bs_generic_func
	['finalize']=bs_generic_func
	['complete']=bs_generic_func
	['order']=${BS_SYSTEM_SHELL_ORDER[*]}
)

# system list
BS_SYSTEM_LISTS=(
	BS_SYSTEM_CMAKE
	BS_SYSTEM_MESON
	BS_SYSTEM_MAKE
	BS_SYSTEM_LINUX
	BS_SYSTEM_SHELL
)

# options
_build_target=""
_build_image=""
_build_verbose=false
_build_option=""
_build_command=""
_build_force=false
_build_jobs="-j$(grep -c processor /proc/cpuinfo)"

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
	local pid=${_program_id}
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
	_program_id=${!}
}

trap bs_prog_kill EXIT

function bs_exec_sh() {
	local exec=${1} err

	# remove first,last space and set multiple space to single space
	exec="$(echo "${exec}" | sed 's/^[ \t]*//;s/[ \t]*$//;s/\s\s*/ /g')"
	logmsg " $ ${exec}"

	if [[ ${_build_verbose} == true ]]; then
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
			if [[ ${_build_force} == true ]]; then
				# remove element
				unset 'dstimg[i]'
				continue
			fi
			return 1
		fi
		logmsg "   ${dstimg[${i}]} > $(realpath "${dstdir}/${dstname[${i}]}")"
	done

	[[ ${_build_verbose} == false ]] && bs_prog_run

	# copy install images
	for i in ${!dstimg[*]}; do
		# delete target directory
		if [[ -z ${dstname[$i]} ]] && [[ -d ${dstimg[$i]} ]] &&
			[[ -d "${dstdir}/$(basename "${dstimg[$i]}")" ]]; then
			bash -c "rm -rf ${dstdir}/$(basename "${dstimg[$i]}")"
		fi
		exec="cp -a ${dstimg[$i]} $(realpath "${dstdir}/${dstname[$i]}")"
		if [[ ${_build_verbose} == true ]]; then
			bash -c "${exec}"
			err=${?}
		else
			bash -c "${exec}" >/dev/null 2>&1
			err=${?}
		fi
	done

	[[ ${_build_verbose} == false ]] && bs_prog_kill

	return "${err}"
}

function bs_generic_delete() {
	declare -n args="${1}"
	local srcdir=${args['source_directory']} outdir=${args['build_directory']}
	local exec="rm -rf ${outdir}"

	[[ -z ${outdir} ]] && return 0
	[[ $(realpath "${srcdir}") == $(realpath "${outdir}") ]] && return 0

	bs_exec_sh "${exec[*]}"

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
		bs_exec_sh "${fn}"
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
		"${_build_option}")

	bs_exec_sh "${exec[*]}"

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
		"${args['build_option']}" "${_build_option}")

	if [[ ${_build_image} ]]; then
		exec+=("-t ${_build_image}")
	elif [[ "${outimg}" ]]; then
		exec+=("-t ${outimg}")
	fi

	bs_exec_sh "${exec[*]} ${_build_jobs}"

	return ${?}
}

function bs_cmake_command() {
	declare -n args="${1}"
	local cmd="${2}"
	local outdir=${args['build_directory']}
	local exec=("cmake" "--build ${outdir}" "${_build_option}" "${cmd}")

	[[ -z ${cmd} ]] && return 1
	[[ -z ${outdir} ]] && outdir="${args['source_directory']}/build"

	bs_exec_sh "${exec[*]} ${_build_jobs}"

	return ${?}
}

function bs_cmake_clean() {
	declare -n args="${1}"
	local exec=("cmake"
		"--build ${args['build_directory']}"
		"${_build_option}"
		"--target clean")

	[[ -z ${args['build_directory']} ]] && return 1

	bs_exec_sh "${exec[*]}"

	return ${?}
}

function bs_cmake_install() {
	declare -n args="${1}"
	declare -n dstimg=args['install_images']
	local exec=("cmake" "--install ${args['build_directory']}")

	# If the type is 'cmake' and 'install_images' is not empty,
	# cmake system will copyies 'install_images' files to 'install_directory'
	# with the name 'install'
	if [[ -n "${dstimg}" ]]; then
		bs_generic_install "${1}"
		return ${?}
	fi

	[[ -n ${args['install_directory']} ]] && exec+=("--prefix ${args['install_directory']}")

	exec+=("${args['install_option']}" "${_build_option}")

	bs_exec_sh "${exec[*]}"

	return ${?}
}

function bs_meson_setup() {
	declare -n args="${1}"
	local srcdir=${args['source_directory']}
	local outdir=${args['build_directory']}

	[[ -z ${outdir} ]] && outdir="${srcdir}/build"

	local exec=("meson" "setup" "${args['build_config']}"
		"${outdir}" "${srcdir}" "${_build_option}")

	bs_exec_sh "${exec[*]}"

	return ${?}
}

function bs_meson_build() {
	declare -n args="${1}"
	declare -n outimg=args['build_images']
	local srcdir=${args['source_directory']} outdir=${args['build_directory']}
	local exec=()

	[[ -z ${outdir} ]] && outdir="${srcdir}/build"

	exec=("meson" "compile" -C "${outdir}" "${_build_option}")

	if [[ ${_build_image} ]]; then
		exec+=("${_build_image}")
	elif [[ "${outimg}" ]]; then
		exec+=("${outimg}")
	fi

	bs_exec_sh "${exec[*]} ${_build_jobs}"

	return ${?}
}

function bs_meson_command() {
	declare -n args="${1}"
	local cmd="${2}"
	local exec=("meson" "${cmd}" "${_build_option}")

	[[ -z ${cmd} ]] && return 1

	bs_exec_sh "${exec[*]}"

	return ${?}
}

function bs_meson_clean() {
	declare -n args="${1}"
	declare -n outimg=args['build_images']
	local srcdir=${args['source_directory']} outdir=${args['build_directory']}
	local exec=()

	[[ -z ${outdir} ]] && outdir="${srcdir}/build"

	exec=("meson" "compile" "--clean" -C "${outdir}" "${_build_option}")

	bs_exec_sh "${exec[*]} ${_build_jobs}"

	return ${?}
}

function bs_meson_install() {
	declare -n args="${1}"
	local srcdir=${args['source_directory']} outdir=${args['build_directory']}
	local -n dstimg=args['install_images']
	local exec=("meson" "install")

	# If the type is 'meson' and 'install_images' is not empty,
	# meson system will copyies 'install_images' files to 'install directory'
	# with the name 'install'
	if [[ -n "${dstimg}" ]]; then
		bs_generic_install "${1}"
		return ${?}
	fi

	[[ -z ${outdir} ]] && outdir="${srcdir}/build"

	exec+=("-C ${outdir}")
	[[ -n ${args['install_directory']} ]] && exec+=("--destdir ${args['install_directory']}")
	exec+=("${args['install_option']}" "${_build_option}")

	bs_exec_sh "${exec[*]}"

	return ${?}
}
function bs_make_build() {
	declare -n args="${1}"
	local srcdir=${args['source_directory']}
	declare -n outimg=args['build_images']
	local exec=("make"
		"-C ${srcdir}"
		"${args['build_option']}" "${_build_option}")

	if [[ -n ${_build_image} ]]; then
		bs_exec_sh "${exec[*]} ${_build_image} ${_build_jobs}"
		return ${?}
	fi

	if [[ ${outimg} ]]; then
		for i in ${outimg}; do
			if ! bs_exec_sh "${exec[*]} ${i} ${_build_jobs}"; then
				return 2
			fi
		done
		return 0
	fi

	bs_exec_sh "${exec[*]} ${_build_jobs}"

	return ${?}
}

function bs_make_command() {
	declare -n args="${1}"
	local cmd="${2}"
	local srcdir=${args['source_directory']}
	local exec=("make"
		"-C ${srcdir}"
		"${args['build_option']}" "${_build_option}")

	[[ -z ${cmd} ]] && return 1

	if [[ -n ${_build_image} ]]; then
		bs_exec_sh "${exec[*]} ${_build_image} ${cmd} ${_build_jobs}"
		return ${?}
	fi

	bs_exec_sh "${exec[*]} ${_build_jobs}"

	return ${?}
}

function bs_make_clean() {
	declare -n args="${1}"
	local exec=("make" "-C ${args['source_directory']}"
		"${args['build_option']}" "${_build_option}" "clean")

	bs_exec_sh "${exec[*]}"

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

	exec+=("${args['build_option']}" "${_build_option}" "${args['build_config']}")

	bs_exec_sh "${exec[*]}"

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

	_build_verbose=true
	bs_exec_sh "${exec[*]}"

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

	exec+=("${args['build_option']}" "${_build_option}")

	if [[ -n ${_build_image} ]]; then
		bs_exec_sh "${exec[*]} ${_build_image} ${_build_jobs}"
		return ${?}
	fi

	if [[ -n ${args['build_images']} ]]; then
		for i in ${args['build_images']}; do
			if ! bs_exec_sh "${exec[*]} ${i} ${_build_jobs}"; then
				return 2
			fi
		done
	else
		# buildroot has no image names
		bs_exec_sh "${exec[*]} ${_build_jobs}"
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

	[[ ${cmd} == *"menuconfig"* ]] && _build_verbose=true

	exec+=("${args['build_option']}" "${_build_option}" "${cmd}" "${_build_jobs}")

	bs_exec_sh "${exec[*]}"

	return ${?}
}

function bs_linux_clean() {
	declare -n args="${1}"
	local exec=("make" "-C ${args['source_directory']}")

	[[ -n ${args['build_directory']} ]] && exec+=("O=${args['build_directory']}")

	exec+=("${args['build_option']}" "${_build_option}" "clean")

	bs_exec_sh "${exec[*]}"

	return ${?}
}

function bs_shell_build() {
	declare -n args="${1}"
	local dir=${args['source_directory']} fn=${args['build_function']}

	[[ -z ${fn} ]] && return 0

	if [[ -d ${dir} ]]; then
		pushd ${dir} >/dev/null 2>&1
		logmsg " $ cd $(pwd)"
		fn="./${fn}"
	fi

	if [[ $(type -t "${fn}") == "function" ]]; then
		${fn} "${1} ${_build_command} ${_build_option}" "${type}"
	else
		bs_exec_sh "${fn} ${args['build_option']} ${_build_command} ${_build_option}"
	fi

	[[ -d ${dir} ]] && popd >/dev/null 2>&1

	return ${?}
}

function bs_shell_install() {
	declare -n args="${1}"
	local dir=${args['source_directory']} fn=${args['install_function']}

	if [[ -z ${fn} ]]; then
		if [[ -n ${args['build_function']} ]]; then
			fn=${args['build_function']}
		else
			return 0
		fi
	fi

	if [[ -d ${dir} ]]; then
		pushd ${dir} >/dev/null 2>&1
		logmsg " $ cd $(pwd)"
		fn="./${fn}"
	fi

	if [[ $(type -t "${fn}") == "function" ]]; then
		${fn} "${1} ${_build_option}" "${type}"
	else
		bs_exec_sh "${fn} ${args['install_option']} ${_build_option}"
	fi

	[[ -d ${dir} ]] && popd >/dev/null 2>&1

	return ${?}
}

function bs_system_assign() {
	declare -n t="${1}"

	[[ -n ${t['system']} ]] && return

	for l in "${BS_SYSTEM_LISTS[@]}"; do
		declare -n list=${l}
		if [[ ${t['build_type']} == "${list['type']}" ]]; then
			t['system']=${l}
			break
		fi
	done
}

function bs_config_load() {
	local val

	if [[ ! -f ${BS_CONFIG_CFG} ]]; then
		logerr " Not found ${BS_CONFIG_CFG}"
		return 1
	fi

	val=$(sed -n '/^\<CONFIG\>/p' "${BS_CONFIG_CFG}")
	val=$(echo "${val}" | cut -d'=' -f 2)
	BS_CONFIG="${val//[[:space:]]/}"

	if [[ ! -f ${BS_CONFIG} ]]; then
		logerr "Not found config file: ${BS_CONFIG}"
		return 1
	fi

	return 0
}

function bs_config_save() {
	local config=${1}

	if [[ -z ${config} || ! -f ${config} ]]; then
		logerr " Invalid config file: ${config}"
		return 1
	fi

	config=$(realpath "${config}")
	logmsg " UPDATE     : ${config} [${BS_CONFIG_CFG}]"

	# save config
	cat >"${BS_CONFIG_CFG}" <<EOF
CONFIG = ${config}
EOF
	return 0
}

function bs_config_show() {
	if [[ -z "${BS_TARGETS[*]}" ]]; then
		logerr " Not defined 'BS_TARGETS' in ${BS_CONFIG} !!!"
		exit 1
	fi

	logmsg " CONFIG     - ${BS_CONFIG}"
	for t in "${BS_TARGETS[@]}"; do
		bs_system_assign "${t}"
		declare -n target=${t}
		printf "\033[0;33m %-10s : %-6s - %s\033[0m\n" \
			"* ${target['target_name']}" "${target['build_type']}" "${target['build_images']}"
	done
}

function bs_config_edit() {
	${BS_EDITOR} "${BS_CONFIG}"
}

function bs_config_menu() {
	local path=${BS_CONFIG_DIR}
	local -a plist entry
	local array config

	# get config lists
	array=$(find "${path}" -type f -name "*.${BS_EXTETION}")
	for i in ${array}; do
		plist+=("${i}")
	done

	# get porject menu lists
	for i in "${plist[@]}"; do
		stat="OFF"
		entry+=("$(basename "${i}")")
		entry+=(" ")
		[[ ${i} == "${BS_CONFIG}" ]] && stat="ON"
		entry+=("${stat}")
	done

	if [[ -z ${entry[*]} ]]; then
		logerr " Not found build configs in ${path}"
		exit 1
	fi

	if ! which whiptail >/dev/null 2>&1; then
		logext " Please install the whiptail"
	fi

	config=$(whiptail --title "Target CONFIG" \
		--radiolist "Select IN : ${BS_CONFIG_DIR}" 0 50 ${#entry[@]} -- "${entry[@]}" \
		3>&1 1>&2 2>&3)
	[[ -z ${config} ]] && exit 1

	BS_CONFIG="${BS_CONFIG_DIR}/${config}"
	if ! (whiptail --title "Save/Exit" --yesno "Save" 8 78); then
		exit 1
	fi

	bs_config_save "${BS_CONFIG}"
}

function bs_usage() {
	echo " Usage:"
	echo -e "\t$(basename "${0}") <option>"
	echo ""
	echo " option:"
	echo -e "\t-m \t\t menuconfig to select config"
	echo -e "\t-p [config]\t set build config."
	echo -e "\t-t [target]\t set config's target."
	echo -e "\t-i [image]\t select build target."
	echo -e "\t-c [command]\t run commands supported by target."
	echo -e "\t-o [option]\t add option to build,config,install (each step)."
	echo -e "\t-f \t\t force build the next target even if a build error occurs"
	echo -e "\t-j [jobs]\t set build jobs"
	echo -e "\t-l\t\t listup targets in config"
	echo -e "\t-e\t\t edit config : ${BS_CONFIG}"
	echo -e "\t-v\t\t build verbose"
	echo ""

	echo " Build commands supported by target type :"
	for i in "${BS_SYSTEM_LISTS[@]}"; do
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
	local listup=false edit=false
	local config=''

	bs_config_load

	while getopts "mp:t:i:c:o:j:flevh" opt; do
		case ${opt} in
		m)
			bs_config_menu
			exit 0
			;;
		p) config="${OPTARG}" ;;
		t) _build_target="${OPTARG}" ;;
		i) _build_image="${OPTARG}" ;;
		c) _build_command=${OPTARG} ;;
		l) listup=true ;;
		o) _build_option="${OPTARG}" ;;
		f) _build_force=true ;;
		j) _build_jobs="-j${OPTARG}" ;;
		e) edit=true ;;
		v) _build_verbose=true ;;
		h)
			bs_usage
			exit 0
			;;
		*) exit 1 ;;
		esac
	done

	if [[ -n ${config} ]]; then
		! bs_config_save "${config}" && exit 1
		! bs_config_load && exit 1
	fi
	if [[ ${listup} == true ]]; then
		# shellcheck disable=SC1090
		source "${BS_CONFIG}"
		bs_config_show
		exit 0
	fi
	if [[ ${edit} == true ]]; then
		bs_config_edit
		exit 0
	fi
}

function bs_build_check() {
	if [[ -z "${BS_TARGETS[*]}" ]]; then
		logerr " Not defined 'BS_TARGETS' in ${BS_CONFIG} !!!"
		exit 1
	fi

	# Check build target
	if [[ -n ${_build_target} ]]; then
		local found=false
		local -a list
		for i in "${BS_TARGETS[@]}"; do
			declare -n target=${i}
			list+=("'${target['target_name']}'")
			if [[ ${target['target_name']} == "${_build_target}" ]]; then
				found=true
				break
			fi
		done
		if [[ ${found} == false ]]; then
			logerr " Error, unknown target : ${_build_target} [ ${list[*]} ]"
			exit 1
		fi
	fi
}

function bs_build_run() {
	for t in "${BS_TARGETS[@]}"; do
		bs_system_assign "${t}"

		declare -n target="${t}"
		declare -n system=${target['system']}
		local status="unknown"
		local command=${_build_command}

		if [[ -n ${_build_target} &&
			${target['target_name']} != "${_build_target}" ]]; then
			continue
		fi

		if [[ ${target['build_type']} != 'shell' ]] &&
			[[ ! -d ${target['source_directory']} ]]; then
			logerr " Error! not found source : '${target['target_name']}', ${target['source_directory']} !"
			continue
		fi

		if [[ -n ${command} ]]; then
			if printf '%s\0' "${!system[@]}" | grep -E -qwz "(${command})"; then
				func=${system[${command}]}
			else
				func=${system['command']}
			fi
			[[ -z ${func} ]] && logext " Not, implement command: '${command}'"

			printf "\033[1;32m %-10s : %-10s\033[0m\n" "* ${target['target_name']}" "${command}"
			if ! ${func} target "${command}"; then
				logext "-- Error, build verbose(-v) to print error log, build target --"
			fi
			status="done"
		else
			printf "\033[1;32m ***** [ %s ] *****\033[0m\n" "${target['target_name']}"
			declare -n order=system['order']
			for c in ${order}; do
				func=${system[${c}]}
				if [[ -z ${func} ]]; then
					logext " Not implement system : '${c}'"
				fi

				if [[ ${c} == 'prepare' && -z ${target['build_prepare']} ]] ||
					[[ ${c} == 'finalize' && -z ${target['build_finalize']} ]] ||
					[[ ${c} == 'complete' && -z ${target['install_complete']} ]]; then
					continue
				fi

				printf "\033[1;32m - %s\033[0m\n" "${c}"
				if ! ${func} target "${c}"; then
					logerr "-- Error, build verbose(-v) to print error log, build all --"
					if [[ ${_build_force} == true ]]; then
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
			bs_config_show
		fi
	done
}

###############################################################################
# Start Build !!!
###############################################################################

bs_build_args "${@}"

if [[ -z ${BS_CONFIG} ]]; then
	logerr " Not selected build CONFIG !!!"
	exit 0
fi

logmsg " CONFIG     : ${BS_CONFIG}\n"
# shellcheck disable=SC1090
source "${BS_CONFIG}"

bs_build_check
bs_build_run
