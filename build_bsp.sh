#!/bin/bash
# Author: Junghyun, Kim <kjh.rohan@gmail.com>
#

# debug
# set -ex

eval "$(locale | sed -e 's/\(.*\)=.*/export \1=en_US.UTF-8/')"

BSP_EDITOR='vim'	# editor with '-e' option

# script's environment elements
declare -A __bsp_env=(
	['CROSS_TOOL']=" "
	['RESULT_DIR']=" "
)

# script's target elements
declare -A __bsp_target=(
	['BUILD_DEPEND']=" "    # target dependency, to support multiple targets, the separator is ' '.
	['BUILD_MANUAL']=" "    # manual build, It true, does not support automatic build and must be built manually.
	['CROSS_TOOL']=" "      # make build crosstool compiler path (set CROSS_COMPILE=)
	['MAKE_ARCH']=" "       # make build architecture (set ARCH=) ex> arm, arm64
	['MAKE_PATH']=" "       # make build source path
	['MAKE_DEFCONFIG']=""   # make default config(defconfig)
	['MAKE_CONFIG']=""      # make config options, TODO
	['MAKE_TARGET']=""      # make build targets, to support multiple targets, the separator is ';'
	['MAKE_CLEANOPT']=""	# make clean option
	['MAKE_NOCLEAN']=""     # if true do not support make clean commands
	['MAKE_OUTDIR']=""      # make locate all output files in 'dir'
	['MAKE_OPTION']=""      # make build option
	['MAKE_INSTALL']=""     # make install options
	['BUILD_PATH']=""       # build source path, The source in this path does not make a build.'
	['BUILD_OUTPUT']=""     # built output images(relative path of MAKE_PATH), to support multiple targets, the separator is ';'
	['BUILD_RESULT']=""     # images names to copy to 'RESULT_DIR', to support multiple targets, the separator is ';'
	['BUILD_PREP']=""       # previous build script before make build.
	['BUILD_POST']=""       # post build script after make build before 'BUILD_OUTPUT' done.
	['BUILD_COMPLETE']=""   # build complete script after 'BUILD_OUTPUT' done.
	['BUILD_CLEAN']=""      # clean script for clean command.
	['BUILD_JOBS']=""       # make build jobs number (-j n)
)

declare -A __bsp_task=(
	['prep']=''
	['conf']=''
	['defconfig']=''
	['make']=''
	['post']=''
	['install']=''
	['result']=''
	['comp']=''
	['clean']=''
)

__bsp_image=()		# store ${BUILD_IMAGES}
__bsp_script_path="$(realpath $(dirname ${BASH_SOURCE}))"
__bsp_script_config="${__bsp_script_path}/.bsp_script"
__bsp_script_rule='build.**.sh'
__bsp_log_dir='.log'	# save to result directory
__bsp_prog_pid=''

function logerr () { echo -e "\033[0;31m$*\033[0m"; }
function logmsg () { echo -e "\033[0;33m$*\033[0m"; }
function logext () { echo -e "\033[0;31m$*\033[0m"; exit -1; }

function fn_usage_format () {
	echo -e " Format ...\n"
	echo -e " BUILD_IMAGES=("
	echo -e "\t\" CROSS_TOOL	= <cross compiler(CROSS_COMPILE) path for the make build> \","
	echo -e "\t\" RESULT_DIR	= <result directory to copy build images> \","
	echo -e "\t\" <TARGET>	="
	echo -e "\t\t BUILD_DEPEND     : < target dependency, to support multiple targets, the separator is ' '. >, "
	echo -e "\t\t BUILD_MANUAL     : < manual build, It true, does not support automatic build and must be built manually. > ,"
	echo -e "\t\t CROSS_TOOL       : < make build crosstool compiler path (set CROSS_COMPILE=) > ,"
	echo -e "\t\t MAKE_ARCH        : < make build architecture (set ARCH=) ex> arm, arm64 > ,"
	echo -e "\t\t MAKE_PATH        : < make build source path > ,"
	echo -e "\t\t MAKE_DEFCONFIG   : < make build default config(defconfig) > ,"
	echo -e "\t\t MAKE_CONFIG      : < make config options, TODO > ,"
	echo -e "\t\t MAKE_TARGET      : < make build targets, to support multiple targets, the separator is ';' > ,"
	echo -e "\t\t MAKE_OUTDIR      : < make locate all output files in 'dir' >,"
	echo -e "\t\t MAKE_CLEANOPT    : < make clean option > ,"
	echo -e "\t\t MAKE_NOCLEAN     : < if true do not support make clean commands >,"
	echo -e "\t\t MAKE_OPTION      : < make build option > ,"
	echo -e "\t\t MAKE_INSTALL     : < make install option > ,"
	echo -e "\t\t BUILD_PATH       : < build source path, The source in this path does not make a build >,"
	echo -e "\t\t BUILD_OUTPUT     : < built output images(relative path of MAKE_PATH), to support multiple file, the separator is ';' > ,"
	echo -e "\t\t BUILD_RESULT     : < images names to copy to 'RESULT_DIR', to support multiple name, the separator is ';' > ,"
	echo -e "\t\t BUILD_PREP       : < previous build before make build. > ,"
	echo -e "\t\t BUILD_POST       : < post build after make build before 'BUILD_OUTPUT' done. > ,"
	echo -e "\t\t BUILD_COMPLETE   : < build complete after 'BUILD_OUTPUT' done. > ,"
	echo -e "\t\t BUILD_CLEAN      : < clean for clean command. > \","
	echo -e "\t\t BUILD_JOBS       : < make build jobs number (-j n) > ,"
	echo -e ""
}

