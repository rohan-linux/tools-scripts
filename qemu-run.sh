#!/bin/bash
# (c) 2024, rohan
# QEMU Shell Script

eval "$(locale | sed -e 's/\(.*\)=.*/export \1=en_US.UTF-8/')"

QEMU_MACHINE_PATH="$(pwd)/tools/project"
QEMU_MACHINE_CONFIG="$(pwd)/.qemu_machine"
QEMU_MACHINE_EXTN='qemu' # machine file extention '*.bs'
QEMU_MACHINE=""
QEMU_MACHINE_SELECT=""
QEMU_EDITOR='vim' # editor with '-e' option

###############################################################################
QEMU_DEVICETREE="devicetree"

# options
_qemu_machines=()
_qemu_target=""
_qemu_option=""
_qemu_dumpdtb=false

function logerr() { echo -e "\033[1;31m$*\033[0m"; }
function logmsg() { echo -e "\033[0;33m$*\033[0m"; }
function logext() {
	echo -e "\033[1;31m$*\033[0m"
	exit 1
}

function qemu_exec_sh() {
	local exec=${1}

	# remove first,last space and set multiple space to single space
	exec="$(echo "${exec}" | sed 's/^[ \t]*//;s/[ \t]*$//;s/\s\s*/ /g')"

	logmsg " $ ${exec}"
	bash -c "${exec}"

	return ${?}
}

function qemu_dtb2dts() {
	local dtb=${1} dts=${2}
	if [[ ! -f ${dtb} ]]; then
		logext "Not found dtb: ${dtb}, first run '-dumpdtb'"
	fi
	qemu_exec_sh "dtc -I dtb -O dts -o ${dts} ${dtb}"
}

function qemu_check_exec() {
	declare -n args=${1}
	local exec=${args['exec']} version

	version=$(${exec} --version | grep version | awk '{print $NF}')
	if [[ -z ${version} ]]; then
		logext " Not found qemu execute file: ${exec} !!!"
	fi
	logmsg " QEMU VERSION : ${version}"
}

function qemu_stop_target() {
	local name=${1}

	if [[ -z "${QEMU_MACHINE_TARGETS[*]}" ]]; then
		logext " Not defined 'QEMU_MACHINE_TARGETS' in ${QEMU_MACHINE} !!!"
	fi

	logmsg " MACHINE      : ${QEMU_MACHINE} [${QEMU_MACHINE_SELECT}]"

	for t in "${QEMU_MACHINE_TARGETS[@]}"; do
		declare -n target=${t}
		if [[ -n ${name} && ${name} != "${target['name']}" ]]; then
			continue
		fi

		qemu_check_exec target

		local exec=${target['exec']} pid

		pid=$(pidof "${exec}")
		if [[ ${pid} ]]; then
			user=$(ps -o user= -p "${pid}")
			echo "Kill ${exec} pid [${user}:${pid}]"
			[[ ${user} == root ]] && _sudo_=sudo
			bash -c "${_sudo_} kill ${pid}"
			if [[ ${QEMU_COMMAND_ARCH["graphic"]} != "-nographic" ]]; then
				pid=$(pidof vinagre)
				if [[ ${pid} ]]; then
					user=$(ps -o user= -p "${pid}")
					[[ $user == root ]] && _sudo_=sudo
					echo "Kill vinagre pid [${user}:${pid}]"
					bash -c "${_sudo_} kill ${pid}"
				fi
			fi
		else
			echo " No running process ${exec} for '${name}'"
		fi
	done
}

function qemu_list_target() {
	if [[ -z "${QEMU_MACHINE_TARGETS[*]}" ]]; then
		logext " Not defined 'QEMU_MACHINE_TARGETS' in ${QEMU_MACHINE} !!!"
	fi

	logmsg " MACHINE      : ${QEMU_MACHINE} [${QEMU_MACHINE_SELECT}]"
	for t in "${QEMU_MACHINE_TARGETS[@]}"; do
		qemu_check_exec "${t}"
		declare -n target=${t}
		printf "\033[0;33m %-12s : %-6s\033[0m\n" "* ${target['name']}" "${target['exec']}"
	done
}

