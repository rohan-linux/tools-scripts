#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#

eval "$(locale | sed -e 's/\(.*\)=.*/export \1=en_US.UTF-8/')"

EDIT_TOOL="vim"	# editor with '-e' option

# config script's environment elements
declare -A __bsp_env__=(
	["CROSS_TOOL"]=" "
	["RESULT_DIR"]=" "
)

# config script's target elements
declare -A __bsp_target__=(
	["BUILD_DEPEND"]=" "	# target dependency, to support multiple targets, the separator is' '.
	["BUILD_MANUAL"]=" "	# manual build, It true, does not support automatic build and must be built manually.
	["CROSS_TOOL"]=" "	# make build crosstool compiler path (set CROSS_COMPILE=)
	["MAKE_ARCH"]=" "	# make build architecture (set ARCH=) ex> arm, arm64
	["MAKE_PATH"]=" "	# make build source path
	["MAKE_CONFIG"]=""	# make build default config(defconfig)
	["MAKE_TARGET"]=""	# make build targets, to support multiple targets, the separator is';'
	["MAKE_NOCLEAN"]=""	# if true do not support make clean commands
	["MAKE_OPTION"]=""	# make build option
	["BUILD_OUTPUT"]=""	# make built output images to copy resultdir, to support multiple targets, the separator is';'
	["BUILD_RESULT"]=""	# copy names to RESULT_DIR, to support multiple targets, the separator is';'
	["MAKE_JOBS"]=" "	# make build jobs number (-j n)
	["BUILD_PREV"]=" "	# previous build script before make build.
	["BUILD_POST"]=""	# post build script after make build before copy 'BUILD_OUTPUT' done.
	["BUILD_LAST"]=""	# late build script after copy 'BUILD_OUTPUT' done.
	["BUILD_CLEAN"]=" "	# clean script for clean command.
)

__bsp_script_dir="$(dirname "$(realpath "$0")")"
__bsp_config_info="${__bsp_script_dir}/.bsp_config"
__bsp_config_prefix="build."
__bsp_config_extend="sh"
__bsp_log_dir=".log"	# save to result directory
__bsp_image=()	# store ${BUILD_IMAGES}
__bsp_progress_pid=""

function show_format () {
	echo -e " Format ...\n"
	echo -e " BUILD_IMAGES=("
	echo -e "\t\" CROSS_TOOL	= <cross compiler(CROSS_COMPILE) path for the make build> \","
	echo -e "\t\" RESULT_DIR	= <result directory to copy build images> \","
	echo -e "\t\" <TARGET>	="
	echo -e "\t\t BUILD_DEPEND    : < target dependency, to support multiple targets, the separator is' '. >, "
	echo -e "\t\t BUILD_MANUAL    : < manual build, It true, does not support automatic build and must be built manually. > ,"
	echo -e "\t\t CROSS_TOOL      : < make build crosstool compiler path (set CROSS_COMPILE=) > ,"
	echo -e "\t\t MAKE_ARCH       : < make build architecture (set ARCH=) ex> arm, arm64 > ,"
	echo -e "\t\t MAKE_PATH       : < make build source path > ,"
	echo -e "\t\t MAKE_CONFIG     : < make build default config(defconfig) > ,"
	echo -e "\t\t MAKE_TARGET     : < make build targets, to support multiple targets, the separator is';' > ,"
	echo -e "\t\t MAKE_NOCLEAN : < if true do not support make clean commands > ,"
	echo -e "\t\t MAKE_OPTION     : < make build option > ,"
	echo -e "\t\t BUILD_OUTPUT     : < make built images to copy resultdir, to support multiple file, the separator is';' > ,"
	echo -e "\t\t BUILD_RESULT     : < copy names to RESULT_DIR, to support multiple name, the separator is';' > ,"
	echo -e "\t\t MAKE_JOBS       : < make build jobs number (-j n) > ,"
	echo -e "\t\t BUILD_PREV      : < previous build before make build. > ,"
	echo -e "\t\t BUILD_POST      : < post build after make build before copy 'BUILD_OUTPUT' done. > ,"
	echo -e "\t\t BUILD_LAST      : < last build after copy 'BUILD_OUTPUT' done. > ,"
	echo -e "\t\t BUILD_CLEAN     : < clean for clean command. > \","
	echo -e ""
}