function fn_usage () {
	if [[ ${1} == format ]]; then fn_usage_format; exit 0; fi

	echo " Usage:"
	echo -e "\t$(basename "${0}") -f <script> [options]"
	echo ""
	echo " options:"
	echo -ne "\t menuconfig\t Select the build script with"
	echo -ne " the script name rules is '${__bsp_script_rule}'"
	echo -e  " in the build scripts directory."
	echo -e  "\t\t\t menuconfig is depended '-D' path"
	echo -e  "\t-D [dir]\t set build scripts directory for the menuconfig"
	echo -e  "\t-S [script]\t set build script file\n"
	echo -e  "\t-t [target]\t set build targets, '<TARGET>' ..."
	echo -e  "\t-c [command]\t build command"
	echo -e  "\t-C\t\t clean all targets, this option run make clean/distclean and 'BUILD_CLEAN'"
	echo -e  "\t-i\t\t show target build script info"
	echo -e  "\t-l\t\t listup targets"
	echo -e  "\t-j [jops]\t set build jobs"
	echo -e  "\t-o [option]\t set build options"
	echo -e  "\t-e\t\t edit build build script file"
	echo -e  "\t-v\t\t show build log"
	echo -e  "\t-V\t\t show build log and enable external shell tasks tracing (with 'set -x')"
	echo -e  "\t-p\t\t skip dependency"
	echo -ne "\t-s [task]\t build task :"
	for i in "${!__bsp_task[@]}"; do
		echo -n " '${i}'";
	done
	echo -e  "\n\t\t\t task order : prep > conf:defconfig post > make > post > install:result > comp"
	echo -e  "\t-m\t\t build manual targets 'BUILD_MANUAL'"
	echo -e  "\t-A\t\t Full build including manual build"
	echo -e  "\t-h [option]\t prints all help, option support 'format'"
	echo ""
}

__a_script_path="${__bsp_script_path}/scripts"
__a_build_script=''
__a_build_target=()
__a_build_cmd=''
__a_build_all=false	# include manual targets
__a_build_manual=false
__a_build_option=''
__a_build_task=''
__a_build_depend=true
__a_build_jobs="$(grep -c processor /proc/cpuinfo)"
__a_build_verbose=false
__a_build_trace=false
__a_target_info=false
__a_target_list=false
__a_edit=false

function fn_build_time () {
	local hrs=$(( SECONDS/3600 ));
	local min=$(( (SECONDS-hrs*3600)/60 ));
	local sec=$(( SECONDS-hrs*3600-min*60 ));
	printf "\n Total: %d:%02d:%02d\n" ${hrs} ${min} ${sec}
}