function qemu_list_machine() {
	local path=${QEMU_MACHINE_PATH}
	local array

	# get machine lists
	array=$(find "${path}" -type f -name "*.${QEMU_MACHINE_EXTN}")
	for i in ${array}; do
		name=$(basename "${i}")
		name=${name%.*}
		_qemu_machines+=("${name}")
	done
}

function qemu_save_machine() {
	local machine=${1}

	QEMU_MACHINE_SELECT="${QEMU_MACHINE_PATH}/${machine}.${QEMU_MACHINE_EXTN}"
	if [[ -z ${machine} || ! -f ${QEMU_MACHINE_SELECT} ]]; then
		logerr " Invalid MACHINE: ${machine}, not exist ${QEMU_MACHINE_SELECT}"
		return 1
	fi

	logmsg " UPDATE       : ${machine} [${QEMU_MACHINE_SELECT}] [${QEMU_MACHINE_CONFIG}]"

	# save machine
	cat >"${QEMU_MACHINE_CONFIG}" <<EOF
MACHINE_PATH = ${QEMU_MACHINE_PATH}
MACHINE_SELECT = ${machine}
EOF
	return 0
}

function qemu_load_machine() {
	local val

	if [[ ! -f ${QEMU_MACHINE_CONFIG} ]]; then
		return 1
	fi

	val=$(sed -n '/^\<MACHINE_SELECT\>/p' "${QEMU_MACHINE_CONFIG}")
	val=$(echo "${val}" | cut -d'=' -f 2)
	QEMU_MACHINE="${val//[[:space:]]/}"
	QEMU_MACHINE_SELECT="${QEMU_MACHINE_PATH}/${QEMU_MACHINE}.${QEMU_MACHINE_EXTN}"

	if [[ ! -f "${QEMU_MACHINE_SELECT}" ]]; then
		logerr " Not found MACHINE: ${QEMU_MACHINE_SELECT}"
		return 1
	fi

	return 0
}
function qemu_edit_machine() {
	${QEMU_EDITOR} "${QEMU_MACHINE_SELECT}"
}

function qemu_usage_format() {
	echo -e " FORMAT: Target elements\n"
	echo -e " declare -A <TARGET>=("
	echo -e "\t['name']=<name>           - qemu target name, required"
	echo -e "\t['exec']=<execute>        - qemu execute file (qemu-system-xxx), required"
	echo -e ""
	echo -e "\t['config']=<config>       - qemu run config"
	echo -e " )"
	echo -e ""
	echo -e " QEMU_MACHINE_TARGETS=( <TARGET> ... )"
	echo -e "\t'QEMU_MACHINE_TARGETS' is reserved"
	echo -e ""
}

function qemu_usage() {
	case ${1} in
	'fmt')
		qemu_usage_format
		exit 0
		;;
	*) ;;
	esac

	echo " Usage:"
	echo -e "\t$(basename "${0}") <option>"
	echo ""
	echo " option:"
	echo -e "\t-l\t\t listup qemu machine at '${QEMU_MACHINE_PATH}'"
	echo -e "\t-m [machine]\t select machine."
	echo -e "\t-t [target...]\t select machine's targets."
	echo -e "\t-o [option]\t add option to run qemu."
	echo -e "\t-k\t\t kill target with -t 'target'"
	echo -e "\t-d\t\t dump devicetree : ${QEMU_DEVICETREE}.dtb and dts"
	echo -e "\t\t\t  dtb -> dts: \$ dtc -I dtb -O dts -o 'source' 'binary'"
	echo -e "\t\t\t  dts -> dtb: \$ dtc -I dts -O dtb -o 'binary' 'source'"
	echo -e "\t-s\t\t show '${QEMU_MACHINE}' targets"
	echo -e "\t-e\t\t edit machine '${QEMU_MACHINE}'"
	echo -e "\t-h\t\t show help [fmt]"
	echo ""
}