function usage () {
	if [[ "${1}" == "format" ]]; then show_format; exit 0; fi

	echo " Usage:"
	echo -e "\t$(basename "$0") -f <config> [options]"
	echo ""
	echo " options:"
	echo -ne "\t menuconfig\t Select the config with"
	echo -ne " the prefix '${__bsp_config_prefix}' and extend '.${__bsp_config_extend}'"
	echo -e  " in the configs directory."
	echo -e  "\t\t\t menuconfig is depended '-D' path"
	echo -e  "\t-D [dir]\t set configs directory for the menuconfig"
	echo -e  "\t-S [config]\t set build config file\n"
	echo -e  "\t-t [target]\t set build targets, '<TARGET>' ..."
	echo -e  "\t-c [command]\t run command"
	echo -e  "\t\t\t support 'cleanbuild','rebuild' and commands supported by target"
	echo -e  "\t-C\t\t clean all targets, this option run make clean/distclean and 'BUILD_CLEAN'"
	echo -e  "\t-i\t\t show target config info"
	echo -e  "\t-l\t\t listup targets"
	echo -e  "\t-j [jops]\t set build jobs"
	echo -e  "\t-o [option]\t set build options"
	echo -e  "\t-e\t\t edit build config file"
	echo -e  "\t-v\t\t show build log"
	echo -e  "\t-V\t\t show build log and enable external shell tasks tracing (with 'set -x')"
	echo -e  "\t-p\t\t skip dependency"
	echo -ne "\t-s [stage]\t build stage :"
	for i in "${!__bsp_stage[@]}"; do
		echo -n " '${i}'";
	done
	echo -e  "\n\t\t\t stage order : prev > make > post > copy > late"
	echo -e  "\t-m\t\t build manual targets 'BUILD_MANUAL'"
	echo -e  "\t-A\t\t Full build including manual build"
	echo -e  "\t-h [option]\t prints all help, option support 'format'"
	echo ""
}