function fn_start_progress () {
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

function fn_kill_progress () {
	local pid=${__bsp_prog_pid}
	if pidof ${pid}; then return; fi
	if [[ ${pid} -ne 0 ]] && [[ -e /proc/${pid} ]]; then
		kill "${pid}" 2> /dev/null
		wait "${pid}" 2> /dev/null
		echo ""
	fi
}

function fn_run_progress () {
	fn_kill_progress
	fn_start_progress &
	echo -en " ${!}"
	__bsp_prog_pid=${!}
}

trap fn_kill_progress EXIT

function fn_print_env () {
	echo -e "\n\033[1;32m BUILD STATUS       = ${__bsp_script_config}\033[0m";
	echo -e "\033[1;32m BUILD CONFIG       = ${__a_build_script}\033[0m";
	echo ""
	for key in "${!__bsp_env[@]}"; do
		[[ -z ${__bsp_env[${key}]} ]] && continue;
		message=$(printf " %-18s = %s\n" "${key}" "${__bsp_env[${key}]}")
		logmsg "${message}"
	done
}

function fn_parse_env () {
	for key in "${!__bsp_env[@]}"; do
		local val=""
		for i in "${__bsp_image[@]}"; do
			if [[ ${i} = *"${key}"* ]]; then
				local elem
				elem="$(echo "${i}" | cut -d'=' -f 2-)"
				elem="$(echo "$elem" | cut -d',' -f 1)"
				elem="$(echo -e "${elem}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
				val=${elem}
				break
			fi
		done
		__bsp_env[${key}]=${val}
	done

	if [[ -z ${__bsp_env['RESULT_DIR']} ]]; then
		__bsp_env['RESULT_DIR']="$(realpath "$(dirname "${0}")")/result"
	fi
	__bsp_log_dir="${__bsp_env['RESULT_DIR']}/${__bsp_log_dir}"
}

function fn_setup_env () {
	local path=${__bsp_target['CROSS_TOOL']}
	[[ -z ${path} ]] && return;

	path=$(realpath "$(dirname "${path}")")
	if [[ -z ${path} ]]; then
		logext " No such 'CROSS_TOOL': $(dirname "${path}")"
	fi
	export PATH=${path}:${PATH}
}

function fn_print_target () {
	local target=${1}

	echo -e "\n\033[1;32m BUILD TARGET       = ${target}\033[0m";
	for key in "${!__bsp_target[@]}"; do
		[[ -z "${__bsp_target[${key}]}" ]] && continue;
		if [[ ${key} == 'MAKE_PATH' ]]; then
			message=$(printf " %-18s = %s\n" "${key}" "$(realpath "${__bsp_target[${key}]}")")
		else
			message=$(printf " %-18s = %s\n" "${key}" "${__bsp_target[${key}]}")
		fi
		logmsg "${message}"
	done
}

declare -A __bsp_dep_target=()
__bsp_dep_list=()

function fn_setup_depend () {
        local target=${1}

	fn_parse_depend "${target}"

	if [[ -z ${__bsp_dep_target['BUILD_DEPEND']} ]]; then
		unset __bsp_dep_list[${#__bsp_dep_list[@]}-1]
		return
	fi

        for d in ${__bsp_dep_target['BUILD_DEPEND']}; do
		if [[ " ${__bsp_dep_list[@]} " =~ "${d}" ]]; then
			echo -e "\033[1;31m Error recursive, Check 'BUILD_DEPEND':\033[0m"
			echo -e "\033[1;31m\t${__bsp_dep_list[@]} ${d}\033[0m"
			exit 1;
		fi
		__bsp_dep_list+=("${d}")
		fn_setup_depend "${d}"
        done
	unset __bsp_dep_list[${#__bsp_dep_list[@]}-1]
}

function fn_parse_depend () {
	local target=${1}
	local contents found=false
	local key='BUILD_DEPEND'

	# get target's contents
	for i in "${__bsp_image[@]}"; do
		if [[ ${i} == *"${target}"* ]]; then
			local elem
			elem="$(echo $(echo "${i}" | cut -d'=' -f 1) | cut -d' ' -f 1)"
			[[ ${target} != "${elem}" ]] && continue;

			# cut
			elem="${i#*$elem*=}"
			# remove line-feed, first and last blank
			contents="$(echo "${elem}" | tr '\n' ' ')"
			contents="$(echo "${contents}" | sed 's/^[ \t]*//;s/[ \t]*$//')"
			found=true
			break
		fi
	done

	if [[ ${found} == false ]]; then
		logext "\n Unknown target '${target}'"
	fi

	# parse contents's elements
	local val=""
	__bsp_dep_target[${key}]=${val}
	if ! echo "${contents}" | grep -qwn "${key}"; then return; fi

	val="${contents#*${key}}"
	val="$(echo "${val}" | cut -d":" -f 2-)"
	val="$(echo "${val}" | cut -d"," -f 1)"
	# remove first,last space and set multiple space to single space
	val="$(echo "${val}" | sed 's/^[ \t]*//;s/[ \t]*$//')"
	val="$(echo "${val}" | sed 's/\s\s*/ /g')"

	__bsp_dep_target[${key}]="${val}"
}

function fn_parse_target () {
	local target=${1}
	local contents found=false

	# get target's contents
	for i in "${__bsp_image[@]}"; do
		if [[ ${i} == *"${target}"* ]]; then
			local elem
			elem="$(echo $(echo "${i}" | cut -d'=' -f 1) | cut -d' ' -f 1)"
			[[ ${target} != "${elem}" ]] && continue;

			# cut
			elem="${i#*${elem}*=}"
			# remove line-feed, first and last blank
			contents="$(echo "${elem}" | tr '\n' ' ')"
			contents="$(echo "${contents}" | sed 's/^[ \t]*//;s/[ \t]*$//')"
			found=true
			break
		fi
	done

	if [[ ${found} == false ]]; then
		logext "\n Unknown target '${target}'"
	fi

	# initialize
	for key in "${!__bsp_target[@]}"; do __bsp_target[${key}]=""; done

	# parse contents's elements
	for key in "${!__bsp_target[@]}"; do
		local val=""
		if ! echo "$contents" | grep -qwn "${key}"; then
			__bsp_target[${key}]=${val}
			[[ ${key} == 'BUILD_MANUAL' ]] && __bsp_target[${key}]=false;
			continue;
		fi
		val="${contents#*${key}}"
		val="$(echo "${val}" | cut -d":" -f 2-)"
		val="$(echo "${val}" | cut -d"," -f 1)"
		# remove first,last space and set multiple space to single space
		val="$(echo "${val}" | sed 's/^[ \t]*//;s/[ \t]*$//')"
		val="$(echo "${val}" | sed 's/\s\s*/ /g')"
		__bsp_target[${key}]="${val}"
	done

	__bsp_target['MAKE_TARGET']=${__bsp_target['MAKE_TARGET']};
	[[ -n ${__bsp_target['MAKE_PATH']} ]] &&
		__bsp_target['MAKE_PATH']=$(realpath "${__bsp_target['MAKE_PATH']}");
	[[ -n ${__bsp_target['MAKE_OUTDIR']} ]] &&
		__bsp_target['MAKE_OUTDIR']=$(readlink -m "${__bsp_target['MAKE_OUTDIR']}");

	[[ -z ${__bsp_target['CROSS_TOOL']} ]] &&
		__bsp_target['CROSS_TOOL']=${__bsp_env['CROSS_TOOL']};
	[[ -z ${__bsp_target['BUILD_JOBS']} ]] &&
		__bsp_target['BUILD_JOBS']=${__a_build_jobs};
}

function fn_parse_target_list () {
	local target_list=()
	local list_manuals=() list_targets=()
	local dump_manuals=() dump_targets=()

	for str in "${__bsp_image[@]}"; do
		local val add=true
		str="$(echo "${str}" | tr '\n' ' ')"
		val="$(echo "${str}" | cut -d'=' -f 1)"
		val="$(echo -e "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

		# skip buil environments"
		for n in "${!__bsp_env[@]}"; do
			if [[ ${n} == "${val}" ]]; then
				add=false
				break
			fi
		done

		[[ ${add} != true ]] && continue;
		[[ ${str} == *"="* ]] && target_list+=("${val}");
	done

	for i in "${__a_build_target[@]}"; do
		local found=false;
		for n in "${target_list[@]}"; do
			if [[ ${i} == "${n}" ]]; then
				found=true
				break;
			fi
		done
		if [[ ${found} == false ]]; then
			echo -e  "\n Unknown target '${i}'"
			echo -ne " Check targets :"
			for t in "${target_list[@]}"; do
				echo -n " ${t}"
			done
			echo -e "\n"
			exit 1;
		fi
	done

	for t in "${target_list[@]}"; do
		fn_parse_target "${t}"
		depend=${__bsp_target['BUILD_DEPEND']}
		[[ -n ${depend} ]] && depend="depend: ${depend}";
		if [[ ${__bsp_target['BUILD_MANUAL']} == true ]]; then
			list_manuals+=("${t}")
			dump_manuals+=("$(printf "%-18s %s\n" "${t}" "${depend} ")")
		else
			list_targets+=("${t}")
			dump_targets+=("$(printf "%-18s %s\n" "${t}" "${depend} ")")
		fi
	done

	if [[ ${#__a_build_target[@]} -eq 0 ]]; then
		__a_build_target=("${list_targets[@]}")
		[[ ${__a_build_manual} == true ]] && __a_build_target=("${list_manuals[@]}");
		[[ ${__a_build_all} == true ]] && __a_build_target=("${list_manuals[@]}" "${list_targets[@]}");
	fi

	# check dependency
	if [[ ${__a_build_depend} == true ]]; then
		for i in "${__a_build_target[@]}"; do
			__bsp_dep_list+=("${i}")
			fn_setup_depend "${i}"
		done
	fi

	if [[ ${__a_target_list} == true ]]; then
		echo -e "\033[1;32m BUILD CONFIG  = ${__a_build_script}\033[0m";
		echo -e "\033[0;33m TARGETS\033[0m";
		for i in "${dump_targets[@]}"; do
			echo -e "\033[0;33m  ${i}\033[0m";
		done
		if [[ ${list_manuals} ]]; then
			echo -e "\033[0;33m\n MANUALLY\033[0m";
			for i in "${dump_manuals[@]}"; do
				echo -e "\033[0;33m  ${i}\033[0m";
			done
		fi
		echo ""
		exit 0;
	fi
}

function fn_shell () {
	local fns=${1} target=${2}
	local log="${__bsp_log_dir}/${target}.script.log"
	local ret

	[[ -z ${fns} ]] && return 0;
	[[ ${__a_build_trace} == true ]] && set -x;

	IFS=";"
	for cmd in ${fns}; do
		cmd="$(echo "${cmd}" | sed 's/\s\s*/ /g')"
		cmd="$(echo "${cmd}" | sed 's/^[ \t]*//;s/[ \t]*$//')"
		cmd="$(echo "${cmd}" | sed 's/\s\s*/ /g')"
		fnc="$(type -t "${cmd}")"
		unset IFS

		logmsg "\n LOG : ${log}"
		logmsg "\n $> ${cmd}"
		rm -f "${log}"
		[[ ${__a_build_verbose} == false ]] && fn_run_progress;

		if [[ "${fnc}" == "function" ]]; then
			# get 2d input arguments in function
			# function FUNC()
			#	declare -n local var="${1}"
			if [[ ${__a_build_verbose} == false ]]; then
				${cmd} __bsp_target >> "${log}" 2>&1
			else
				${cmd} __bsp_target
			fi
		else
			if [[ ${__a_build_verbose} == false ]]; then
				bash -c "${cmd}" >> "${log}" 2>&1
			else
				bash -c "${cmd}"
			fi
		fi
		# get return value
		ret=${?}

		fn_kill_progress
		[[ ${__a_build_trace} == true ]] && set +x;
		if [[ ${ret} -ne 0 ]]; then
			if [[ ${__a_build_verbose} == false ]]; then
				logerr " ERROR: script '${target}': ${log}\n";
			else
				logerr " ERROR: script '${target}'\n";
			fi
			break;
		fi
	done

	return ${ret}
}

function fn_make () {
	local command=$(echo "make ${1}") target=${2}
	local log="${__bsp_log_dir}/${target}.make.log"
	local ret

	logmsg "\n LOG : ${log}"
	logmsg "\n $> ${command}"
	rm -f "${log}"

	[[ ${__a_build_trace} == true ]] && set -x;
	if [[ ${__a_build_verbose} == false ]] && [[ ${command} != *menuconfig* ]]; then
		fn_run_progress
		eval ${command} >> "${log}" 2>&1
	else
		eval ${command}
	fi
	# get return value
	ret=${?}

	fn_kill_progress
	if [[ ${ret} -eq 2 ]] && [[ ${command} != *"clean"* ]]; then
		if [[ ${__a_build_verbose} == false ]]; then
			logerr " ERROR: make '${target}': ${log}\n";
		else
			logerr " ERROR: make '${target}'\n";
		fi
	else
		ret=0
	fi

	return ${ret}
}

function fn_do_exec () {
	if ! fn_shell "${1}" "${2}"; then
		exit 1;
	fi
}

function fn_do_conf () {
	logmsg " *** TODO Implementation ***"
	return
}

function fn_do_make () {
	local cmd=${1} target=${2}
	local path=${__bsp_target['MAKE_PATH']}
	local conf=${__bsp_target['MAKE_DEFCONFIG']}
	local argv=("-C ${path}" "${__bsp_target['MAKE_OPTION']}")

	# check make condition
	[[ -z ${cmd} || -z ${path} ]] && return;
	[[ ! -d ${path} ]] && exit 1;
	[[ ! -f "${path}/makefile" && ! -f "${path}/Makefile" ]] && return;

	# make options
	[[ ${__bsp_target['CROSS_TOOL']} ]] &&
		argv+=( "CROSS_COMPILE=${__bsp_target['CROSS_TOOL']}" );
	[[ ${__bsp_target['MAKE_ARCH']} ]] &&
		argv+=( "ARCH=${__bsp_target['MAKE_ARCH']}" );
	[[ ${__bsp_target['MAKE_OUTDIR']} ]] &&
		argv+=( "O=${__bsp_target['MAKE_OUTDIR']}" );
	[[ ${__bsp_target['MAKE_OUTDIR']} ]] &&
		path=${__bsp_target['MAKE_OUTDIR']}

	[[ ${cmd} == ${conf} && -f "${path}/.config" ]] && return;

	[[ ${cmd} == *"clean"* && -n ${__bsp_target['MAKE_CLEANOPT']} ]] &&
		argv+=( ${__bsp_target['MAKE_CLEANOPT']} )

	argv+=( "${__a_build_option}" "${cmd}" "-j${__bsp_target['BUILD_JOBS']}" )
	if ! fn_make "$( echo "${argv[@]}" )" "${target}"; then
		exit 1;
	fi
}

function fn_do_result () {
	local out=${1} dir=${__bsp_env['RESULT_DIR']}
	local path=${__bsp_target['MAKE_PATH']}
	local ret=${__bsp_target['BUILD_RESULT']}

	[[ -z ${out} ]] && return;
	if ! mkdir -p "${dir}"; then exit 1; fi

	[[ -n ${__bsp_target['MAKE_OUTDIR']} ]] && path=${__bsp_target['MAKE_OUTDIR']}
	ret=$(echo "${ret}" | sed 's/[;,]//g')

	for src in ${out}; do
		[ "${src}" == "${src#/}" ] && src=$(realpath "${path}/${src}");
		src=$(echo "${src}" | sed 's/[;,]//g')
		dst=$(realpath "${dir}/$(echo "${ret}" | cut -d' ' -f1)")
		ret=$(echo ${ret} | cut -d' ' -f2-)
		if [[ ${src} != *'*'* ]] && [[ -d ${src} ]] && [[ -d ${dst} ]]; then
			rm -rf "${dst}";
		fi

		logmsg "\n $> cp -a ${src} ${dst}"
		[[ ${__a_build_verbose} == false ]] && fn_run_progress;
		cp -a ${src} ${dst}
		fn_kill_progress
	done
}

function fn_depend_target () {
	local target=${1}

	for d in ${__bsp_target['BUILD_DEPEND']}; do
		[[ -z ${d} ]] && continue;
		# echo -e "\n\033[1;32m BUILD DEPEND       = ${target} ---> $d\033[0m";
		fn_build_target "${d}";
		fn_parse_target "${target}"
	done
}

function fn_setup_task () {
	# set build tasks
	__bsp_task['conf']=${__bsp_target['MAKE_CONFIG']};
	__bsp_task['defconfig']=${__bsp_target['MAKE_DEFCONFIG']};
	__bsp_task['prep']=${__bsp_target['BUILD_PREP']};
	__bsp_task['post']=${__bsp_target['BUILD_POST']};
	__bsp_task['result']=${__bsp_target['BUILD_OUTPUT']};
	__bsp_task['comp']=${__bsp_target['BUILD_COMPLETE']};
	__bsp_task['clean']=${__bsp_target['BUILD_CLEAN']};

	if [[ ${__bsp_target['MAKE_PATH']} ]]; then
		if [[ ${__a_build_cmd} == *"clean"* ]]; then
			__bsp_task['make']="clean";
		elif [[ ${__bsp_target['MAKE_TARGET']} ]]; then
			__bsp_task['make']="${__bsp_target['MAKE_TARGET']}";
		else
			__bsp_task['make']="all";
		fi
	fi

	if [[ ${__bsp_target['MAKE_INSTALL']} ]]; then
		__bsp_task['install']="install ${__bsp_target['MAKE_INSTALL']}";
	fi

	[[ -z ${__a_build_task} ]] && return;

	for t in "${!__bsp_task[@]}"; do
		if [[ ${t} == ${__a_build_task} ]]; then
			for n in "${!__bsp_task[@]}"; do
				[[ ${n} != ${__a_build_task} ]] && __bsp_task[${n}]=''
			done
			return
		fi
	done

	echo -ne "\n\033[1;31m Not Support task command: ${__a_build_task} ( \033[0m"
	for t in "${!__bsp_task[@]}"; do
		echo -n "${t} "
	done
	echo -e "\033[1;31m)\033[0m\n"
	exit 1;
}

function fn_build_target () {
	local target=${1}

	fn_parse_target "${target}"

	# build dependency
	[[ ${__a_build_depend} == true ]] && fn_depend_target "${target}";
	fn_print_target "${target}"

	[[ ${__a_target_info} == true ]] && return;
	! mkdir -p "${__bsp_env['RESULT_DIR']}" && exit 1;
	! mkdir -p "${__bsp_log_dir}" && exit 1;

	fn_setup_env
	fn_setup_task

	if [[ -n ${__a_build_cmd} ]]; then
		if [[ ${__a_build_cmd} == 'defconfig' &&  ${__bsp_task['defconfig']} ]]; then
			fn_do_make "distclean" "${target}"
			fn_do_make "${__bsp_task['defconfig']}" "${target}"
		else
			if [[ ${__bsp_target['MAKE_NOCLEAN']} != true ]]; then
				fn_do_make "${__a_build_cmd}" "${target}";
			fi
		fi
		if [[ ${__a_build_cmd} == *"clean"* ]]; then
			fn_do_exec "${__bsp_task['clean']}" "${target}"
		fi
	else
		fn_do_exec   "${__bsp_task['prep']}" "${target}"
		fn_do_conf   "${__bsp_task['conf']}" "${target}"
		! fn_do_make "${__bsp_task['defconfig']}" "${target}" && exit 1;
		fn_do_exec   "${__bsp_task['post']}" "${target}"

		if [[ ${__bsp_task['make']} ]]; then
			for t in ${__bsp_task['make']}; do
				! fn_do_make "${t}" "${target}" && exit 1;
			done
		fi

		! fn_do_make "${__bsp_task['install']}" "${target}" && exit 1;
		fn_do_result "${__bsp_task['result']}" "${target}"
		fn_do_exec   "${__bsp_task['comp']}" "${target}"
	fi
}

function fn_run_build () {
	fn_parse_target_list
	fn_print_env

	for i in "${__a_build_target[@]}"; do
		fn_build_target "${i}"
	done

	fn_build_time
}

function fn_setup_script () {
	local script=${1}

	if [[ ! -f ${script} ]]; then
		logext " Not selected build scripts in ${script}"
	fi

	# include build script file
	source "${script}"
	if [[ -z ${BUILD_IMAGES} ]]; then
		logerr " Not defined 'BUILD_IMAGES'\n"
		fn_usage_format
		exit 1
	fi

	__bsp_image=("${BUILD_IMAGES[@]}");
}

function fn_save_script () {
	local path=${1} script=${2}

	if [[ ! -f $(realpath "${__bsp_script_config}") ]]; then
cat > "${__bsp_script_config}" <<EOF
PATH   = $(realpath "${__a_script_path}")
CONFIG =
EOF
	fi

	if [[ -n ${path} ]]; then
		if [[ ! -d $(realpath "${path}") ]]; then
			logext " No such directory: ${path}"
		fi
		sed -i "s|^PATH.*|PATH = ${path}|" "${__bsp_script_config}"
                __a_script_path=${path}
	fi

	if [[ -n ${script} ]]; then
		if [[ ! -f $(realpath "${__a_script_path}/${script}") ]]; then
			logext " No such script: ${path}"
		fi
		sed -i "s/^CONFIG.*/CONFIG = ${script}/" "${__bsp_script_config}"
	fi
}

function fn_parse_script () {
	local table=${1}	# parse table
	local file=${__bsp_script_config}
	local val ret

	[[ ! -f ${file} ]] && return;

	val=$(sed -n '/^\<PATH\>/p' "${file}");
	ret=$(echo "${val}" | cut -d'=' -f 2)
	ret=$(echo "${ret}" | sed 's/[[:space:]]//g')
	__a_script_path="${ret# *}"

	val=$(sed -n '/^\<CONFIG\>/p' "${file}");
	ret=$(echo "${val}" | cut -d'=' -f 2)
	ret=$(echo "${ret}" | sed 's/[[:space:]]//g')
	__a_build_script="$(realpath "${__a_script_path}/"${ret# *}"")"

	val=''
	ret=$(find ${__a_script_path} -print \
		2> >(grep 'No such file or directory' >&2) | \
		grep "${__bsp_script_rule}" | sort)
	for i in ${ret}; do
                i="$(echo "$(basename ${i})" | cut -d'/' -f2)"
		#[[ -n $(echo "${i}" | awk -F".${__bsp_script_rule}" '{print $2}') ]] && continue;
		#[[ ${i} == *common* ]] && continue;
		val="${val} $(echo ${i})"
		eval "${table}=(\"${val}\")"
	done
}

function fn_menu_script () {
	local table=${1}
	local select
	local -a entry

	for i in ${table}; do
		stat="OFF"
		entry+=( "${i}" )
		entry+=( " " )
		[[ ${i} == "$(basename "${__a_build_script}")" ]] && stat="ON";
		entry+=( "${stat}" )
	done

	if ! which whiptail > /dev/null 2>&1; then
		logext " Please install the whiptail"
	fi

	select=$(whiptail --title "Target script" \
		--radiolist "Choose a script" 0 50 ${#entry[@]} -- "${entry[@]}" \
		3>&1 1>&2 2>&3)
	[[ -z ${select} ]] && exit 1;
	__a_build_script=${select}
}

function fn_menu_save () {
	if ! (whiptail --title "Save/Exit" --yesno "Save" 8 78); then
		exit 1;
	fi
	fn_save_script "" "${__a_build_script}"
}

function fn_parse_args () {
	while getopts "f:t:c:Cj:o:s:D:S:mAilevVph" opt; do
	case ${opt} in
		f )	__a_build_script=$(realpath "${OPTARG}");;
		t )	__a_build_target=("${OPTARG}")
			until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
				__a_build_target+=("$(eval "echo \${$OPTIND}")")
				OPTIND=$((OPTIND + 1))
			done
			;;
		c )	__a_build_cmd="${OPTARG}";;
		m )	__a_build_manual=true;;
		A )	__a_build_all=true;;
		j )	__a_build_jobs=${OPTARG};;
		v )	__a_build_verbose=true;;
		V )	__a_build_verbose=true; __a_build_trace=true;;
		p )	__a_build_depend=false;;
		o )	__a_build_option="${OPTARG}";;
		D )	__a_script_path=$(realpath "${OPTARG}")
			fn_save_script "${__a_script_path}" ""
			exit 0;;
		S)      __a_script_path=$(dirname "$(realpath "${OPTARG}")")
                        __a_build_script=$(basename "$(realpath "${OPTARG}")")
                        fn_save_script "${__a_script_path}" "${__a_build_script}"
			exit 0;;
		i ) 	__a_target_info=true;;
		l )	__a_target_list=true;;
		e )	__a_edit=true;
			break;;
		s ) 	__a_build_task="${OPTARG}";;
		h )	fn_usage "$(eval "echo \${$OPTIND}")";
			exit 1;;
	        * )	exit 1;;
	esac
	done
}

###############################################################################
# Run build
###############################################################################
if [[ ${1} == "menuconfig" ]]; then
	fn_parse_args "${@: 2}"
else
	fn_parse_args "${@}"
fi

if [[ -z ${__a_build_script} ]]; then
        avail_list=()
	fn_parse_script avail_list
	if [[ $* == "menuconfig"* && ${__a_build_cmd} != "menuconfig" ]]; then
		fn_menu_script "${avail_list}"
		fn_menu_save
		echo -e "\033[1;32m SAVE : ${__bsp_script_config}\n\033[0m";
		logmsg "$(sed -e 's/^/ /' < "${__bsp_script_config}")"
		exit 0;
	fi
	if [[ -z ${__a_build_script} ]]; then
		logerr " Not selected build script in ${__a_script_path}"
		logerr " Set build script with -f <script> or menuconfig option"
		exit 1;
	fi
fi

fn_setup_script "${__a_build_script}"

if [[ "${__a_edit}" == true ]]; then
	${BSP_EDITOR} "${__a_build_script}"
	exit 0;
fi

fn_parse_env
fn_run_build