function qemu_parse_args() {
	local listup=false show=false edit=false
	local machine='' stop=false

	qemu_load_machine

	while getopts "m:t:o:lkdseh" opt; do
		case ${opt} in
		m) machine="${OPTARG}" ;;
		l) listup=true ;;
		t) _qemu_target="${OPTARG}" ;;
		s) show=true ;;
		o) _qemu_option="${OPTARG}" ;;
		k) stop=true ;;
		d) _qemu_dumpdtb=true ;;
		e) edit=true ;;
		h)
			qemu_usage "$(eval "echo \${$OPTIND}")"
			exit 0
			;;
		*) exit 1 ;;
		esac
	done

	if [[ ${listup} == true ]]; then
		qemu_list_machine
		[[ -z ${_qemu_machines[*]} ]] && logext " Not Found MACHINES : ${QEMU_MACHINE_PATH}"

		logmsg " MACHINE      : ${QEMU_MACHINE} [${QEMU_MACHINE_SELECT}]"
		for i in "${_qemu_machines[@]}"; do logmsg "            - ${i}"; done
		exit 0
	fi

	if [[ -n ${machine} ]]; then
		! qemu_save_machine "${machine}" && exit 1
		! qemu_load_machine && exit 1
	fi

	if [[ ${show} == true ]]; then
		# shellcheck disable=SC1090
		source "${QEMU_MACHINE_SELECT}"
		qemu_list_target
		exit 0
	fi

	if [[ ${edit} == true ]]; then
		qemu_edit_machine
		exit 0
	fi

	if [[ ${stop} == true ]]; then
		# shellcheck disable=SC1090
		source "${QEMU_MACHINE_SELECT}"
		qemu_stop_target "${_qemu_target}"
		exit 0
	fi
}

function qemu_check_target() {
	local name="${1}"
	local found=false
	local -a list

	if [[ -z "${QEMU_MACHINE_TARGETS[*]}" ]]; then
		logext " Not defined 'QEMU_MACHINE_TARGETS' in ${QEMU_MACHINE} !!!"
	fi

	for i in "${QEMU_MACHINE_TARGETS[@]}"; do
		declare -n target=${i}
		list+=("'${target['name']}'")
		if [[ ${target['name']} == "${name}" ]]; then
			found=true
			break
		fi
	done

	if [[ ${found} == false ]]; then
		if [[ -z ${_qemu_target} && ${#list[*]} == 1 ]]; then
			_qemu_target=${list[0]}
		else
			logext " Error, unknown target : ${name} [ ${list[*]} ]"
		fi
	fi
}

function qemu_run_target() {
	local name="${1}"

	qemu_check_target "${name}"

	for t in "${QEMU_MACHINE_TARGETS[@]}"; do
		declare -n target=${t}
		if [[ -n ${name} && ${target['name']} != "${name}" ]]; then
			continue
		fi

		logmsg " TARGET       : ${_qemu_target}"
		local exec=("${target['exec']}" "${target['config']}" "${_qemu_option}")
		if [[ ${_qemu_dumpdtb} == true ]]; then
			local string="${exec[*]}"
			local search="-machine"
			local mach="$(echo "${string##*$search}" | cut -d ' ' -f1)"

			logmsg " DUMP DTB     : ${QEMU_DEVICETREE}.dtb"
			exec+=("-machine ${mach},dumpdtb=${QEMU_DEVICETREE}.dtb")
		fi

		declare -A config=()
		local re='^-'
		for s in ${exec[*]}; do
			if [[ ${s} =~ ${re} ]]; then
				key=${s} config[${key}]=''
			else
				[[ -z ${key} ]] && continue
				if [[ ${config[${key}]} ]]; then
					config[${key}]="${config[${key}]} ${s}"
				else
					config[${key}]="${s}"
				fi
			fi
		done

		for s in "${!config[@]}"; do
			logmsg "    ${s} ${config[${s}]}"
		done
		logmsg ""

		qemu_exec_sh "${exec[*]}"
		break
	done

	if [[ ${_qemu_dumpdtb} == true ]]; then
		logmsg " DTB to DTS   : ${QEMU_DEVICETREE}.dts"
		qemu_dtb2dts "${QEMU_DEVICETREE}.dtb" "${QEMU_DEVICETREE}.dts"
	fi
}

###############################################################################
# Start QEMU !!!
###############################################################################

qemu_parse_args "${@}"

if [[ -z ${QEMU_MACHINE} ]]; then
	logext " Not Selected QEMU MACHINE, PATH: ${QEMU_MACHINE_PATH}"
fi

logmsg " MACHINE      : ${QEMU_MACHINE} [${QEMU_MACHINE_SELECT}]"
# shellcheck disable=SC1090
source "${QEMU_MACHINE_SELECT}"

qemu_run_target "${_qemu_target}"