function err () { echo -e "\033[0;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

__in_bsp_config=""	# build script file
__in_bsp_target=()

__in_config_dir="${__bsp_script_dir}/configs"
__in_target_command=""
__in_target_cleanall=false
__in_append_option=""
__in_jobs="$(grep -c processor /proc/cpuinfo)"

__in_show_info=false
__in_show_list=false
__in_edit=false
__in_verbose=false
__in_trace=false

__in_target_manual=false
__in_target_all=false	# include manual targets
__in_check_depend=true
__in_bsp_target_stage=""

declare -A __bsp_stage=(
	["prev"]=true		# execute script 'BUILD_PREV'
	["make"]=true		# make with 'MAKE_PATH' and 'MAKE_TARGET'
	["copy"]=true		# execute copy with 'BUILD_OUTPUT and BUILD_RESULT'
	["post"]=true		# execute script 'BUILD_POST'
	["late"]=true		# execute script 'BUILD_LAST'
)

function show_build_time () {
	local hrs=$(( SECONDS/3600 ));
	local min=$(( (SECONDS-hrs*3600)/60));
	local sec=$(( SECONDS-hrs*3600-min*60 ));
	printf "\n Total: %d:%02d:%02d\n" $hrs $min $sec
}

function show_progress () {
	local spin='-\|/' pos=0
	local delay=0.3 start=$SECONDS
	while true; do
		local hrs=$(( (SECONDS-start)/3600 ));
		local min=$(( (SECONDS-start-hrs*3600)/60));
		local sec=$(( (SECONDS-start)-hrs*3600-min*60 ))
		pos=$(( (pos + 1) % 4 ))
		printf "\r\t: Progress |${spin:$pos:1}| %d:%02d:%02d" $hrs $min $sec
		sleep ${delay}
	done
}

function run_progress () {
	kill_progress
	show_progress &
	echo -en " $!"
	__bsp_progress_pid=$!
}

function kill_progress () {
	local pid=${__bsp_progress_pid}
	if pidof ${pid}; then return; fi
	if [[ ${pid} -ne 0 ]] && [[ -e /proc/${pid} ]]; then
		kill "${pid}" 2> /dev/null
		wait "${pid}" 2> /dev/null
		echo ""
	fi
}

trap kill_progress EXIT

function print_env () {
	echo -e "\n\033[1;32m BUILD STATUS       = ${__bsp_config_info}\033[0m";
	echo -e "\033[1;32m BUILD CONFIG       = ${__in_bsp_config}\033[0m";
	echo ""
	for key in "${!__bsp_env__[@]}"; do
		[[ -z ${__bsp_env__[${key}]} ]] && continue;
		message=$(printf " %-18s = %s\n" "${key}" "${__bsp_env__[${key}]}")
		msg "${message}"
	done
}

function parse_env () {
	for key in "${!__bsp_env__[@]}"; do
		local val=""
		for i in "${__bsp_image[@]}"; do
			if [[ ${i} = *"${key}"* ]]; then
				local elem
				elem="$(echo "${i}" | cut -d'=' -f 2-)"
				elem="$(echo "$elem" | cut -d',' -f 1)"
				elem="$(echo -e "${elem}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
				val=$elem
				break
			fi
		done
		__bsp_env__[${key}]=${val}
	done

	if [[ -z ${__bsp_env__["RESULT_DIR"]} ]]; then
		__bsp_env__["RESULT_DIR"]="$(realpath "$(dirname "${0}")")/result"
	fi
	__bsp_log_dir="${__bsp_env__["RESULT_DIR"]}/${__bsp_log_dir}"
}

function setup_env () {
	local path=${1}
	[[ -z ${path} ]] && return;

	path=$(realpath "$(dirname "${1}")")
	if [[ -z ${path} ]]; then
		err " No such 'CROSS_TOOL': $(dirname "${1}")"
		exit 1
	fi
	export PATH=${path}:$PATH
}

function print_target () {
	local target=${1}

	echo -e "\n\033[1;32m BUILD TARGET       = ${target}\033[0m";
	for key in "${!__bsp_target__[@]}"; do
		[[ -z "${__bsp_target__[${key}]}" ]] && continue;
		if [[ "${key}" == "MAKE_PATH" ]]; then
			message=$(printf " %-18s = %s\n" "${key}" "$(realpath "${__bsp_target__[${key}]}")")
		else
			message=$(printf " %-18s = %s\n" "${key}" "${__bsp_target__[${key}]}")
		fi
		msg "${message}"
	done
}

declare -A __bsp_depend=()
__bsp_depend_list=()

function parse_depend () {
	local target=${1}
	local contents found=false
	local key="BUILD_DEPEND"

	# get target's contents
	for i in "${__bsp_image[@]}"; do
		if [[ ${i} == *"${target}"* ]]; then
			local elem
			elem="$(echo $(echo "${i}" | cut -d'=' -f 1) | cut -d' ' -f 1)"
			[[ ${target} != "$elem" ]] && continue;

			# cut
			elem="${i#*$elem*=}"
			# remove line-feed, first and last blank
			contents="$(echo "$elem" | tr '\n' ' ')"
			contents="$(echo "$contents" | sed 's/^[ \t]*//;s/[ \t]*$//')"
			found=true
			break
		fi
	done

	if [[ ${found} == false ]]; then
		err "\n Unknown target '${target}'"
		exit 1;
	fi

	# parse contents's elements
	local val=""
	__bsp_depend[${key}]=${val}
	if ! echo "$contents" | grep -qwn "${key}"; then return; fi

	val="${contents#*${key}}"
	val="$(echo "${val}" | cut -d":" -f 2-)"
	val="$(echo "${val}" | cut -d"," -f 1)"
	# remove first,last space and set multiple space to single space
	val="$(echo "${val}" | sed 's/^[ \t]*//;s/[ \t]*$//')"
	val="$(echo "${val}" | sed 's/\s\s*/ /g')"

	__bsp_depend[${key}]="${val}"
}

function parse_target () {
	local target=${1}
	local contents found=false

	# get target's contents
	for i in "${__bsp_image[@]}"; do
		if [[ ${i} == *"${target}"* ]]; then
			local elem
			elem="$(echo $(echo "${i}" | cut -d'=' -f 1) | cut -d' ' -f 1)"
			[[ ${target} != "$elem" ]] && continue;

			# cut
			elem="${i#*$elem*=}"
			# remove line-feed, first and last blank
			contents="$(echo "$elem" | tr '\n' ' ')"
			contents="$(echo "$contents" | sed 's/^[ \t]*//;s/[ \t]*$//')"
			found=true
			break
		fi
	done

	if [[ ${found} == false ]]; then
		err "\n Unknown target '${target}'"
		exit 1;
	fi

	# initialize
	for key in "${!__bsp_target__[@]}"; do __bsp_target__[${key}]=""; done

	# parse contents's elements
	for key in "${!__bsp_target__[@]}"; do
		local val=""
		if ! echo "$contents" | grep -qwn "${key}"; then
			__bsp_target__[${key}]=${val}
			[[ ${key} == "BUILD_MANUAL" ]] && __bsp_target__[${key}]=false;
			continue;
		fi

		val="${contents#*${key}}"
		val="$(echo "${val}" | cut -d":" -f 2-)"
		val="$(echo "${val}" | cut -d"," -f 1)"
		# remove first,last space and set multiple space to single space
		val="$(echo "${val}" | sed 's/^[ \t]*//;s/[ \t]*$//')"
		val="$(echo "${val}" | sed 's/\s\s*/ /g')"

		__bsp_target__[${key}]="${val}"
	done

	[[ -n ${__bsp_target__["MAKE_PATH"]} ]] && __bsp_target__["MAKE_PATH"]=$(realpath "${__bsp_target__["MAKE_PATH"]}");
	[[ -z ${__bsp_target__["MAKE_TARGET"]} ]] && __bsp_target__["MAKE_TARGET"]="all";
	[[ -z ${__bsp_target__["CROSS_TOOL"]} ]] && __bsp_target__["CROSS_TOOL"]=${__bsp_env__["CROSS_TOOL"]};
	[[ -z ${__bsp_target__["MAKE_JOBS"]} ]] && __bsp_target__["MAKE_JOBS"]=$__in_jobs;
}

function check_depend () {
        local target=${1}

	parse_depend "${target}"

	if [[ -z ${__bsp_depend["BUILD_DEPEND"]} ]]; then
		unset __bsp_depend_list[${#__bsp_depend_list[@]}-1]
		return
	fi

        for d in ${__bsp_depend["BUILD_DEPEND"]}; do
		if [[ " ${__bsp_depend_list[@]} " =~ "${d}" ]]; then
			echo -e "\033[1;31m Error recursive, Check 'BUILD_DEPEND':\033[0m"
			echo -e "\033[1;31m\t${__bsp_depend_list[@]} $d\033[0m"
			exit 1;
		fi
		__bsp_depend_list+=("$d")
		check_depend "$d"
        done
	unset __bsp_depend_list[${#__bsp_depend_list[@]}-1]
}

function parse_target_list () {
	local target_list=()
	local list_manuals=() list_targets=()
	local dump_manuals=() dump_targets=()

	for str in "${__bsp_image[@]}"; do
		local val add=true
		str="$(echo "${str}" | tr '\n' ' ')"
		val="$(echo "${str}" | cut -d'=' -f 1)"
		val="$(echo -e "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

		# skip buil environments"
		for n in "${!__bsp_env__[@]}"; do
			if [[ ${n} == "${val}" ]]; then
				add=false
				break
			fi
		done

		[[ ${add} != true ]] && continue;
		[[ ${str} == *"="* ]] && target_list+=("${val}");
	done

	for i in "${__in_bsp_target[@]}"; do
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
		parse_target "${t}"
		depend=${__bsp_target__["BUILD_DEPEND"]}
		[[ -n ${depend} ]] && depend="depend: ${depend}";
		if [[ ${__bsp_target__["BUILD_MANUAL"]} == true ]]; then
			list_manuals+=("${t}")
			dump_manuals+=("$(printf "%-18s %s\n" "${t}" "${depend} ")")
		else
			list_targets+=("${t}")
			dump_targets+=("$(printf "%-18s %s\n" "${t}" "${depend} ")")
		fi
	done

	if [[ ${#__in_bsp_target[@]} -eq 0 ]]; then
		__in_bsp_target=("${list_targets[@]}")
		[[ $__in_target_manual == true ]] && __in_bsp_target=("${list_manuals[@]}");
		[[ $__in_target_all == true ]] && __in_bsp_target=("${list_manuals[@]}" "${list_targets[@]}");
	fi

	# check dependency
	if [[ ${__in_check_depend} == true ]]; then
		for i in "${__in_bsp_target[@]}"; do
			__bsp_depend_list+=("${i}")
			check_depend "${i}"
		done
	fi

	if [[ ${__in_show_list} == true ]]; then
		echo -e "\033[1;32m BUILD CONFIG  = ${__in_bsp_config}\033[0m";
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

function exec_shell () {
	local command=${1} target=${2}
	local log="${__bsp_log_dir}/${target}.script.log"
	local ret

	[[ ${__in_trace} == true ]] && set -x;

	IFS=";"
	for cmd in ${command}; do
		cmd="$(echo "${cmd}" | sed 's/\s\s*/ /g')"
		cmd="$(echo "${cmd}" | sed 's/^[ \t]*//;s/[ \t]*$//')"
		cmd="$(echo "${cmd}" | sed 's/\s\s*/ /g')"
		fnc=$($(echo ${cmd}| cut -d' ' -f1) 2>/dev/null | grep -q 'function')
		unset IFS

		msg "\n LOG : ${log}"
		msg "\n $> ${cmd}"
		rm -f "$log"
		[[ ${__in_verbose} == false ]] && run_progress;

		if $fnc; then
			if [[ ${__in_verbose} == false ]]; then
				${cmd} >> "$log" 2>&1
			else
				${cmd}
			fi
		else
			if [[ ${__in_verbose} == false ]]; then
				bash -c "${cmd}" >> "$log" 2>&1
			else
				bash -c "${cmd}"
			fi
		fi
		### get return value ###
		ret=$?

		kill_progress
		[[ ${__in_trace} == true ]] && set +x;
		if [[ ${ret} -ne 0 ]]; then
			if [[ ${__in_verbose} == false ]]; then
				err " ERROR: script '${target}':$log\n";
			else
				err " ERROR: script '${target}'\n";
			fi
			break;
		fi
	done

	return ${ret}
}

function exec_make () {
	local command=${1} target=${2}
	local log="${__bsp_log_dir}/${target}.make.log"
	local ret

	command="$(echo "${command}" | sed 's/\s\s*/ /g')"
	msg "\n LOG : ${log}"
	msg "\n $> make ${command}"
	rm -f "$log"

	if [[ ${__in_verbose} == false ]] && [[ ${command} != *menuconfig* ]]; then
		run_progress
		make ${command} >> "$log" 2>&1
	else
		make ${command}
	fi
	### get return value ###
	ret=$?

	kill_progress
	if [[ ${ret} -eq 2 ]] && [[ ${command} != *"clean"* ]]; then
		if [[ ${__in_verbose} == false ]]; then
			err " ERROR: make '${target}':$log\n";
		else
			err " ERROR: make '${target}'\n";
		fi
	else
		ret=0
	fi

	return ${ret}
}

function run_cmd_prev () {
	local target=${1}

	if [[ -z ${__bsp_target__["BUILD_PREV"]} ]] ||
	   [[ ${__in_target_cleanall} == true ]] ||
	   [[ ${__bsp_stage["prev"]} == false ]]; then
		return;
	fi

	if ! exec_shell "${__bsp_target__["BUILD_PREV"]}" "${target}"; then
		exit 1;
	fi
}

function run_cmd_post () {
	local target=${1}

	if [[ -z ${__bsp_target__["BUILD_POST"]} ]] ||
	   [[ ${__in_target_cleanall} == true ]] ||
	   [[ ${__bsp_stage["post"]} == false ]]; then
		return;
	fi

	if ! exec_shell "${__bsp_target__["BUILD_POST"]}" "${target}"; then
		exit 1;
	fi
}

function run_cmd_late () {
	local target=${1}

	if [[ -z ${__bsp_target__["BUILD_LAST"]} ]] ||
	   [[ ${__in_target_cleanall} == true ]] ||
	   [[ ${__bsp_stage["late"]} == false ]]; then
		return;
	fi

	if ! exec_shell "${__bsp_target__["BUILD_LAST"]}" "${target}"; then
		exit 1;
	fi
}

function run_cmd_clean () {
	local target=${1} command=${__in_target_command}

	[[ -z ${__bsp_target__["BUILD_CLEAN"]} ]] && return;
	[[ ${command} != *"clean"* ]] && return;

	if ! exec_shell "${__bsp_target__["BUILD_CLEAN"]}" "${target}"; then
		exit 1;
	fi
}

function run_make () {
	local target=${1}
	local command=${__in_target_command}
	local path=${__bsp_target__["MAKE_PATH"]}
	local config=${__bsp_target__["MAKE_CONFIG"]}
	local build_option="${__bsp_target__["MAKE_OPTION"]} -j${__bsp_target__["MAKE_JOBS"]} "
	local stage_file="${path}/.${target}_defconfig"
	local stage="BUILD:${config}:${__bsp_target__["MAKE_OPTION"]}"
	local arch_option
	declare -A mode=(
		["distclean"]=false
		["clean"]=false
		["defconfig"]=false
		["menuconfig"]=false
		)

	if [[ -z ${path} ]] || [[ ! -d ${path} ]]; then
		[[ -z ${path} ]] && return;
		err " Not found 'MAKE_PATH': '${__bsp_target__["MAKE_PATH"]}'"
		exit 1;
	fi

	if [[ ${__bsp_stage["make"]} == false ]] ||
	   [[ ! -f ${path}/makefile && ! -f ${path}/Makefile ]]; then
		return
	fi

	if [[ ${__bsp_target__["MAKE_ARCH"]} ]]; then
		arch_option="ARCH=${__bsp_target__["MAKE_ARCH"]} "
	fi

	if [[ ${__bsp_target__["CROSS_TOOL"]} ]]; then
		arch_option+="CROSS_COMPILE=${__bsp_target__["CROSS_TOOL"]} "
	fi

	[[ -n $__in_append_option ]] && build_option+="$__in_append_option";

	if [[ ${command} == clean ]] || [[ ${command} == cleanbuild ]] ||
	   [[ ${command} == rebuild ]]; then
		mode["clean"]=true
	fi

	if [[ ${command} == cleanall ]] ||
	   [[ ${command} == distclean ]] || [[ ${command} == rebuild ]]; then
		mode["clean"]=true;
		mode["distclean"]=true;
		[[ -n ${config} ]] && mode["defconfig"]=true;
	fi

	if [[ ${command} == defconfig || ! -f ${path}/.config ]] && [[ -n ${config} ]]; then
		mode["defconfig"]=true
		mode["clean"]=true;
		mode["distclean"]=true;
	fi

	if [[ ${command} == menuconfig ]] && [[ -n ${config} ]]; then
		mode["menuconfig"]=true
	fi

	if [[ ! -e $stage_file ]] || [[ $(cat "$stage_file") != "$stage" ]]; then
		mode["clean"]=true;
		mode["distclean"]=true
		[[ -n ${config} ]] && mode["defconfig"]=true;
		rm -f "$stage_file";
		echo "$stage" >> "$stage_file";
		sync;
	fi

	# make clean
	if [[ ${mode["clean"]} == true ]]; then
		if [[ ${__bsp_target__["MAKE_NOCLEAN"]} != true ]]; then
			exec_make "-C ${path} clean" "${target}"
		fi
		if [[ ${command} == clean ]]; then
			run_cmd_clean "${target}"
			exit 0;
		fi
	fi

	# make distclean
	if [[ ${mode["distclean"]} == true ]]; then
		if [[ ${__bsp_target__["MAKE_NOCLEAN"]} != true ]]; then
			exec_make "-C ${path} distclean" "${target}"
		fi
		[[ ${command} == distclean ]] || [[ ${__in_target_cleanall} == true ]] && rm -f "$stage_file";
		[[ ${__in_target_cleanall} == true ]] && return;
		if [[ ${command} == distclean ]]; then
			run_cmd_clean "${target}"
			exit 0;
		fi
	fi

	# make defconfig
	if [[ ${mode["defconfig"]} == true ]]; then
		if ! exec_make "-C ${path} $arch_option ${config}" "${target}"; then
			exit 1;
		fi
		[[ ${command} == defconfig ]] && exit 0;
	fi

	# make menuconfig
	if [[ ${mode["menuconfig"]} == true ]]; then
		exec_make "-C ${path} $arch_option menuconfig" "${target}";
		exit 0;
	fi

	# make targets
	if [[ -z ${command} ]] ||
	   [[ ${command} == rebuild ]] || [[ ${command} == cleanbuild ]]; then
		for i in ${__bsp_target__["MAKE_TARGET"]}; do
			i="$(echo "${i}" | sed 's/[;,]//g') "
			if ! exec_make "-C ${path} $arch_option ${i} $build_option" "${target}"; then
				exit 1
			fi
		done
	else
		if ! exec_make "-C ${path} $arch_option ${command} $build_option" "${target}"; then
			exit 1
		fi
	fi
}

function run_result () {
	local path=${__bsp_target__["MAKE_PATH"]}
	local file=${__bsp_target__["BUILD_OUTPUT"]}
	local dir=${__bsp_env__["RESULT_DIR"]}
	local ret=${__bsp_target__["BUILD_RESULT"]}

	if [[ -z ${file} ]] || [[ ${__in_target_cleanall} == true ]] ||
	   [[ ${__bsp_stage["copy"]} == false ]]; then
		return;
	fi

	if ! mkdir -p "$dir"; then exit 1; fi

	ret=$(echo "${ret}" | sed 's/[;,]//g')
	for src in ${file}; do
		src=$(realpath "${path}/${src}")
		src=$(echo "${src}" | sed 's/[;,]//g')
		dst=$(realpath "$dir/$(echo "${ret}" | cut -d' ' -f1)")
		ret=$(echo ${ret} | cut -d' ' -f2-)
		if [[ ${src} != *'*'* ]] && [[ -d ${src} ]] && [[ -d ${dst} ]]; then
			rm -rf "${dst}";
		fi

		msg "\n $> cp -a ${src} ${dst}"
		[[ ${__in_verbose} == false ]] && run_progress;
		cp -a ${src} ${dst}
		kill_progress
	done
}

function build_depend () {
	local target=${1}

	for d in ${__bsp_target__["BUILD_DEPEND"]}; do
		[[ -z ${d} ]] && continue;
		# echo -e "\n\033[1;32m BUILD DEPEND       = ${target} ---> $d\033[0m";
		build_target "${d}";
		parse_target "${target}"
	done
}

function build_target () {
	local target=${1}

	parse_target "${target}"

	# build dependency
	if [[ ${__in_check_depend} == true ]]; then
		build_depend "${target}"
		if echo "${__in_bsp_target_stage}" | grep -qwn "${target}"; then return; fi
		__in_bsp_target_stage+="${target} "
	fi

	print_target "${target}"
	[[ ${__in_show_info} == true ]] && return;
	if ! mkdir -p "${__bsp_env__["RESULT_DIR"]}"; then exit 1; fi
	if ! mkdir -p "${__bsp_log_dir}"; then exit 1; fi

	setup_env "${__bsp_target__["CROSS_TOOL"]}"
	run_cmd_prev "${target}"
	run_make "${target}"
	run_cmd_post "${target}"
	run_result "${target}"
	run_cmd_late "${target}"
	run_cmd_clean "${target}"
}

function build_run () {
	parse_target_list
	print_env

	for i in "${__in_bsp_target[@]}"; do
		build_target "${i}"
	done

	[[ ${__in_target_cleanall} == true ]] &&
	[[ -d ${__bsp_log_dir} ]] && rm -rf "${__bsp_log_dir}";

	show_build_time
}

function setup_config () {
	local config=${1}

	if [[ ! -f ${config} ]]; then
		err " Not selected build scripts in ${config}"
		exit 1;
	fi

	# include build script file
	source "${config}"
	if [[ -z ${BUILD_IMAGES} ]]; then
		err " Not defined 'BUILD_IMAGES'\n"
		show_format
		exit 1
	fi

	__bsp_image=("${BUILD_IMAGES[@]}");
}

function store_config () {
	local path=${1} script=${2}

	if [[ ! -f $(realpath "${__bsp_config_info}") ]]; then
cat > "${__bsp_config_info}" <<EOF
PATH   = $(realpath "${__in_config_dir}")
CONFIG =
EOF
	fi

	if [[ -n ${path} ]]; then
		if [[ ! -d $(realpath "${path}") ]]; then
			err " No such directory: ${path}"
			exit 1;
		fi
		sed -i "s|^PATH.*|PATH = ${path}|" "${__bsp_config_info}"
                __in_config_dir=${path}
	fi

	if [[ -n ${script} ]]; then
		if [[ ! -f $(realpath "${__in_config_dir}/${script}") ]]; then
			err " No such script: ${path}"
			exit 1;
		fi
		sed -i "s/^CONFIG.*/CONFIG = ${script}/" "${__bsp_config_info}"
	fi
}

function parse_config () {
	local file=${__bsp_config_info}
	local str ret

	[[ ! -f ${file} ]] && return;

	str=$(sed -n '/^\<PATH\>/p' "${file}");
	ret=$(echo "${str}" | cut -d'=' -f 2)
	ret=$(echo "${ret}" | sed 's/[[:space:]]//g')
	__in_config_dir="${ret# *}"

	str=$(sed -n '/^\<CONFIG\>/p' "${file}");
	ret=$(echo "${str}" | cut -d'=' -f 2)
	ret=$(echo "${ret}" | sed 's/[[:space:]]//g')
	__in_bsp_config="$(realpath "${__in_config_dir}/"${ret# *}"")"
}

function avail_configs () {
	local table=${1}	# parse table
	local prefix=${__bsp_config_prefix}
	local extend=${__bsp_config_extend}
        local path=${__in_config_dir}
	local val value

	value=$(find ${path} -print \
		2> >(grep -v 'No such file or directory' >&2) | \
		grep -F "${prefix}" | sort)
	for i in ${value}; do
                i="$(echo "$(basename ${i})" | cut -d'/' -f2)"
		[[ -n $(echo "${i}" | awk -F".${prefix}" '{print $2}') ]] && continue;
		[[ ${i} == *common* ]] && continue;
		[[ "${i##*.}" != ${extend} ]] && continue;
		val="${val} $(echo "${i}" | awk -F".${prefix}" '{print $1}')"
		eval "${table}=(\"${val}\")"
	done
}

function menu_config () {
	local table=${1} string=${2}
	local result=${3} # return value
	local select
	local -a entry

	for i in ${table}; do
		stat="OFF"
		entry+=( "${i}" )
		entry+=( " " )
		[[ ${i} == "$(basename "${!result}")" ]] && stat="ON";
		entry+=( "${stat}" )
	done

	if ! which whiptail > /dev/null 2>&1; then
		err " Please install the whiptail"
		exit 1
	fi

	select=$(whiptail --title "Target ${string}" \
		--radiolist "Choose a ${string}" 0 50 ${#entry[@]} -- "${entry[@]}" \
		3>&1 1>&2 2>&3)
	[[ -z ${select} ]] && exit 1;

	eval "${result}=(\"${select}\")"
}

function menu_save () {
	if ! (whiptail --title "Save/Exit" --yesno "Save" 8 78); then
		exit 1;
	fi
	store_config "" "${__in_bsp_config}"
}

function set_build_stage () {
	for i in "${!__bsp_stage[@]}"; do
		if [[ ${i} == "${1}" ]]; then
			for n in "${!__bsp_stage[@]}"; do
				__bsp_stage[${n}]=false
			done
			__bsp_stage[${i}]=true
			return
		fi
	done

	echo -ne "\n\033[1;31m Not Support Stage Command: ${i} ( \033[0m"
	for i in "${!__bsp_stage[@]}"; do
		echo -n "${i} "
	done
	echo -e "\033[1;31m)\033[0m\n"
	exit 1;
}

function parse_args () {
	while getopts "f:t:c:Cj:o:s:D:S:mAilevVph" opt; do
	case ${opt} in
		f )	__in_bsp_config=$(realpath "${OPTARG}");;
		t )	__in_bsp_target=("${OPTARG}")
			until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
				__in_bsp_target+=("$(eval "echo \${$OPTIND}")")
				OPTIND=$((OPTIND + 1))
			done
			;;
		c )	__in_target_command="${OPTARG}";;
		m )	__in_target_manual=true;;
		A )	__in_target_all=true;;
		C )	__in_target_cleanall=true; __in_target_command="distclean";;
		j )	__in_jobs=${OPTARG};;
		v )	__in_verbose=true;;
		V )	__in_verbose=true; __in_trace=true;;
		p )	__in_check_depend=false;;
		o )	__in_append_option="${OPTARG}";;
		D )	__in_config_dir=$(realpath "${OPTARG}")
			store_config "${__in_config_dir}" ""
			exit 0;;
		S)      __in_config_dir=$(dirname "$(realpath "${OPTARG}")")
                        __in_bsp_config=$(basename "$(realpath "${OPTARG}")")
                        store_config "${__in_config_dir}" "${__in_bsp_config}"
			exit 0;;
		i ) 	__in_show_info=true;;
		l )	__in_show_list=true;;
		e )	__in_edit=true;
			break;;
		s ) 	set_build_stage "${OPTARG}";;
		h )	usage "${@: 2}";
			exit 1;;
	        * )	exit 1;;
	esac
	done
}

###############################################################################
# Run build
###############################################################################
if [[ ${1} == "menuconfig" ]]; then
	parse_args "${@: 2}"
else
	parse_args "${@}"
fi

if [[ -z ${__in_bsp_config} ]]; then
        avail_list=()
	parse_config
	avail_configs avail_list
	if [[ $* == *"menuconfig"* && ${__in_target_command} != "menuconfig" ]]; then
		menu_config "${avail_list}" "config" __in_bsp_config
		menu_save
		msg "$(sed -e 's/^/ /' < "${__bsp_config_info}")"
		exit 0;
	fi
	if [[ -z ${__in_bsp_config} ]]; then
		err " Not selected build script in ${__in_config_dir}"
		err " Set build script with -f <script> or menuconfig option"
		exit 1;
	fi
fi

setup_config "${__in_bsp_config}"

if [[ "${__in_edit}" == true ]]; then
	$EDIT_TOOL "${__in_bsp_config}"
	exit 0;
fi

parse_env
build_run
