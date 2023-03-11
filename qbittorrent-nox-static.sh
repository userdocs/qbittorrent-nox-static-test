#!/usr/bin/env bash
#
# Copyright 2020 by userdocs and contributors
#
# SPDX-License-Identifier: Apache-2.0
#
# @author - userdocs
#
# @contributors IceCodeNew Stanislas boredazfcuk AdvenT. guillaumedsde inochisa
#
# @credits - https://gist.github.com/notsure2 https://github.com/c0re100/qBittorrent-Enhanced-Edition
#
# shellcheck disable=SC2034,SC1091
# Why are these checks excluded?
#
# https://github.com/koalaman/shellcheck/wiki/SC2034
# There are quite a few variables defined by combining other variables that mean nothing on their own.
# This behavior is intentional and the warning can be skipped.
#
# https://github.com/koalaman/shellcheck/wiki/SC1091
# I am sourcing /etc/os-release for some variables.
# It's not available to shellcheck to source and it's a safe file so we can skip this
#
# Script Formatting - https://marketplace.visualstudio.com/items?itemName=foxundermoon.shell-format
#
#################################################################################################################################################
# Script version = Major minor patch
#################################################################################################################################################
script_version="1.0.6"
#################################################################################################################################################
# Set some script features - https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
#################################################################################################################################################
set -a
#################################################################################################################################################
# Unset some variables to set defaults.
#################################################################################################################################################
unset qbt_skip_delete qbt_skip_icu qbt_git_proxy qbt_curl_proxy qbt_install_dir qbt_build_dir qbt_working_dir qbt_modules_test qbt_python_version
#################################################################################################################################################
# Color me up Scotty - define some color values to use as variables in the scripts.
#################################################################################################################################################
cr="\e[31m" clr="\e[91m" # [c]olor[r]ed     [c]olor[l]ight[r]ed
cg="\e[32m" clg="\e[92m" # [c]olor[g]reen   [c]olor[l]ight[g]reen
cy="\e[33m" cly="\e[93m" # [c]olor[y]ellow  [c]olor[l]ight[y]ellow
cb="\e[34m" clb="\e[94m" # [c]olor[b]lue    [c]olor[l]ight[b]lue
cm="\e[35m" clm="\e[95m" # [c]olor[m]agenta [c]olor[l]ight[m]agenta
cc="\e[36m" clc="\e[96m" # [c]olor[c]yan    [c]olor[l]ight[c]yan

tb="\e[1m" td="\e[2m" tu="\e[4m" tn="\n" tbk="\e[5m" # [t]ext[b]old [t]ext[d]im [t]ext[u]nderlined [t]ext[n]ewline [t]ext[b]lin[k]

utick="\e[32m\U2714\e[0m" uplus="\e[36m\U002b\e[0m" ucross="\e[31m\U00D7\e[0m" # [u]nicode][tick] [u]nicode][plus] [u]nicode][cross]

urc="\e[31m\U25cf\e[0m" ulrc="\e[91m\U25cf\e[0m"    # [u]nicode[r]ed[c]ircle     [u]nicode[l]ight[r]ed[c]ircle
ugc="\e[32m\U25cf\e[0m" ulgc="\e[92m\U25cf\e[0m"    # [u]nicode[g]reen[c]ircle   [u]nicode[l]ight[g]reen[c]ircle
uyc="\e[33m\U25cf\e[0m" ulyc="\e[93m\U25cf\e[0m"    # [u]nicode[y]ellow[c]ircle  [u]nicode[l]ight[y]ellow[c]ircle
ubc="\e[34m\U25cf\e[0m" ulbc="\e[94m\U25cf\e[0m"    # [u]nicode[b]lue[c]ircle    [u]nicode[l]ight[b]lue[c]ircle
umc="\e[35m\U25cf\e[0m" ulmc="\e[95m\U25cf\e[0m"    # [u]nicode[m]agenta[c]ircle [u]nicode[l]ight[m]agenta[c]ircle
ucc="\e[36m\U25cf\e[0m" ulcc="\e[96m\U25cf\e[0m"    # [u]nicode[c]yan[c]ircle    [u]nicode[l]ight[c]yan[c]ircle
ugrc="\e[37m\U25cf\e[0m" ulgrcc="\e[97m\U25cf\e[0m" # [u]nicode[gr]ey[c]ircle    [u]nicode[l]ight[gr]ey[c]ircle

cdef="\e[39m" # [c]olor[def]ault
cend="\e[0m"  # [c]olor[end]
#######################################################################################################################################################
# Check we are on a supported OS and release.
#######################################################################################################################################################
# Get the main platform name, for example: debian, ubuntu or alpine
what_id="$(source /etc/os-release && printf "%s" "${ID}")"

# Get the codename for this this OS. Note, Alpine does not have a unique codename.
what_version_codename="$(source /etc/os-release && printf "%s" "${VERSION_CODENAME}")"

# Get the version number for this codename, for example: 10, 20.04, 3.12.4
what_version_id="$(source /etc/os-release && printf "%s" "${VERSION_ID%_*}")"

# Account for varation in the versioning 3.1 or 3.1.0 to make sure the check works correctly
[[ "$(wc -w <<< "${what_version_id//\./ }")" -eq "2" ]] && alpline_min_version="310"

# If alpine, set the codename to alpine. We check for min v3.10 later with codenames.
if [[ "${what_id}" =~ ^(alpine)$ ]]; then
	what_version_codename="alpine"
fi

## Check against allowed codenames or if the codename is alpine version greater than 3.10
if [[ ! "${what_version_codename}" =~ ^(alpine|bullseye|focal|jammy)$ ]] || [[ "${what_version_codename}" =~ ^(alpine)$ && "${what_version_id//\./}" -lt "${alpline_min_version:-3100}" ]]; then
	printf '\n%b\n\n' " ${urc} ${cy} This is not a supported OS. There is no reason to continue.${cend}"
	printf '%b\n\n' " id: ${td}${cly}${what_id}${cend} codename: ${td}${cly}${what_version_codename}${cend} version: ${td}${clr}${what_version_id}${cend}"
	printf '%b\n\n' " ${uyc} ${td}These are the supported platforms${cend}"
	printf '%b\n' " ${clm}Debian${cend} - ${clb}bullseye${cend}"
	printf '%b\n' " ${clm}Ubuntu${cend} - ${clb}focal${cend} - ${clb}jammy${cend}"
	printf '%b\n\n' " ${clm}Alpine${cend} - ${clb}3.10.0${cend} or greater"
	exit 1
fi
#######################################################################################################################################################
# This function sets some default values we use but whose values can be overridden by certain flags or exported as variables before running the script
#######################################################################################################################################################
set_default_values() {
	# For docker deploys to not get prompted to set the timezone.
	DEBIAN_FRONTEND="noninteractive" && TZ="Europe/London"

	# The default build configuration is qmake + qt5, qbt_build_tool=cmake or -c will make qt6 and cmake default
	qbt_build_tool="${qbt_build_tool:-qmake}"

	# Default to empty to use host native build tools. This way we can build on native arch on a supported OS and skip crossbuild toolchains
	qbt_cross_name="${qbt_cross_name:-}"

	# Default to host - we are not really using this for anything other than what it defaults to so no need to set it.
	qbt_cross_target="${qbt_cross_target:-${what_id}}"

	# yes to create debug build to use with gdb - disables stripping - for some reason liborrent b2 builds are 200MB or larger. qbt_build_debug=yes or -d
	qbt_build_debug="${qbt_build_debug:-no}"

	# github actions workflows - use https://github.com/userdocs/qbt-workflow-files/releases/latest instead of direct downloads from various source locations.
	# Provides an alternative source and does not spam download hosts when building matrix builds.
	qbt_workflow_files="${qbt_workflow_files:-no}"

	# github actions workflows - use the workflow files saved as artifacts instead of downloading from workflow files or host per matrix
	qbt_workflow_artifacts="${qbt_workflow_artifacts:-no}"

	# Provide a git username and repo in this format - username/repo
	# In this repo the structure needs to be like this /patches/libtorrent/1.2.11/patch and/or /patches/qbittorrent/4.3.1/patch
	# your patch file will be automatically fetched and loadded for those matching tags.
	qbt_patches_url="${qbt_patches_url:-userdocs/qbittorrent-nox-static-test}"

	# Default to this version of libtorrent is no tag or branch is specificed. qbt_libtorrent_version=1.2 or -lt v1.2.18
	qbt_libtorrent_version="${qbt_libtorrent_version:-2.0}"

	# Use release Jamfile unless we need a specific fix from the relevant RC branch.
	# Using this can also break builds when non backported changes are present which will require a custom jamfile
	qbt_libtorrent_master_jamfile="${qbt_libtorrent_master_jamfile:-no}"

	# Strip symbols by default as we need full debug builds to be useful gdb to backtrace so stripping is a sensible default optimisation.
	qbt_optimise_strip="${qbt_optimise_strip:-no}"

	# Github actions specific - Build revisions - The workflow will set this dynamically so that the urls are not hardcoded to a single repo
	qbt_revision_url="${qbt_revision_url:-userdocs/qbittorrent-nox-static-test}"

	# Github actions specific - Build revisions - standard increments the revision version automatically in the script on build
	# The legacy workflow disables this and it is incremented by the workflow instead.
	qbt_workflow_type="${qbt_workflow_type:-standard}"

	# In standard mode gawk and bison are installed via apt-get as system dependencies. In alternate mode they are built from source.
	qbt_debian_mode="${qbt_debian_mode:-standard}"

	# Provide a path to check for cached local git repos and use those instead. Priority over worflow files.
	qbt_cache_dir="${qbt_cache_dir%/}"

	# We are only using python3 but it's easier to just change this if we need to for some reason.
	qbt_python_version="3"

	# Set the CXX standards used to build cxx code.
	# ${standard} - Set the CXX standard. You may need to set c++14 for older versions of some apps, like qt 5.12
	standard="17" && cpp_standard="c${standard}" && cxx_standard="c++${standard}"

	# The Alpine repository we use for package sources
	CDN_URL="http://dl-cdn.alpinelinux.org/alpine/edge/main" # for alpine

	# Define our list of available modules in an array.
	qbt_modules=("all" "install" "bison" "gawk" "glibc" "zlib" "iconv" "icu" "openssl" "boost" "libtorrent" "double_conversion" "qtbase" "qttools" "qbittorrent")

	# Create this array empty. Modules listed in or added to this array will be removed from the default list of modules, changing the behaviour of all or install
	delete=()

	# Create this array empty. Packages listed in or added to this array will be removed from the default list of packages, changing the list of installed dependencies
	delete_pkgs=()

	# A function to print some env value of the script dynamically. Used in the help section and script output.
	_print_env() {
		printf '\n%b\n\n' " ${uyc} Default env settings${cend}"
		printf '%b\n' " ${cly}  qbt_libtorrent_version=\"${clg}${qbt_libtorrent_version}${cly}\"${cend}"
		printf '%b\n' " ${cly}  qbt_qt_version=\"${clg}${qbt_qt_version}${cly}\"${cend}"
		printf '%b\n' " ${cly}  qbt_build_tool=\"${clg}${qbt_build_tool}${cly}\"${cend}"
		printf '%b\n' " ${cly}  qbt_cross_name=\"${clg}${qbt_cross_name}${cly}\"${cend}"
		printf '%b\n' " ${cly}  qbt_patches_url=\"${clg}${qbt_patches_url}${cly}\"${cend}"
		printf '%b\n' " ${cly}  qbt_workflow_files=\"${clg}${qbt_workflow_files}${cly}\"${cend}"
		printf '%b\n' " ${cly}  qbt_debian_mode=\"${clg}${qbt_debian_mode}${cly}\"${cend}"
		printf '%b\n' " ${cly}  qbt_cache_dir=\"${clg}${qbt_cache_dir}${cly}\"${cend}"
		printf '%b\n' " ${cly}  qbt_libtorrent_master_jamfile=\"${clg}${qbt_libtorrent_master_jamfile}${cly}\"${cend}"
		printf '%b\n' " ${cly}  qbt_optimise_strip=\"${clg}${qbt_optimise_strip}${cly}\"${cend}"
		printf '%b\n\n' " ${cly}  qbt_build_debug=\"${clg}${qbt_build_debug}${cly}\"${cend}"
	}

	# Dynamic tests to change settings based on the use of qmake,cmake,strip and debug
	if [[ "${qbt_build_debug}" = "yes" ]]; then
		qbt_optimise_strip="no"
		qbt_cmake_debug='ON'
		qbt_libtorrent_debug='debug-symbols=on'
		qbt_qbittorrent_debug='--enable-debug'
	else
		qbt_cmake_debug='OFF'
	fi

	# Dynamic tests to change settings based on the use of qmake,cmake,strip and debug
	if [[ "${qbt_optimise_strip}" = "yes" && "${qbt_build_debug}" = "no" ]]; then
		qbt_strip_qmake='strip'
		qbt_strip_flags='-s'
	else
		qbt_strip_qmake='-nostrip'
		qbt_strip_flags=''
	fi

	# Dynamic tests to change settings based on the use of qmake,cmake,strip and debug
	case "${qbt_qt_version}" in
		5)
			if [[ "${qbt_build_tool}" != 'cmake' ]]; then
				qbt_build_tool="qmake"
				qbt_use_qt6="OFF"
			fi
			;;&
		6)
			qbt_build_tool="cmake"
			qbt_use_qt6="ON"
			;;&
		"")
			[[ "${qbt_build_tool}" == 'cmake' ]] && qbt_qt_version="6" || qbt_qt_version="5"
			;;&
		*)
			[[ ! "${qbt_qt_version}" =~ ^(5|6)$ ]] && qbt_workflow_files="no"
			[[ "${qbt_build_tool}" == 'qmake' && "${qbt_qt_version}" =~ ^6 ]] && qbt_build_tool="cmake"
			[[ "${qbt_build_tool}" == 'cmake' && "${qbt_qt_version}" =~ ^5 ]] && qbt_build_tool="cmake" qbt_qt_version="6"
			[[ "${qbt_build_tool}" == 'cmake' && "${qbt_qt_version}" =~ ^6 ]] && qbt_use_qt6="ON"
			;;
	esac

	# If we are crossbuilding then bootstrap the crossbuild tools we ned for the target arch else set native arch and remove the debian crossbuild tools
	if [[ ${qbt_cross_name} =~ ^(x86_64|armhf|armv7|aarch64)$ ]]; then
		_multi_arch bootstrap
	else
		cross_arch="$(uname -m)"
		delete_pkgs+=("crossbuild-essential-${cross_arch}")
	fi

	# if Alpine then delete modules we don't use and set the required packages array
	if [[ "${what_id}" =~ ^(alpine)$ ]]; then
		delete+=("bison" "gawk" "glibc")
		[[ -z "${qbt_cache_dir}" ]] && delete_pkgs+=("coreutils" "gpg")
		qbt_required_pkgs=("autoconf" "automake" "bash" "bash-completion" "build-base" "coreutils" "curl" "git" "gpg" "pkgconf" "libtool" "perl" "python${qbt_python_version}" "python${qbt_python_version}-dev" "py${qbt_python_version}-numpy" "py${qbt_python_version}-numpy-dev" "linux-headers" "ttf-freefont" "graphviz" "cmake" "re2c")
	fi

	# if debian based then set the required packages array
	if [[ "${what_id}" =~ ^(debian|ubuntu)$ ]]; then
		[[ "${qbt_debian_mode}" == 'alternate' ]] && delete_pkgs+=("gawk" "bison")
		[[ "${qbt_debian_mode}" == 'standard' ]] && delete+=("bison" "gawk")
		qbt_required_pkgs=("gettext" "texinfo" "gawk" "bison" "build-essential" "crossbuild-essential-${cross_arch}" "curl" "pkg-config" "automake" "libtool" "git" "openssl" "perl" "python${qbt_python_version}" "python${qbt_python_version}-dev" "python${qbt_python_version}-numpy" "unzip" "graphviz" "re2c")
	fi

	# remove this module by default unless provided as a first argument to the script.
	if [[ "${1}" != 'install' ]]; then
		delete+=("install")
	fi

	# Don't remove the icu module if it was provided as a positional parameter.
	# else skip icu by default unless the -i flag is provided.
	if [[ "${*}" =~ ([[:space:]]|^)"icu"([[:space:]]|$) ]]; then
		qbt_skip_icu="no"
	elif [[ "${qbt_skip_icu}" != "no" ]]; then
		delete+=("icu")
	fi

	# Configure default dependencies and modules if cmake is not specificed
	if [[ "${qbt_build_tool}" != 'cmake' ]]; then
		delete+=("double_conversion")
		delete_pkgs+=("unzip" "ttf-freefont" "graphviz" "cmake" "re2c")
	else
		[[ "${qbt_skip_icu}" != "no" ]] && delete+=("icu")
	fi

	# Set the working dir to our current location and all things well be relative to this location.
	qbt_working_dir="$(pwd)"

	# Used with printf. Use the qbt_working_dir variable but the $HOME path is replaced with a literal ~
	qbt_working_dir_short="${qbt_working_dir/$HOME/\~}"

	# Install relative to the script location.
	qbt_install_dir="${qbt_working_dir}/qbt-build"

	# Used with printf. Use the qbt_install_dir variable but the $HOME path is replaced with a literal ~
	qbt_install_dir_short="${qbt_install_dir/$HOME/\~}"

	# Get the local users $PATH before we isolate the script by setting HOME to the install dir in the set_build_directory function.
	qbt_local_paths="$PATH"
}
#######################################################################################################################################################
# This function will check for a list of defined dependencies from the qbt_required_pkgs array. Apps like python3-dev are dynamically set
#######################################################################################################################################################
check_dependencies() {
	printf '\n%b\n\n' " ${ulbc} ${tb}Checking if required core dependencies are installed${cend}"

	# remove packages in the delete_pkgs from the qbt_required_pkgs array
	for target in "${delete_pkgs[@]}"; do
		for i in "${!qbt_required_pkgs[@]}"; do
			if [[ "${qbt_required_pkgs[i]}" == "${target}" ]]; then
				unset 'qbt_required_pkgs[i]'
			fi
		done
	done

	# Rebuild array to sort index from 0
	qbt_required_pkgs=("${qbt_required_pkgs[@]}")

	# This checks over the qbt_required_pkgs array for the OS specificed dependencies to see if they are installed
	for pkg in "${qbt_required_pkgs[@]}"; do

		if [[ "${what_id}" =~ ^(alpine)$ ]]; then
			pkgman() { apk info -e "${pkg}"; }
		fi

		if [[ "${what_id}" =~ ^(debian|ubuntu)$ ]]; then
			pkgman() { dpkg -s "${pkg}"; }
		fi

		if pkgman > /dev/null 2>&1; then
			printf '%b\n' " ${utick} ${pkg}"
		else
			if [[ -n "${pkg}" ]]; then
				deps_installed="no"
				printf '%b\n' " ${ucross} ${pkg}"
				qbt_checked_required_pkgs+=("$pkg")
			fi
		fi
	done

	# Check if user is able to install the dependencies, if yes then do so, if no then exit.
	if [[ "${deps_installed}" == "no" ]]; then
		if [[ "$(id -un)" == 'root' ]]; then
			printf '\n%b\n\n' " ${uplus} ${cg}Updating${cend}"

			if [[ "${what_id}" =~ ^(alpine)$ ]]; then
				apk update --repository="${CDN_URL}"
				apk upgrade --repository="${CDN_URL}"
				apk fix
			fi

			if [[ "${what_id}" =~ ^(debian|ubuntu)$ ]]; then
				apt-get update -y
				apt-get upgrade -y
				apt-get autoremove -y
			fi

			[[ -f /var/run/reboot-required ]] && {
				printf '\n%b\n\n' " ${cr}This machine requires a reboot to continue installation. Please reboot now.${cend}"
				exit
			}

			printf '\n%b\n\n' " ${uplus}${cg} Installing required dependencies${cend}"

			if [[ "${what_id}" =~ ^(alpine)$ ]]; then
				if ! apk add "${qbt_checked_required_pkgs[@]}" --repository="${CDN_URL}"; then
					printf '\n'
					exit 1
				fi
			fi

			if [[ "${what_id}" =~ ^(debian|ubuntu)$ ]]; then
				if ! apt-get install -y "${qbt_checked_required_pkgs[@]}"; then
					printf '\n'
					exit 1
				fi
			fi

			printf '\n%b\n' " ${utick}${cg} Dependencies installed!${cend}"

			deps_installed="yes"
		else
			printf '\n%b\n' " ${tb}Please request or install the missing core dependencies before using this script${cend}"

			if [[ "${what_id}" =~ ^(alpine)$ ]]; then
				printf '\n%b\n\n' " ${clr}apk add${cend} ${qbt_checked_required_pkgs[*]}"
			fi

			if [[ "${what_id}" =~ ^(debian|ubuntu)$ ]]; then
				printf '\n%b\n\n' " ${clr}apt-get install -y${cend} ${qbt_checked_required_pkgs[*]}"
			fi

			exit
		fi
	fi

	# All checks passed print
	if [[ "${deps_installed}" != "no" ]]; then
		printf '\n%b\n' " ${ugc}${tb} All checks passed and core dependencies are installed, continuing to build${cend}"
	fi
}
#######################################################################################################################################################
# This is first help section that for triggers that do not require any processing and only provide a static result whe using help
#######################################################################################################################################################
while (("${#}")); do
	case ${1} in
		-b | --build-directory)
			qbt_build_dir="${2}"
			shift 2
			;;
		-c | --cmake)
			qbt_build_tool="cmake"
			shift
			;;
		-d | --debug)
			qbt_build_debug="yes"
			shift
			;;
		-sdu | --scripts-debug-urls)
			script_debug_urls="yes"
			shift
			;;
		-dma | --debian-mode-alternate)
			qbt_debian_mode="alternate"
			shift
			;;

		-cd | --cache-directory)
			qbt_cache_dir="${2%/}"
			if [[ -n "${3}" ]]; then
				qbt_cache_dir_options="${3}"
				shift 3
			else
				shift 2
			fi
			;;
		-i | --icu)
			qbt_skip_icu="no"
			[[ "${qbt_skip_icu}" == "no" ]] && delete=("${delete[@]/icu/}")
			shift
			;;
		-p | --proxy)
			qbt_git_proxy="${2}"
			qbt_curl_proxy="${2}"
			shift 2
			;;
		-ma | --multi-arch)
			if [[ -n "${2}" && "${2}" =~ ^(x86_64|armhf|armv7|aarch64)$ ]]; then
				qbt_cross_name="${2}"
				shift 2
			else
				printf '\n%b\n' " ${ulrc} You must provide a valid arch option when using${cend} ${clb}-ma${cend}"
				printf '\n%b\n' " ${ulbc} armhf${cend}"
				printf '%b\n' " ${ulbc} armv7${cend}"
				printf '%b\n' " ${ulbc} aarch64${cend}"
				printf '%b\n' " ${ulbc} x86_64${cend}"
				printf '\n%b\n\n' " ${ulgc} Example usage:${clb} -ma aarch64${cend}"
				exit 1
			fi
			shift
			;;
		-o | --optimize)
			optimize="-march=native"
			shift
			;;
		-s | --strip)
			qbt_optimise_strip="yes"
			shift
			;;
		-wf | --workflow)
			qbt_workflow_files="yes"
			shift
			;;
		-h-cd | --help-cache-directory)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " This will let you set a path of a directory that contains cached github repos of modules"
			printf '\n%b\n' " ${uyc} Cached apps folder names must match the module name. Case and spelling"
			printf '\n%b\n' " For example: ${clc}~/cache_dir/qbittorrent${cend}"
			printf '\n%b\n\n' " ${ulbc} Usage example: ${clb}-cd ~/cache_dir${cend}"
			exit
			;;
		-h-dma | --help-debian-mode-alternate)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " This modes builds the dependencies ${clm}gawk${cend} and ${clm}bison${cend} from source"
			printf '\n%b\n' " In the standard mode they are installed via ${clm}apt-get${cend} as dependencies"
			printf '\n%b\n\n' " ${ulbc} Usage example: ${clb}-dma${cend}"
			exit
			;;
		-h-o | --help-optimize)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " ${uyc} ${cly}Warning:${cend} using this flag will mean your static build is limited a CPU that matches the host spec"
			printf '\n%b\n' " ${ulbc} Usage example: ${clb}-o${cend}"
			printf '\n%b\n\n' " Additonal flags used: ${clc}-march=native${cend}"
			exit
			;;
		-h-p | --help-proxy)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Specify a proxy URL and PORT to use with curl and git"
			printf '\n%b\n' " ${ulbc} Usage examples:"
			printf '\n%b\n' " ${clb}-p${cend} ${clc}username:password@https://123.456.789.321:8443${cend}"
			printf '\n%b\n' " ${clb}-p${cend} ${clc}https://proxy.com:12345${cend}"
			printf '\n%b\n' " ${uyc} Call this before the help option to see outcome dynamically:"
			printf '\n%b\n\n' " ${clb}-p${cend} ${clc}https://proxy.com:12345${cend} ${clb}-h-p${cend}"
			[[ -n "${qbt_curl_proxy}" ]] && printf '%b\n' " proxy command: ${clc}${qbt_curl_proxy}${tn}${cend}"
			exit
			;;
		--) # end argument parsing
			shift
			break
			;;
		*) # preserve positional arguments
			params1+=("${1}")
			shift
			;;
	esac
done

# Set positional arguments in their proper place.
set -- "${params1[@]}"
#######################################################################################################################################################
# curl test download functions - default is no proxy - curl is a test function and curl_curl is the command function
#######################################################################################################################################################
curl_curl() {
	if [[ -z "${qbt_curl_proxy}" ]]; then
		"$(type -P curl)" -sNL4fq --connect-timeout 5 --retry 5 --retry-delay 5 --retry-max-time 25 "${@}"
	else
		"$(type -P curl)" -sNL4fq --connect-timeout 5 --retry 5 --retry-delay 5 --retry-max-time 25 --proxy-insecure -x "${qbt_curl_proxy}" "${@}"
	fi

}

curl() {
	if ! curl_curl "${@}"; then
		printf '%b\n' 'error_url'
	fi
}
#######################################################################################################################################################
# git test download functions - default is no proxy - git is a test function and git_git is the command function
#######################################################################################################################################################
git_git() {
	if [[ -z "${qbt_git_proxy}" ]]; then
		"$(type -P git)" "${@}"
	else
		"$(type -P git)" -c http.sslVerify=false -c http.https://github.com.proxy="${qbt_git_proxy}" "${@}"
	fi
}

git() {
	if [[ "${2}" == '-t' ]]; then
		url_test="${1}"
		tag_flag="${2}"
		tag_test="${3}"
	else
		url_test="${11}" # 11th place in our download folder function
	fi

	if ! curl -I "${url_test%\.git}" &> /dev/null; then
		printf '\n%b\n\n' " ${cy}There is an issue with your proxy settings or network connection${cend}"
		exit
	fi

	status="$(
		git_git ls-remote --exit-code "${url_test}" "${tag_flag}" "${tag_test}" &> /dev/null
		printf '%b\n' "${?}"
	)"

	if [[ "${tag_flag}" == '-t' && "${status}" == '0' ]]; then
		printf '%b\n' "${tag_test}"
	elif [[ "${tag_flag}" == '-t' && "${status}" -ge '1' ]]; then
		printf '%b\n' 'error_tag'
	else
		if ! git_git "${@}"; then
			printf '\n%b\n\n' " ${cy}There is an issue with your proxy settings or network connection${cend}"
			exit
		fi
	fi
}

_test_git_ouput() {
	if [[ "${1}" == 'error_tag' ]]; then
		printf '\n%b\n' "${cy} Sorry, the provided ${2} tag ${cr}${3}${cend}${cy} is not valid${cend}"
	fi
}
#######################################################################################################################################################
# This function sets the build and installation directory. If the argument -b is used to set a build directory that directory is set and used.
# If nothing is specified or the switch is not used it defaults to the hard-coded path relative to the scripts location - qbittorrent-build
#######################################################################################################################################################
set_build_directory() {
	if [[ -n "${qbt_build_dir}" ]]; then
		if [[ "${qbt_build_dir}" =~ ^/ ]]; then
			qbt_install_dir="${qbt_build_dir}"
			qbt_install_dir_short="${qbt_install_dir/$HOME/\~}"
		else
			qbt_install_dir="${qbt_working_dir}/${qbt_build_dir}"
			qbt_install_dir_short="${qbt_working_dir_short}/${qbt_build_dir}"
		fi
	fi

	# Set lib and include directory paths based on install path.
	include_dir="${qbt_install_dir}/include"
	lib_dir="${qbt_install_dir}/lib"

	# Define some build specific variables
	LOCAL_USER_HOME="${HOME}" # Get the local user's home dir path before we contain HOME to the build dir.
	HOME="${qbt_install_dir}"
	PATH="${qbt_install_dir}/bin${PATH:+:${qbt_local_paths}}"
	PKG_CONFIG_PATH="${lib_dir}/pkgconfig"
}
#######################################################################################################################################################
# This function sets some compiler flags globally - b2 settings are set in the ~/user-config.jam  set in the _installation_modules function
#######################################################################################################################################################
custom_flags_set() {
	CXXFLAGS="${optimize/*/$optimize }-std=${cxx_standard} -static -w ${qbt_strip_flags} -Wno-psabi -I${include_dir}"
	CPPFLAGS="${optimize/*/$optimize }-static -w ${qbt_strip_flags} -Wno-psabi -I${include_dir}"
	LDFLAGS="${optimize/*/$optimize }-static -L${lib_dir} -pthread"
}

custom_flags_reset() {
	CXXFLAGS="${optimize/*/$optimize } -w -std=${cxx_standard}"
	CPPFLAGS="${optimize/*/$optimize } -w"
	LDFLAGS=""
}
#######################################################################################################################################################
# This function is where we set your URL and github tag info that we use with other functions.
#######################################################################################################################################################
_set_module_urls() {
	# Update check url for the _script_version function
	script_url="https://raw.githubusercontent.com/userdocs/qbittorrent-nox-static-test/master/qbittorrent-nox-static.sh"
	##########################################################################################################################################################
	# Create the github_url associative array for all the applications this script uses and we call them as ${github_url[app_name]}
	##########################################################################################################################################################
	declare -gA github_url
	if [[ ! "${what_id}" =~ ^(alpine)$ ]]; then
		github_url[cmake_ninja]="https://github.com/userdocs/qbt-cmake-ninja-crossbuilds.git"
		github_url[bison]="https://git.savannah.gnu.org/git/bison.git"
		github_url[gawk]="https://git.savannah.gnu.org/git/gawk.git"
		github_url[glibc]="https://sourceware.org/git/glibc.git"
	fi
	github_url[ninja]="https://github.com/ninja-build/ninja.git"
	github_url[zlib]="https://github.com/zlib-ng/zlib-ng.git"
	github_url[iconv]="https://git.savannah.gnu.org/git/libiconv.git"
	github_url[icu]="https://github.com/unicode-org/icu.git"
	github_url[double_conversion]="https://github.com/google/double-conversion.git"
	github_url[openssl]="https://github.com/openssl/openssl.git"
	github_url[boost]="https://github.com/boostorg/boost.git"
	github_url[libtorrent]="https://github.com/arvidn/libtorrent.git"
	github_url[qtbase]="https://github.com/qt/qtbase.git"
	github_url[qttools]="https://github.com/qt/qttools.git"
	github_url[qbittorrent]="https://github.com/qbittorrent/qBittorrent.git"
	##########################################################################################################################################################
	# Create the github_tag associative array for all the applications this script uses and we call them as ${github_tag[app_name]}
	##########################################################################################################################################################
	declare -gA github_tag
	if [[ ! "${what_id}" =~ ^(alpine)$ ]]; then
		github_tag[cmake_ninja]="$(git_git ls-remote -q -t --refs "${github_url[cmake_ninja]}" | awk '{sub("refs/tags/", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
		github_tag[bison]="$(git_git ls-remote -q -t --refs "${github_url[bison]}" | awk '/\/v/{sub("refs/tags/", "");sub("(.*)((-|_)[^0-9].*)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
		github_tag[gawk]="$(git_git ls-remote -q -t --refs "${github_url[gawk]}" | awk '/\/tags\/gawk/{sub("refs/tags/", "");sub("(.*)(-[^0-9].*)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
		if [[ "${what_version_codename}" =~ ^(jammy)$ ]]; then
			github_tag[glibc]="glibc-2.37"
		else # "$(git_git ls-remote -q -t --refs https://sourceware.org/git/glibc.git | awk '/\/tags\/glibc-[0-9]\.[0-9]{2}$/{sub("refs/tags/", "");sub("(.*)(-[^0-9].*)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
			github_tag[glibc]="glibc-2.31"
		fi
	else
		github_tag[ninja]="master"
	fi
	github_tag[ninja]="master"
	github_tag[zlib]="develop"
	github_tag[iconv]="$(git_git ls-remote -q -t --refs "${github_url[iconv]}" | awk '{sub("refs/tags/", "");sub("(.*)(-[^0-9].*)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
	github_tag[icu]="$(git_git ls-remote -q -t --refs "${github_url[icu]}" | awk '/\/release-/{sub("refs/tags/", "");sub("(.*)(-[^0-9].*)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
	github_tag[double_conversion]="$(git_git ls-remote -q -t --refs "${github_url[double_conversion]}" | awk '/v/{sub("refs/tags/", "");sub("(.*)(v6|rc|alpha|beta)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
	github_tag[openssl]="$(git_git ls-remote -q -t --refs "${github_url[openssl]}" | awk '/openssl/{sub("refs/tags/", "");sub("(.*)(v6|rc|alpha|beta)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n1)"
	github_tag[boost]=$(git_git ls-remote -q -t --refs "${github_url[boost]}" | awk '{sub("refs/tags/", "");sub("(.*)(rc|alpha|beta)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)
	github_tag[libtorrent]="$(git_git ls-remote -q -t --refs "${github_url[libtorrent]}" | awk '/'"v${qbt_libtorrent_version}"'/{sub("refs/tags/", "");sub("(.*)(-[^0-9].*)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
	github_tag[qtbase]="$(git_git ls-remote -q -t --refs "${github_url[qtbase]}" | awk '/'"v${qbt_qt_version}"'/{sub("refs/tags/", "");sub("(.*)(-a|-b|-r)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
	github_tag[qttools]="$(git_git ls-remote -q -t --refs "${github_url[qttools]}" | awk '/'"v${qbt_qt_version}"'/{sub("refs/tags/", "");sub("(.*)(-a|-b|-r)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
	github_tag[qbittorrent]="$(git_git ls-remote -q -t --refs "${github_url[qbittorrent]}" | awk '{sub("refs/tags/", "");sub("(.*)(-[^0-9].*|rc|alpha|beta)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n 1)"
	##########################################################################################################################################################
	# Create the app_version associative array for all the applications this script uses and we call them as ${app_version[app_name]}
	##########################################################################################################################################################
	declare -gA app_version
	app_version[ninja]="$(curl "https://raw.githubusercontent.com/ninja-build/ninja/master/src/version.cc" | sed -rn 's|const char\* kNinjaVersion = "(.*)";|\1|p' | sed 's/\.git//g')"
	if [[ ! "${what_id}" =~ ^(alpine)$ ]]; then
		app_version[cmake_debian]="${github_tag[cmake_ninja]%_*}"
		app_version[ninja_debian]="${github_tag[cmake_ninja]#*_}"
		app_version[bison]="${github_tag[bison]#v}"
		app_version[gawk]="${github_tag[gawk]#gawk-}"
		app_version[glibc]="${github_tag[glibc]#glibc-}"
	fi
	app_version[zlib]="$(curl "https://raw.githubusercontent.com/zlib-ng/zlib-ng/${github_tag[zlib]}/zlib.h.in" | sed -rn 's|#define ZLIB_VERSION "(.*)"|\1|p' | sed 's/\.zlib-ng//g')"
	app_version[iconv]="${github_tag[iconv]#v}"
	app_version[icu]="${github_tag[icu]#release-}"
	app_version[double_conversion]="${github_tag[bison]#v}"
	app_version[openssl]="${github_tag[openssl]#openssl-}"
	app_version[boost]="${github_tag[boost]#boost-}"
	app_version[libtorrent]="${github_tag[libtorrent]#v}"
	app_version[qtbase]="$(printf '%s' "${github_tag[qtbase]#v}" | sed 's/-lts-lgpl//g')"
	app_version[qttools]="$(printf '%s' "${github_tag[qttools]#v}" | sed 's/-lts-lgpl//g')"
	app_version[qbittorrent]="${github_tag[qbittorrent]#release-}"
	##########################################################################################################################################################
	# Create the source_archive_url associative array for all the applications this script uses and we call them as ${source_archive_url[app_name]}
	##########################################################################################################################################################
	declare -gA source_archive_url
	if [[ ! "${what_id}" =~ ^(alpine)$ ]]; then
		source_archive_url[cmake_ninja]="https://github.com/userdocs/qbt-cmake-ninja-crossbuilds/releases/latest/download/${what_id}-${what_version_codename}-cmake-$(dpkg --print-architecture).tar.gz"
		source_archive_url[bison]="https://ftp.gnu.org/gnu/bison/$(grep -Eo 'bison-([0-9]{1,3}[.]?)([0-9]{1,3}[.]?)([0-9]{1,3}?)\.tar.gz' <(curl https://ftp.gnu.org/gnu/bison/) | sort -V | tail -1)"
		source_archive_url[gawk]="https://ftp.gnu.org/gnu/gawk/$(grep -Eo 'gawk-([0-9]{1,3}[.]?)([0-9]{1,3}[.]?)([0-9]{1,3}?)\.tar.gz' <(curl https://ftp.gnu.org/gnu/gawk/) | sort -V | tail -1)"
		source_archive_url[glibc]="https://ftp.gnu.org/gnu/libc/${github_tag[glibc]}.tar.gz"
	fi
	source_archive_url[zlib]="https://github.com/zlib-ng/zlib-ng/archive/refs/heads/develop.tar.gz"
	source_archive_url[iconv]="https://ftp.gnu.org/gnu/libiconv/$(grep -Eo 'libiconv-([0-9]{1,3}[.]?)([0-9]{1,3}[.]?)([0-9]{1,3}?)\.tar.gz' <(curl https://ftp.gnu.org/gnu/libiconv/) | sort -V | tail -1)"
	source_archive_url[icu]="https://github.com/unicode-org/icu/releases/download/${github_tag[icu]}/icu4c-${github_tag[icu]/-/_}-src.tgz"
	source_archive_url[double_conversion]="https://github.com/google/double-conversion/archive/refs/tags/${github_tag[double_conversion]}.tar.gz"
	source_archive_url[openssl]="https://github.com/openssl/openssl/archive/${github_tag[openssl]}.tar.gz"
	source_archive_url[boost]="https://boostorg.jfrog.io/artifactory/main/release/${github_tag[boost]/boost-/}/source/${github_tag[boost]//[-\.]/_}.tar.gz"
	source_archive_url[libtorrent]="https://github.com/arvidn/libtorrent/releases/download/${github_tag[libtorrent]}/libtorrent-rasterbar-${github_tag[libtorrent]#v}.tar.gz"

	read -ra qt_version_short_array <<< "${app_version[qtbase]//\./ }"
	qt_version_short="${qt_version_short_array[0]}.${qt_version_short_array[1]}"

	if [[ "${qbt_qt_version}" =~ ^6 ]]; then
		source_archive_url[qtbase]="https://download.qt.io/official_releases/qt/${qt_version_short}/${app_version[qtbase]}/submodules/qtbase-everywhere-src-${app_version[qtbase]}.tar.xz"
		source_archive_url[qttools]="https://download.qt.io/official_releases/qt/${qt_version_short}/${app_version[qttools]}/submodules/qttools-everywhere-src-${app_version[qttools]}.tar.xz"
	else
		source_archive_url[qtbase]="https://download.qt.io/official_releases/qt/${qt_version_short}/${app_version[qtbase]}/submodules/qtbase-everywhere-opensource-src-${app_version[qtbase]}.tar.xz"
		source_archive_url[qttools]="https://download.qt.io/official_releases/qt/${qt_version_short}/${app_version[qttools]}/submodules/qttools-everywhere-opensource-src-${app_version[qttools]}.tar.xz"
	fi

	source_archive_url[qbittorrent]="https://github.com/qbittorrent/qBittorrent/archive/refs/tags/${github_tag[qbittorrent]}.tar.gz"
	##########################################################################################################################################################
	# Create the qbt_workflow_archive_url associative array for all the applications this script uses and we call them as ${qbt_workflow_archive_url[app_name]}
	##########################################################################################################################################################
	declare -gA qbt_workflow_archive_url
	if [[ ! "${what_id}" =~ ^(alpine)$ ]]; then
		qbt_workflow_archive_url[bison]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/bison.tar.xz"
		qbt_workflow_archive_url[gawk]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/gawk.tar.xz"
		qbt_workflow_archive_url[glibc]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/glibc.${github_tag[glibc]#glibc-}.tar.xz"
	fi
	qbt_workflow_archive_url[zlib]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/zlib.tar.xz"
	qbt_workflow_archive_url[iconv]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/iconv.tar.xz"
	qbt_workflow_archive_url[icu]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/icu.tar.xz"
	qbt_workflow_archive_url[double_conversion]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/double_conversion.tar.xz"
	qbt_workflow_archive_url[openssl]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/openssl.tar.xz"
	qbt_workflow_archive_url[boost]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/boost.tar.xz"
	qbt_workflow_archive_url[libtorrent]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/libtorrent.${github_tag[libtorrent]/v/}.tar.xz"
	qbt_workflow_archive_url[qtbase]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/qt${qbt_qt_version:0:1}base.tar.xz"
	qbt_workflow_archive_url[qttools]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/qt${qbt_qt_version:0:1}tools.tar.xz"
	qbt_workflow_archive_url[qbittorrent]="https://github.com/userdocs/qbt-workflow-files/releases/latest/download/qbittorrent.tar.xz"
	###################################################################################################################################################
	# Define some test URLs we use to check or test the status of some URLs
	###################################################################################################################################################
	boost_url_status="$(curl_curl -so /dev/null --head --write-out '%{http_code}' "https://boostorg.jfrog.io/artifactory/main/release/${app_version[boost]}/source/boost_${app_version[boost]//./_}.tar.gz")"
	url_test="$(curl -so /dev/null "https://www.google.com")"

	return
}
#######################################################################################################################################################
# Debug stuff
#######################################################################################################################################################
_debug() {
	if [[ "${script_debug_urls}" == "yes" ]]; then
		mapfile -t github_url_sorted < <(printf '%s\n' "${!github_url[@]}" | sort)
		printf '\n%b\n\n' " ${umc} ${cly}github_url${cend}"
		for n in "${github_url_sorted[@]}"; do
			printf '%b\n' " ${clg}$n${cend}: ${clb}${github_url[$n]}${cend}" #: ${github_url[$n]}"
		done

		mapfile -t github_tag_sorted < <(printf '%s\n' "${!github_tag[@]}" | sort)
		printf '\n%b\n\n' " ${umc} ${cly}github_tag${cend}"
		for n in "${github_tag_sorted[@]}"; do
			printf '%b\n' " ${clg}$n${cend}: ${clb}${github_tag[$n]}${cend}" #: ${github_url[$n]}"
		done

		mapfile -t app_version_sorted < <(printf '%s\n' "${!app_version[@]}" | sort)
		printf '\n%b\n\n' " ${umc} ${cly}app_version${cend}"
		for n in "${app_version_sorted[@]}"; do
			printf '%b\n' " ${clg}$n${cend}: ${clb}${app_version[$n]}${cend}" #: ${github_url[$n]}"
		done

		mapfile -t source_archive_url_sorted < <(printf '%s\n' "${!source_archive_url[@]}" | sort)
		printf '\n%b\n\n' " ${umc} ${cly}source_archive_url${cend}"
		for n in "${source_archive_url_sorted[@]}"; do
			printf '%b\n' " ${clg}$n${cend}: ${clb}${source_archive_url[$n]}${cend}" #: ${github_url[$n]}"
		done

		mapfile -t qbt_workflow_archive_url_sorted < <(printf '%s\n' "${!qbt_workflow_archive_url[@]}" | sort)
		printf '\n%b\n\n' " ${umc} ${cly}qbt_workflow_archive_url${cend}"
		for n in "${qbt_workflow_archive_url_sorted[@]}"; do
			printf '%b\n' " ${clg}$n${cend}: ${clb}${qbt_workflow_archive_url[$n]}${cend}" #: ${github_url[$n]}"
		done
		printf '\n'
		exit
	fi
}
#######################################################################################################################################################
# This function verifies the module names from the array qbt_modules in the default values function.
#######################################################################################################################################################
_installation_modules() {
	# remove modules from the delete array from the qbt_modules array
	for target in "${delete[@]}"; do
		for deactivated in "${!qbt_modules[@]}"; do
			if [[ "${qbt_modules[${deactivated}]}" == "${target}" ]]; then
				unset 'qbt_modules[${deactivated}]'
			fi
		done
	done

	# Rebuild the qbt_modules array so index the index is indexed from 0 onwards
	qbt_modules=("${qbt_modules[@]}")

	# For all modules params pass test that they exist in the qbt_modules array or set qbt_modules_test to fail

	for passed_params in "${@}"; do
		if [[ ! "${qbt_modules[*]}" =~ ${passed_params} ]]; then
			qbt_modules_test="fail"
		fi
	done

	# If the param all is passed then activate all validated modules for installation by setting the skip_${module}=no using eval
	if [[ "${qbt_modules_test}" != 'fail' && "${#}" -ne '0' ]]; then
		if [[ "${*}" =~ ([[:space:]]|^)all([[:space:]]|$) ]]; then
			for module in "${qbt_modules[@]:1}"; do
				eval "skip_${module}=no"
			done
			# Only activate the module passed as a param and leave the rest defauled to skip
		else
			for module in "${@}"; do
				eval "skip_${module}=no"
				qbt_modules=("all" "${module}")
			done
		fi

		# Create the directories we need.
		mkdir -p "${qbt_install_dir}/logs"
		mkdir -p "${PKG_CONFIG_PATH}"
		mkdir -p "${qbt_install_dir}/completed"

		# Set some python variables we need.
		python_major="$(python"${qbt_python_version}" -c "import sys; print(sys.version_info[0])")"
		python_minor="$(python"${qbt_python_version}" -c "import sys; print(sys.version_info[1])")"
		python_micro="$(python"${qbt_python_version}" -c "import sys; print(sys.version_info[2])")"

		python_short_version="${python_major}.${python_minor}"
		python_link_version="${python_major}${python_minor}"

		printf '%b\n' "using gcc : : : <cflags>${optimize/*/$optimize }-std=${cxx_standard} <cxxflags>${optimize/*/$optimize }-std=${cxx_standard} ;${tn}using python : ${python_short_version} : /usr/bin/python${python_short_version} : /usr/include/python${python_short_version} : /usr/lib/python${python_short_version} ;" > "$HOME/user-config.jam"

		# printf the build directory.
		printf '\n%b\n' " ${uyc}${tb} Install Prefix${cend} : ${clc}${qbt_install_dir_short}${cend}"

		# Some basic help
		printf '\n%b\n' " ${uyc}${tb} Script help${cend} : ${clc}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${clb}-h${cend}"
	else
		printf '\n%b\n' " ${tbk}${urc}${cend}${tb} One or more of the provided modules are not supported${cend}"
		printf '\n%b\n' " ${uyc}${tb} Below is a list of supported modules${cend}"
		printf '\n%b\n' " ${umc}${clm} ${qbt_modules[*]}${cend}"

		_print_env

		exit
	fi
}
#######################################################################################################################################################
# This function will test to see if a Jamfile patch file exists via the variable patches_github_url for the tag used.
#######################################################################################################################################################
apply_patches() {
	patch_app_name="${1}"
	# Libtorrent has two tag formats libtorrent-1_2_11 and the newer v1.2.11. Moving forward v1.2.11 is the standard format. Make sure we always get the same outcome for either
	[[ "${github_tag[libtorrent]}" =~ ^RC_ ]] && libtorrent_patch_tag="${github_tag[libtorrent]}"
	[[ "${github_tag[libtorrent]}" =~ ^libtorrent- ]] && libtorrent_patch_tag="${github_tag[libtorrent]#libtorrent-}" && libtorrent_patch_tag="${libtorrent_patch_tag//_/\.}"
	[[ "${github_tag[libtorrent]}" =~ ^v[0-9] ]] && libtorrent_patch_tag="${github_tag[libtorrent]#v}"

	# Start to define the default master branch we will use by transforming the libtorrent_patch_tag variable to underscores. The result is dynamic and can be: RC_1_0, RC_1_1, RC_1_2, RC_2_0 and so on.
	default_jamfile="${libtorrent_patch_tag//./\_}"

	# Remove everything after second underscore. Occasionally the tag will be short, like v2.0 so we need to make sure not remove the underscore if there is only one present.
	if [[ $(grep -o '_' <<< "$default_jamfile" | wc -l) -le 1 ]]; then
		default_jamfile="RC_${default_jamfile}"
	elif [[ $(grep -o '_' <<< "$default_jamfile" | wc -l) -ge 2 ]]; then
		default_jamfile="RC_${default_jamfile%_*}"
	fi

	qbittorrent_patch_tag="${github_tag[qbittorrent]#release-}" # qbittorrent has a consistent tag format of release-4.3.1.

	if [[ "${patch_app_name}" == 'bootstrap-help' ]]; then # All the core variables we need for the help command are set so we can exit this function now.
		return
	fi

	if [[ "${patch_app_name}" == 'bootstrap' ]]; then
		mkdir -p "${qbt_install_dir}/patches/libtorrent/${libtorrent_patch_tag}"
		mkdir -p "${qbt_install_dir}/patches/qbittorrent/${qbittorrent_patch_tag}"
		printf '\n%b\n' " ${uyc} Using the defaults, these directories have been created:${cend}"
		printf '\n%b\n' " ${clc}  $qbt_install_dir_short/patches/libtorrent/${libtorrent_patch_tag}${cend}"
		printf '\n%b\n' " ${clc}  $qbt_install_dir_short/patches/qbittorrent/${qbittorrent_patch_tag}${cend}"
		printf '\n%b\n' " ${ucc} If a patch file, named ${clc}patch${cend} is found in these directories it will be applied to the relevant module with a matching tag."
	else
		patch_tag="${patch_app_name}_patch_tag"
		patch_dir="${qbt_install_dir}/patches/${patch_app_name}/${!patch_tag}"
		patch_file="${patch_dir}/patch"
		patch_file_url="https://raw.githubusercontent.com/${qbt_patches_url}/master/patches/${patch_app_name}/${!patch_tag}/patch"
		patch_jamfile="Jamfile"
		patch_jamfile_url="https://raw.githubusercontent.com/${qbt_patches_url}/master/patches/${patch_app_name}/${!patch_tag}/Jamfile"

		[[ ! -d "${patch_dir}" ]] && mkdir -p "${patch_dir}"

		if [[ -f "${patch_file}" ]]; then
			[[ ${qbt_workflow_files} == "no" ]] && printf '\n'
			printf '%b\n'" ${utick}${cr} Using ${!patch_tag} existing patch file${cend} - ${patch_file}"
			[[ "${patch_app_name}" == 'qbittorrent' ]] && printf '\n' # purely comsetic
		else
			if curl_curl "${patch_file_url}" -o "${patch_file}"; then
				[[ ${qbt_workflow_files} == "no" ]] && printf '\n'
				printf '%b\n' " ${utick}${cr} Using ${!patch_tag} downloaded patch file${cend} - ${patch_file_url}"
				[[ "${patch_app_name}" == 'qbittorrent' ]] && printf '\n' # purely comsetic
			fi
		fi

		if [[ "${patch_app_name}" == 'libtorrent' ]]; then
			if [[ -f "${patch_dir}/Jamfile" ]]; then
				cp -f "${patch_dir}/Jamfile" "${patch_jamfile}"
				[[ ${qbt_workflow_files} == "no" ]] && printf '\n'
				printf '%b\n\n' " ${utick}${cr} Using existing custom Jamfile file${cend}"
			elif curl_curl "${patch_jamfile_url}" -o "${patch_jamfile}"; then
				[[ ${qbt_workflow_files} == "no" ]] && printf '\n'
				printf '%b\n\n' " ${utick}${cr} Using downloaded custom Jamfile file${cend}"
			elif [[ "${qbt_libtorrent_master_jamfile}" == "yes" ]]; then
				[[ ${qbt_workflow_files} == "no" ]] && printf '\n'
				curl_curl "https://raw.githubusercontent.com/arvidn/libtorrent/${default_jamfile}/Jamfile" -o "${patch_jamfile}"
				printf '%b\n\n' " ${utick}${cr} Using libtorrent branch master Jamfile file${cend}"
			else
				printf '\n%b\n\n' " ${utick}${cr} Using libtorrent ${github_tag[libtorrent]} Jamfile file${cend}"
			fi
		fi

		[[ -f "${patch_file}" ]] && patch -p1 < "${patch_file}"
	fi
}
#######################################################################################################################################################
# This function is to test a directory exists before attemtping to cd and fail with and exit code if it doesn't.
#######################################################################################################################################################
_pushd() {
	if ! pushd "$@" &> /dev/null; then
		printf '\n%b\n' "This directory does not exist. There is a problem"
		printf '\n%b\n\n' "${clr}${1}${cend}"
		exit 1
	fi
}

_popd() {
	if ! popd &> /dev/null; then
		printf '%b\n' "This directory does not exist. There is a problem"
		exit 1
	fi
}
#######################################################################################################################################################
# This function makes sure the log directory and path required exists for tee
#######################################################################################################################################################
tee() {
	[[ "$#" -eq 1 && "${1%/*}" =~ / ]] && mkdir -p "${1%/*}"
	[[ "$#" -eq 2 && "${2%/*}" =~ / ]] && mkdir -p "${2%/*}"
	command tee "$@"
}
#######################################################################################################################################################
# This function sets the name of the application to be used with the functions download_file/folder and delete_function
#######################################################################################################################################################
_application_name() {
	app_name="${1}"
	app_name_skip="skip_${app_name}"
}
#######################################################################################################################################################
# This function skips the deletion of the -n flag is supplied
#######################################################################################################################################################
application_skip() {
	if [[ "${1}" == 'last' ]]; then
		printf '\n%b\n\n' " ${uyc} Skipping ${clm}${app_name}${cend} module installation"
	else
		printf '\n%b\n' " ${uyc} Skipping ${clm}${app_name}${cend} module installation"
	fi
}
#######################################################################################################################################################
#
#######################################################################################################################################################
_cache_dirs() {
	if [[ -n "${qbt_cache_dir}" ]]; then

		# If the directory provided was relative then prepend pwd to it to get a full path.
		if [[ ! "${qbt_cache_dir}" =~ ^/ ]]; then
			qbt_cache_dir="$(pwd)/${qbt_cache_dir}"
		fi

		case "${qbt_cache_dir_options}" in
			rm)
				[[ -d ${qbt_cache_dir} ]] && rm -rf "${qbt_cache_dir}"
				printf '\n%b\n\n' " ${urc} ${clc}${qbt_cache_dir}${cend} removed"
				exit
				;;
			bs)
				qbt_cache_dir_bootstrap="yes"
				;;
			'') ;;
			*)
				printf '\n%b\n' " ${urc} ${cly}Unregonsied qbt_cache_dir_options used: ${cend}"
				printf '\n%b\n' "   Valid options you can use as a singular additon to the path"
				printf '\n%b\n' "   ${clb}-cd PATH rm${cend} : Delete the cache dir"
				printf '\n%b\n\n' "   ${clb}-cd PATH bs${cend} : Download the cache file but do not continue the installation"
				exit
				;;
		esac

		# If the cache_dir does not exist then create it now.
		[[ ! -d "${qbt_cache_dir}" ]] && mkdir "${qbt_cache_dir}"
		# The download loop

		for module in "${qbt_modules[@]:1}"; do

			_application_name "${module}"

			if [[ "${qbt_cache_dir_bootstrap}" == 'yes' || "${!app_name_skip:-yes}" == "no" ]]; then

				# If the modules folder exists then most into them and get the tag if present or alternativley, the branch name - set it to cached_module_tag
				if [[ -d "${qbt_cache_dir}/${module}" ]]; then
					_pushd "${qbt_cache_dir}/${module}"
					if [[ -z "$(git tag)" ]]; then
						cached_module_tag=$(git branch --show-current)
					else
						cached_module_tag="$(git tag)"
					fi
					_popd
				fi

				# If the tag or branches matches the github_tag[${module}] then update the git repo.
				if [[ "${cached_module_tag}" == "${github_tag[${module}]}" && -d "${qbt_cache_dir}/${module}" ]]; then
					_pushd "${qbt_cache_dir}/${module}"
					printf '\n%b\n\n' " ${ugc} ${clb}${module}${cend} - Updating directory ${clc}${qbt_cache_dir}${cend}"
					git pull --all -p
					_popd
				# If the tag or branch is different then start the download process.
				else
					_pushd "${qbt_cache_dir}" || exit 1
					# back up the old folder by moving and renaming it.
					[[ -d "${module}" ]] && mv -f "${module}" "${module}-$(date +'%j-%R:%S')"
					printf '\n%b\n' " ${ugc} ${clb}${module}${cend} - caching to directory ${clc}${qbt_cache_dir}${cend}"
					_download_folder "${module}"
				fi
			fi
		done
		[[ "${qbt_cache_dir_bootstrap}" == "yes" ]] && {
			printf '\n'
			exit
		}
	fi
}
#######################################################################################################################################################
# This function is for downloading source code archives
#######################################################################################################################################################
download_file() {
	if [[ -n "${1}" ]]; then
		[[ -n "${2}" ]] && subdir="/${2}" || subdir=""

		file_name="${qbt_install_dir}/${1}.tar.xz"

		# The default source
		source_url="${source_archive_url[${1}]}"

		if [[ "${qbt_workflow_files}" == "no" && "${qbt_workflow_artifacts}" == 'no' ]]; then
			printf '\n%b\n\n' " ${uplus}${cg} Installing ${1}${cend} source files - ${cly}${1}${cend} - ${cly}${source_url}${cend}"
		fi

		if [[ "${qbt_workflow_files}" == "yes" ]]; then
			source_url="${qbt_workflow_archive_url[${1}]}"
			printf '\n%b\n\n' " ${uplus}${cg} Installing ${1}${cend} workflows files - ${cly}${1}${cend} - ${cly}${source_url}${cend}"
		fi

		if [[ "${qbt_workflow_artifacts}" == "yes" ]]; then
			printf '\n%b\n\n' " ${uplus}${cg} Using ${1}${cend} artifact files ${cly}${file_name}${cend}"
		else
			if [[ -f "${file_name}" ]]; then
				grep -Eqom1 "(.*)[^/]" <(tar tf "${file_name}")
				post_command
				rm -rf {"${qbt_install_dir:?}/$(tar tf "${file_name}" | grep -Eom1 "(.*)[^/]")","${file_name}"}
			fi
			curl "${qbt_workflow_archive_url[${1}]}" -o "${file_name}"
		fi

		printf '%b\n' "${source_url}" > "${qbt_install_dir}/logs/${1}_file_url.log"

		_cmd tar xf "${file_name}" -C "${qbt_install_dir}"
		source_dir="${qbt_install_dir}/$(tar tf "${file_name}" | head -1 | cut -f1 -d"/")${subdir}"
		mkdir -p "${source_dir}"
		[[ "${1}" != 'boost' ]] && _pushd "${source_dir}"
	else
		printf '\n%b\n' "You must provide a filename name for the function - download_file"
		printf '%b\n' "It creates the name from the app_name_github_tag variable set in the URL section"
		printf '\n%b\n\n' "download_file filename url"
		exit
	fi
}
#######################################################################################################################################################
# This function is for downloading git releases based on their tag.
#######################################################################################################################################################
_download_folder() { # download_folder "${app_name}" "${github_url[${app_name}]}"
	if [[ -n "${1}" ]]; then
		[[ -n "${2}" ]] && subdir="/${2}" || subdir=""

		mkdir -p "${qbt_install_dir}/logs"
		printf '%s' "${github_url[${1}]}" > "${qbt_install_dir}/logs/github_url_${1}.log"
		git_git config --global advice.detachedHead false

		if [[ -n "${qbt_cache_dir}" ]]; then
			folder_name="${qbt_cache_dir}/${1}"
			folder_inc="${qbt_cache_dir}/include/${1}"
		else
			folder_name="${qbt_install_dir}/${1}"
			folder_inc="${qbt_install_dir}/include/${1}"
		fi

		[[ -z "${qbt_cache_dir}" && -d "${folder_name}" ]] && rm -rf "${folder_name}"
		[[ "${1}" == 'libtorrent' && -d "${folder_inc}" ]] && rm -rf "${folder_inc}"

		if [[ -n "${qbt_cache_dir}" && -d "${folder_name}" ]]; then
			printf "\n%b\n\n" " ${uplus}${cg} Installing ${1}${cend} -${clc} ${qbt_cache_dir}/${1}${cend} from ${cly}${github_url[${1}]}${cend} using tag${cly} ${github_tag[${1}]}${cend}"
		else
			printf "\n%b\n\n" " ${uplus}${cg} Installing ${1}${cend} - ${cly}${github_url[${1}]}${cend} using tag${cly} ${github_tag[${1}]}${cend}"
		fi

		if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${1}" ]]; then
			cp -rf "${qbt_cache_dir}/${1}"/. "${qbt_install_dir}/${1}"
		else
			if [[ -n "${qbt_cache_dir}" && "${1}" =~ (bison|qttools) ]]; then
				_cmd git clone --no-tags --single-branch --branch "${github_tag[${1}]}" -j"$(nproc)" --depth 1 "${github_url[${1}]}" "${folder_name}"
				_pushd "${folder_name}"
				git submodule update --force --recursive --init --remote --depth=1 --single-branch
				_popd
			else
				_cmd git clone --no-tags --single-branch --branch "${github_tag[${1}]}" --shallow-submodules --recurse-submodules -j"$(nproc)" --depth 1 "${github_url[${1}]}" "${folder_name}"
			fi
		fi

		mkdir -p "${qbt_install_dir}/${1}${subdir}"
		_pushd "${qbt_install_dir}/${1}${subdir}"
	else
		printf '\n%b\n' "You must provide a tag name for the function - download_folder"
		printf '%b\n' "It creates the tag from the app_name_github_tag variable set in the URL section"
		printf '\n%b\n' "download_folder tagname url subdir"
		exit
	fi
}
#######################################################################################################################################################
# This function is for removing files and folders we no longer need
#######################################################################################################################################################
delete_function() {
	if [[ -n "${1}" ]]; then
		if [[ -z "${qbt_skip_delete}" ]]; then
			[[ "$2" == 'last' ]] && printf '\n%b\n' " ${utick}${clr} Deleting $1 installation files and folders${cend}" || printf '\n%b\n' " ${utick}${clr} Deleting ${1} installation files and folders${cend}"
			file_name="${qbt_install_dir}/${1}.t${source_archive_url[${1}]##*.t}"
			folder_name="${qbt_install_dir}/${1}"
			[[ -f "${file_name}" ]] && rm -rf {"${qbt_install_dir:?}/$(tar tf "${file_name}" | grep -Eom1 "(.*)[^/]")","${file_name}"}
			[[ -d "${folder_name}" ]] && rm -rf "${folder_name}"
			[[ -d "${qbt_working_dir}" ]] && _pushd "${qbt_working_dir}"
		else
			[[ "${2}" == 'last' ]] && printf '\n%b\n' " ${uyc}${clr} Skipping $1 deletion${cend}" || printf '\n%b\n' " ${uyc}${clr} Skipping ${1} deletion${cend}"
		fi
	else
		printf '\n%b\n' "The delete_function works in tandem with the application_name function"
		printf '%b\n' "Set the app_name using the application_name function then use this function."
		printf '\n%b\n\n' "delete_function app_name"
		exit
	fi
}
#######################################################################################################################################################
# This function installs a completed static build of qbittorrent-nox to the /usr/local/bin for root or ${HOME}/bin for non root
#######################################################################################################################################################
install_qbittorrent() {
	if [[ -f "${qbt_install_dir}/completed/qbittorrent-nox" ]]; then
		if [[ "$(id -un)" == 'root' ]]; then
			mkdir -p "/usr/local/bin"
			cp -rf "${qbt_install_dir}/completed/qbittorrent-nox" "/usr/local/bin"
		else
			mkdir -p "${HOME}/bin"
			cp -rf "${qbt_install_dir}/completed/qbittorrent-nox" "${LOCAL_USER_HOME}/bin"
		fi

		printf '\n%b\n' " ${uplus} qbittorrent-nox has been installed!${cend}"
		printf '\n%b\n\n' " Run it using this command:"
		[[ "$(id -un)" == 'root' ]] && printf '\n%b\n\n' " ${cg}qbittorrent-nox${cend}" || printf '\n%b\n\n' " ${cg}~/bin/qbittorrent-nox${cend}"
		exit
	else
		printf '\n%b\n\n' " ${ucross} qbittorrent-nox has not been built to the defined install directory:"
		printf '\n%b\n' "${cg}${qbt_install_dir_short}/completed${cend}"
		printf '\n%b\n\n' "Please build it using the script first then install"
		exit
	fi
}
#######################################################################################################################################################
# This is a command test function: _cmd exit 1
#######################################################################################################################################################
_cmd() {
	if ! "${@}"; then
		printf '\n%b\n\n' " The command: ${clr}${*}${cend} failed"
		exit 1
	fi
}
#######################################################################################################################################################
# This is a command test function to test build commands for failure
#######################################################################################################################################################
post_command() {
	outcome=("${PIPESTATUS[@]}")
	[[ -n "${1}" ]] && command_type="${1}"
	if [[ "${outcome[*]}" =~ [1-9] ]]; then
		printf '\n%b\n\n' " ${urc}${clr} Error: The ${command_type:-tested} command produced an exit code greater than 0 - Check the logs${cend}"
		exit 1
	fi
}
#######################################################################################################################################################
# This function handles the Multi Arch dynamics of the script.
#######################################################################################################################################################
_multi_arch() {
	if [[ "${qbt_cross_name}" =~ ^(x86_64|armhf|armv7|aarch64)$ ]]; then
		if [[ "${what_id}" =~ ^(alpine|debian|ubuntu)$ ]]; then

			[[ "${1}" != 'bootstrap' ]] && printf '\n%b\n' " ${ugc}${cly} Using multiarch - arch: ${qbt_cross_name} host: ${what_id} target: ${qbt_cross_target}${cend}"

			case "${qbt_cross_name}" in
				armhf)
					case "${qbt_cross_target}" in
						alpine)
							cross_arch="armhf"
							qbt_cross_host="arm-linux-musleabihf"
							qbt_zlib_arch="armv6"
							;;&
						debian | ubuntu)
							cross_arch="armel"
							qbt_cross_host="arm-linux-gnueabi"
							;;&
						*)
							qbt_cross_openssl="linux-armv4"
							qbt_cross_boost="arm"
							qbt_cross_qtbase="linux-arm-gnueabi-g++"
							;;
					esac
					;;
				armv7)
					case "${qbt_cross_target}" in
						alpine)
							cross_arch="armv7"
							qbt_cross_host="armv7l-linux-musleabihf"
							qbt_zlib_arch="armv7"
							;;&
						debian | ubuntu)
							cross_arch="armhf"
							qbt_cross_host="arm-linux-gnueabihf"
							;;&
						*)
							qbt_cross_openssl="linux-armv4"
							qbt_cross_boost="arm"
							qbt_cross_qtbase="linux-arm-gnueabi-g++"
							;;
					esac
					;;
				aarch64)
					case "${qbt_cross_target}" in
						alpine)
							cross_arch="aarch64"
							qbt_cross_host="aarch64-linux-musl"
							qbt_zlib_arch="aarch64"
							;;&
						debian | ubuntu)
							cross_arch="arm64"
							qbt_cross_host="aarch64-linux-gnu"
							;;&
						*)
							qbt_cross_openssl="linux-aarch64"
							qbt_cross_boost="arm"
							qbt_cross_qtbase="linux-aarch64-gnu-g++"
							;;
					esac
					;;
				x86_64)
					case "${qbt_cross_target}" in
						alpine)
							cross_arch="x86_64"
							qbt_cross_host="x86_64-linux-musl"
							qbt_zlib_arch="x86_64"
							;;&
						debian | ubuntu)
							cross_arch="amd64"
							qbt_cross_host="x86_64-linux-gnu"
							;;&
						*)
							qbt_cross_openssl="linux-x86_64"
							qbt_cross_boost="x86_64"
							qbt_cross_qtbase="linux-g++-64"
							;;
					esac
					;;
			esac

			[[ "${1}" == 'bootstrap' ]] && return

			CHOST="${qbt_cross_host}"
			CC="${qbt_cross_host}-gcc"
			AR="${qbt_cross_host}-ar"
			CXX="${qbt_cross_host}-g++"

			mkdir -p "${qbt_install_dir}/logs"

			if [[ "${qbt_cross_target}" =~ ^(alpine)$ && ! -f "${qbt_install_dir}/${qbt_cross_host}.tar.gz" ]]; then
				curl "https://github.com/userdocs/qbt-musl-cross-make/releases/latest/download/${qbt_cross_host}.tar.gz" > "${qbt_install_dir}/${qbt_cross_host}.tar.gz"
				tar xf "${qbt_install_dir}/${qbt_cross_host}.tar.gz" --strip-components=1 -C "${qbt_install_dir}"
			fi

			_fix_multiarch_static_links "${qbt_cross_host}"

			multi_bison=("--host=${qbt_cross_host}")                                                # ${multi_bison[@]}
			multi_gawk=("--host=${qbt_cross_host}")                                                 # ${multi_gawk[@]}
			multi_glibc=("--host=${qbt_cross_host}")                                                # ${multi_glibc[@]}
			multi_iconv=("--host=${qbt_cross_host}")                                                # ${multi_iconv[@]}
			multi_icu=("--host=${qbt_cross_host}" "-with-cross-build=${qbt_install_dir}/icu/cross") # ${multi_icu[@]}
			multi_openssl=("./Configure" "${qbt_cross_openssl}")                                    # ${multi_openssl[@]}
			multi_qtbase=("-xplatform" "${qbt_cross_qtbase}")                                       # ${multi_qtbase[@]}

			if [[ "${qbt_build_tool}" == 'cmake' ]]; then
				multi_libtorrent=("-D CMAKE_CXX_COMPILER=${qbt_cross_host}-g++")        # ${multi_libtorrent[@]}
				multi_double_conversion=("-D CMAKE_CXX_COMPILER=${qbt_cross_host}-g++") # ${multi_double_conversion[@]}
				multi_qbittorrent=("-D CMAKE_CXX_COMPILER=${qbt_cross_host}-g++")       # ${multi_qbittorrent[@]}
			else
				b2_toolset="gcc-arm"
				printf '%b\n' "using gcc : arm : ${qbt_cross_host}-g++ : <cflags>${optimize/*/$optimize }-std=${cxx_standard} <cxxflags>${optimize/*/$optimize }-std=${cxx_standard} ;${tn}using python : ${python_short_version} : /usr/bin/python${python_short_version} : /usr/include/python${python_short_version} : /usr/lib/python${python_short_version} ;" > "$HOME/user-config.jam"
				multi_libtorrent=("toolset=${b2_toolset}")     # ${multi_libtorrent[@]}
				multi_qbittorrent=("--host=${qbt_cross_host}") # ${multi_qbittorrent[@]}
			fi
			return
		else
			printf '\n%b\n\n' " ${ulrc} Multiarch only works with Alpine Linux (native or docker)${cend}"
			exit 1
		fi
	else
		multi_openssl=("./config") # ${multi_openssl[@]}
		return
	fi
}
#######################################################################################################################################################
# Github Actions release info
#######################################################################################################################################################
_release_info() {
	_error_tag

	printf '\n%b\n' " ${ugc} ${cly}Release boot-strapped${cend}"

	release_info_dir="${qbt_install_dir}/release_info"

	mkdir -p "${release_info_dir}"

	cat > "${release_info_dir}/tag.md" <<- TAG_INFO
		${github_tag[qbittorrent]}_${github_tag[libtorrent]}
	TAG_INFO

	cat > "${release_info_dir}/title.md" <<- TITLE_INFO
		qbittorrent ${app_version[qbittorrent]} libtorrent ${app_version[libtorrent]}
	TITLE_INFO

	if git_git ls-remote --exit-code --tags "https://github.com/${qbt_revision_url}.git" "${github_tag[qbittorrent]}_${github_tag[libtorrent]}" &> /dev/null; then
		if grep -q '"name": "dependency-version.json"' < <(curl "https://api.github.com/repos/${qbt_revision_url}/releases/tags/${github_tag[qbittorrent]}_${github_tag[libtorrent]}"); then
			until curl_curl "https://github.com/${qbt_revision_url}/releases/download/${github_tag[qbittorrent]}_${github_tag[libtorrent]}/dependency-version.json" > remote-dependency-version.json; do
				printf '%b\n' "Waiting for dependency-version.json URL."
				sleep 2
			done

			remote_revision_version="$(sed -rn 's|(.*)"revision": "(.*)"|\2|p' < remote-dependency-version.json)"

			if [[ "${remote_revision_version}" =~ ^[0-9]+$ && "${qbt_workflow_type}" == 'standard' ]]; then
				qbt_revision_version="$((remote_revision_version + 1))"
			elif [[ "${remote_revision_version}" =~ ^[0-9]+$ && "${qbt_workflow_type}" == 'legacy' ]]; then
				qbt_revision_version="${remote_revision_version}"
			fi
		fi
	fi

	cat > "${release_info_dir}/dependency-version.json" <<- DEPENDENCY_INFO
		{
		    "qbittorrent": "${app_version[qbittorrent]}",
		    "qt${qt_version_short_array[0]}": "${app_version[qtbase]}",
		    "libtorrent_${qbt_libtorrent_version//\./_}": "${app_version[libtorrent]}",
		    "boost": "${app_version[boost]}",
		    "openssl": "${app_version[openssl]}",
		    "revision": "${qbt_revision_version:-0}"
		}
	DEPENDENCY_INFO

	cat > "${release_info_dir}/release.md" <<- RELEASE_INFO
		## Build info

		|           Components           |           Version           |
		| :----------------------------: | :-------------------------: |
		|          Qbittorrent           | ${app_version[qbittorrent]} |
		| Qt${qt_version_short_array[0]} |   ${app_version[qtbase]}    |
		|           Libtorrent           | ${app_version[libtorrent]}  |
		|             Boost              |    ${app_version[boost]}    |
		|            OpenSSL             |   ${app_version[openssl]}   |
		|            zlib-ng             |    ${app_version[zlib]}     |

		## Architectures and build info

		These source code files are used for workflows: [qbt-workflow-files](https://github.com/userdocs/qbt-workflow-files/releases/latest)

		These builds were created on Alpine linux using [custom prebuilt musl toolchains](https://github.com/userdocs/qbt-musl-cross-make/releases/latest) for:

		|  Arch   | Alpine Cross build files | Arch config |
		| :-----: | :----------------------: | :---------: |
		|  armhf  |   arm-linux-musleabihf   |   armv6zk   |
		|  armv7  | armv7l-linux-musleabihf  |   armv7-a   |
		| aarch64 |    aarch64-linux-musl    |   armv8-a   |
		| x86_64  |    x86_64-linux-musl     |    amd64    |

		## Build matrix for libtorrent ${github_tag[libtorrent]}

		ℹ️ With Qbittorrent 4.4.0 onwards all cmake builds use Qt6 and all qmake builds use Qt5, as long as Qt5 is supported.

		ℹ️ [Check the build table for more info](https://github.com/userdocs/qbittorrent-nox-static#build-table---dependencies---arch---os---build-tools)

		⚠️ Binary builds are stripped - See https://userdocs.github.io/qbittorrent-nox-static/#/debugging

		<!--
		declare -A current_build_version
		current_build_version[qbittorrent]="${app_version[qbittorrent]}"
		current_build_version[qt${qt_version_short_array[0]}]="${app_version[qtbase]}"
		current_build_version[libtorrent_${qbt_libtorrent_version//\./_}]="${app_version[libtorrent]}"
		current_build_version[boost]=${app_version[boost]}
		current_build_version[openssl]=${app_version[openssl]}
		current_build_version[revision]="${qbt_revision_version:-0}"
		-->
	RELEASE_INFO

	return
}
#######################################################################################################################################################
# cmake installation
#######################################################################################################################################################
_cmake() {
	if [[ "${qbt_build_tool}" == 'cmake' ]]; then
		printf '\n%b\n' " ${ulbc}${clr} Checking if cmake and ninja need to be installed${cend}"
		mkdir -p "${qbt_install_dir}/bin"
		_pushd "${qbt_install_dir}"

		if [[ "${what_id}" =~ ^(debian|ubuntu)$ ]]; then
			if [[ "$(cmake --version 2> /dev/null | awk 'NR==1{print $3}')" != "${app_version[cmake_debian]}" ]]; then
				curl "${source_archive_url[cmake_ninja]}" > "${what_id}-${what_version_codename}-cmake-$(dpkg --print-architecture).tar.gz"
				post_command "Debian cmake and ninja installation"
				tar xf "${what_id}-${what_version_codename}-cmake-$(dpkg --print-architecture).tar.gz" --strip-components=1 -C "${qbt_install_dir}"
				rm -f "${what_id}-${what_version_codename}-cmake-$(dpkg --print-architecture).deb"

				printf '\n%b\n' " ${uyc} Installed cmake: ${cly}${app_version[cmake_debian]}"
				printf '\n%b\n' " ${uyc} Installed ninja: ${cly}${app_version[cmake_ninja]}"
			else
				printf '\n%b\n' " ${uyc} Using cmake: ${cly}${app_version[cmake_debian]}"
				printf '\n%b\n' " ${uyc} Using ninja: ${cly}${app_version[cmake_ninja]}"
			fi
		fi

		if [[ "${what_id}" =~ ^(alpine)$ ]]; then
			if [[ "$("${qbt_install_dir}/bin/ninja" --version 2> /dev/null)" != "${app_version[ninja]}" ]]; then
				_download_folder ninja
				cmake -Wno-dev -Wno-deprecated -B build \
					-D CMAKE_BUILD_TYPE="release" \
					-D CMAKE_CXX_STANDARD="${standard}" \
					-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
					-D CMAKE_INSTALL_PREFIX="${qbt_install_dir}" |& tee "${qbt_install_dir}/logs/ninja.log"
				cmake --build build -j"$(nproc)" |& tee -a "${qbt_install_dir}/logs/ninja.log"

				post_command build

				cmake --install build |& tee -a "${qbt_install_dir}/logs/ninja.log"
				_pushd "${qbt_install_dir}" && rm -rf "${qbt_install_dir}/ninja"
			fi
		fi

		printf '\n%b\n' " ${ugc}${clr} cmake and ninja are installed and ready to use${cend}"
	fi
}
#######################################################################################################################################################
# static lib link fix: check for *.so and *.a versions of a lib in the $lib_dir and change the *.so link to point to the statric lib e.g. libdl.a
#######################################################################################################################################################
_fix_static_links() {
	log_name="$1"
	mapfile -t library_list < <(find "${lib_dir}" -maxdepth 1 -exec bash -c 'basename "$0" ".${0##*.}"' {} \; | sort | uniq -d)
	for file in "${library_list[@]}"; do
		if [[ "$(readlink "${lib_dir}/${file}.so")" != "${file}.a" ]]; then
			ln -fsn "${file}.a" "${lib_dir}/${file}.so"
			printf 's%b\n' "${lib_dir}${file}.so changed to point to ${file}.a" >> "${qbt_install_dir}/logs/${log_name}-fix-static-links.log"
		fi
	done
	return
}
_fix_multiarch_static_links() {
	if [[ -d "${qbt_install_dir}/${qbt_cross_host}" ]]; then
		log_name="$1"
		multiarch_lib_dir="${qbt_install_dir}/${qbt_cross_host}/lib"
		mapfile -t library_list < <(find "${multiarch_lib_dir}" -maxdepth 1 -exec bash -c 'basename "$0" ".${0##*.}"' {} \; | sort | uniq -d)
		for file in "${library_list[@]}"; do
			if [[ "$(readlink "${multiarch_lib_dir}/${file}.so")" != "${file}.a" ]]; then
				ln -fsn "${file}.a" "${multiarch_lib_dir}/${file}.so"
				printf '%b\n' "${multiarch_lib_dir}${file}.so changed to point to ${file}.a" >> "${qbt_install_dir}/logs/${log_name}-fix-static-links.log"
			fi
		done
		return
	fi
}

#######################################################################################################################################################
# error functions
#######################################################################################################################################################
_error_url() {
	[[ "${url_test}" == "error_url" ]] && {
		printf '\n%b\n\n' " ${cy}There is an issue with your proxy settings or network connection${cend}"
		exit
	}
}
#
_error_tag() {
	[[ "${github_tag[*]}" =~ error_tag ]] && {
		printf '\n'
		exit
	}
}
#######################################################################################################################################################
# Script Version check
#######################################################################################################################################################
_script_version() {
	script_version_remote="$(curl -sL "${script_url}" | sed -rn 's|^script_version="(.*)"$|\1|p')"

	semantic_version() {
		local test_array
		read -ra test_array < <(printf "%s" "${@//./ }")
		printf "%d%03d%03d%03d" "${test_array[@]}"
	}

	if [[ "$(semantic_version "${script_version}")" -lt "$(semantic_version "${script_version_remote}")" ]]; then
		printf '\n%b\n' " ${tbk}${urc}${cend} Script update available! Versions - ${cly}local:${clr}${script_version}${cend} ${cly}remote:${clg}${script_version_remote}${cend}"
		printf '\n%b\n' " ${ugc} curl -sLo ~/qbittorrent-nox-static.sh https://git.io/qbstatic${cend}"
	else
		printf '\n%b\n' " ${ugc} Script version: ${clg}${script_version}${cend}"
	fi
}
#######################################################################################################################################################
# Functions part 1: Use some of our functions
#######################################################################################################################################################
set_default_values "${@}" # see functions

check_dependencies # see functions

set_build_directory # see functions

_set_module_urls "$@" # see functions
#######################################################################################################################################################
# This section controls our flags that we can pass to the script to modify some variables and behavior.
#######################################################################################################################################################
while (("${#}")); do
	case "${1}" in
		-bs | --boot-strap)
			apply_patches bootstrap
			shift
			;;
		-bs-c | --boot-strap-cmake)
			qbt_build_tool="cmake"
			_cmake
			shift
			;;
		-bs-r | --boot-strap-release)
			_release_info
			shift
			;;
		-bs-ma | --boot-strap-multi-arch)
			if [[ -n "${2}" && "${2}" =~ ^(x86_64|armhf|armv7|aarch64)$ ]]; then
				qbt_cross_name="${2}"
				shift 2
			else
				printf '\n%b\n' " ${ulrc} You must provide a valid arch option when using${cend} ${clb}-ma${cend}"
				printf '\n%b\n' " ${ulyc} armhf${cend}"
				printf '%b\n' " ${ulyc} armv7${cend}"
				printf '%b\n' " ${ulyc} aarch64${cend}"
				printf '%b\n' " ${ulyc} x86_64${cend}"
				printf '\n%b\n\n' " ${ulgc} example usage:${clb} -ma aarch64${cend}"
				exit 1
			fi
			_multi_arch
			shift
			;;
		-bs-a | --boot-strap-all)
			apply_patches bootstrap
			_release_info
			_cmake
			_multi_arch
			shift
			;;
		-bv | --boost-version)
			github_tag[boost]="$(git "${github_url[boost]}" -t "boost-$2")"
			app_version[boost]="${github_tag[boost]#boost-}"
			source_archive_url[boost]="https://boostorg.jfrog.io/artifactory/main/release/$2/source/boost_${2//\./_}.tar.gz"
			_test_git_ouput "${github_tag[boost]}" "boost" "boost-$2"
			override_workflow="yes"
			shift 2
			;;
		-n | --no-delete)
			qbt_skip_delete="yes"
			shift
			;;
		-m | --master)
			github_tag[libtorrent]="$(git "${github_url[libtorrent]}" -t "RC_${qbt_libtorrent_version//./_}")"
			app_version[libtorrent]="${github_tag[libtorrent]#v}"
			_test_git_ouput "${github_tag[libtorrent]}" "libtorrent" "RC_${qbt_libtorrent_version//./_}"

			github_tag[qbittorrent]="$(git "${github_url[qbittorrent]}" -t "master")"
			app_version[qbittorrent]="${github_tag[qbittorrent]#release-}"
			_test_git_ouput "${github_tag[qbittorrent]}" "qbittorrent" "master"

			override_workflow="yes"
			shift
			;;
		-lm | --libtorrent-master)
			github_tag[libtorrent]="$(git "${github_url[libtorrent]}" -t "RC_${qbt_libtorrent_version//./_}")"
			app_version[libtorrent]="${github_tag[libtorrent]#v}"
			_test_git_ouput "${github_tag[libtorrent]}" "libtorrent" "RC_${qbt_libtorrent_version//./_}"
			override_workflow="yes"
			shift
			;;
		-lt | --libtorrent-tag)
			github_tag[libtorrent]="$(git "${github_url[libtorrent]}" -t "$2")"
			app_version[libtorrent]="${github_tag[libtorrent]#v}"
			_test_git_ouput "${github_tag[libtorrent]}" "libtorrent" "$2"
			override_workflow="yes"
			shift 2
			;;
		-pr | --patch-repo)
			if [[ "$(curl "https://github.com/${2}")" != 'error_url' ]]; then
				qbt_patches_url="${2}"
			else
				printf '\n%b\n' " ${cy}This repo does not exist:${cend}"
				printf '\n%b\n' " https://github.com/${2}"
				printf '\n%b\n\n' " ${cy}Please provide a valid username and repo.${cend}"
				exit
			fi
			shift 2
			;;
		-qm | --qbittorrent-master)
			github_tag[qbittorrent]="$(git "${github_url[qbittorrent]}" -t "master")"
			app_version[qbittorrent]="${github_tag[qbittorrent]#release-}"
			_test_git_ouput "${github_tag[qbittorrent]}" "qbittorrent" "master"
			override_workflow="yes"
			shift
			;;
		-qt | --qbittorrent-tag)
			github_tag[qbittorrent]="$(git "${github_url[qbittorrent]}" -t "$2")"
			app_version[qbittorrent]="${github_tag[qbittorrent]#release-}"
			_test_git_ouput "${github_tag[qbittorrent]}" "qbittorrent" "$2"
			override_workflow="yes"
			shift 2
			;;
		-h | --help)
			printf '\n%b\n\n' " ${tb}${tu}Here are a list of available options${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-b${cend}     ${td}or${cend} ${clb}--build-directory${cend}       ${cy}Help:${cend} ${clb}-h-b${cend}     ${td}or${cend} ${clb}--help-build-directory${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-bv${cend}    ${td}or${cend} ${clb}--boost-version${cend}         ${cy}Help:${cend} ${clb}-h-bv${cend}    ${td}or${cend} ${clb}--help-boost-version${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-c${cend}     ${td}or${cend} ${clb}--cmake${cend}                 ${cy}Help:${cend} ${clb}-h-c${cend}     ${td}or${cend} ${clb}--help-cmake${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-cd${cend}    ${td}or${cend} ${clb}--cache-directory${cend}       ${cy}Help:${cend} ${clb}-h-cd${cend}    ${td}or${cend} ${clb}--help-cache-directory${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-d${cend}     ${td}or${cend} ${clb}--debug${cend}                 ${cy}Help:${cend} ${clb}-h-d${cend}     ${td}or${cend} ${clb}--help-debug${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-dma${cend}   ${td}or${cend} ${clb}--debian-mode-alternate${cend} ${cy}Help:${cend} ${clb}-h-dma${cend}   ${td}or${cend} ${clb}--help-debian-mode-alternate${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-bs${cend}    ${td}or${cend} ${clb}--boot-strap${cend}            ${cy}Help:${cend} ${clb}-h-bs${cend}    ${td}or${cend} ${clb}--help-boot-strap${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-bs-c${cend}  ${td}or${cend} ${clb}--boot-strap-cmake${cend}      ${cy}Help:${cend} ${clb}-h-bs-c${cend}  ${td}or${cend} ${clb}--help-boot-strap-cmake${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-bs-r${cend}  ${td}or${cend} ${clb}--boot-strap-release${cend}    ${cy}Help:${cend} ${clb}-h-bs-r${cend}  ${td}or${cend} ${clb}--help-boot-strap-release${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-bs-ma${cend} ${td}or${cend} ${clb}--boot-strap-multi-arch${cend} ${cy}Help:${cend} ${clb}-h-bs-ma${cend} ${td}or${cend} ${clb}--help-boot-strap-multi-arch${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-bs-a${cend}  ${td}or${cend} ${clb}--boot-strap-all${cend}        ${cy}Help:${cend} ${clb}-h-bs-a${cend}  ${td}or${cend} ${clb}--help-boot-strap-all${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-i${cend}     ${td}or${cend} ${clb}--icu${cend}                   ${cy}Help:${cend} ${clb}-h-i${cend}     ${td}or${cend} ${clb}--help-icu${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-lm${cend}    ${td}or${cend} ${clb}--libtorrent-master${cend}     ${cy}Help:${cend} ${clb}-h-lm${cend}    ${td}or${cend} ${clb}--help-libtorrent-master${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-lt${cend}    ${td}or${cend} ${clb}--libtorrent-tag${cend}        ${cy}Help:${cend} ${clb}-h-lt${cend}    ${td}or${cend} ${clb}--help-libtorrent-tag${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-m${cend}     ${td}or${cend} ${clb}--master${cend}                ${cy}Help:${cend} ${clb}-h-m${cend}     ${td}or${cend} ${clb}--help-master${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-ma${cend}    ${td}or${cend} ${clb}--multi-arch${cend}            ${cy}Help:${cend} ${clb}-h-ma${cend}    ${td}or${cend} ${clb}--help-multi-arch${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-n${cend}     ${td}or${cend} ${clb}--no-delete${cend}             ${cy}Help:${cend} ${clb}-h-n${cend}     ${td}or${cend} ${clb}--help-no-delete${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-o${cend}     ${td}or${cend} ${clb}--optimize${cend}              ${cy}Help:${cend} ${clb}-h-o${cend}     ${td}or${cend} ${clb}--help-optimize${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-p${cend}     ${td}or${cend} ${clb}--proxy${cend}                 ${cy}Help:${cend} ${clb}-h-p${cend}     ${td}or${cend} ${clb}--help-proxy${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-pr${cend}    ${td}or${cend} ${clb}--patch-repo${cend}            ${cy}Help:${cend} ${clb}-h-pr${cend}    ${td}or${cend} ${clb}--help-patch-repo${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-qm${cend}    ${td}or${cend} ${clb}--qbittorrent-master${cend}    ${cy}Help:${cend} ${clb}-h-qm${cend}    ${td}or${cend} ${clb}--help-qbittorrent-master${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-qt${cend}    ${td}or${cend} ${clb}--qbittorrent-tag${cend}       ${cy}Help:${cend} ${clb}-h-qt${cend}    ${td}or${cend} ${clb}--help-qbittorrent-tag${cend}"
			printf '%b\n' " ${cg}Use:${cend} ${clb}-s${cend}     ${td}or${cend} ${clb}--strip${cend}                 ${cy}Help:${cend} ${clb}-h-s${cend}     ${td}or${cend} ${clb}--help-strip${cend}"

			printf '\n%b\n' " ${tb}${tu}Module specific help - flags are used with the modules listed here.${cend}"

			printf '\n%b\n' " ${cg}Use:${cend} ${clm}all${cend} ${td}or${cend} ${clm}module-name${cend}          ${cg}Usage:${cend} ${clc}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${clm}all${cend} ${clb}-i${cend}"

			printf '\n%b\n' " ${td}${clm}all${cend} ${td}----------------${cend} ${td}${cly}optional${cend} ${td}Recommended method to install all modules${cend}"
			printf '%b\n' " ${td}${clm}install${cend} ${td}------------${cend} ${td}${cly}optional${cend} ${td}Install the ${td}${clc}${qbt_install_dir_short}/completed/qbittorrent-nox${cend} ${td}binary${cend}"
			[[ "${what_id}" =~ ^(debian|ubuntu)$ ]] && printf '%b\n' "${td} ${clm}bison${cend} ${td}--------------${cend} ${td}${cly}optional${cend} ${td}Build bison${cend}"
			[[ "${what_id}" =~ ^(debian|ubuntu)$ ]] && printf '%b\n' " ${td}${clm}gawk${cend} ${td}---------------${cend} ${td}${cly}optional${cend} ${td}Build gawk${cend}"
			[[ "${what_id}" =~ ^(debian|ubuntu)$ ]] && printf '%b\n' " ${td}${clm}glibc${cend} ${td}--------------${cend} ${td}${clr}required${cend} ${td}Build libc locally to statically link nss${cend}"
			printf '%b\n' " ${td}${clm}zlib${cend} ${td}---------------${cend} ${td}${clr}required${cend} ${td}Build zlib locally${cend}"
			printf '%b\n' " ${td}${clm}iconv${cend} ${td}--------------${cend} ${td}${clr}required${cend} ${td}Build iconv locally${cend}"
			printf '%b\n' " ${td}${clm}icu${cend} ${td}----------------${cend} ${td}${cly}optional${cend} ${td}Build ICU locally${cend}"
			printf '%b\n' " ${td}${clm}openssl${cend} ${td}------------${cend} ${td}${clr}required${cend} ${td}Build openssl locally${cend}"
			printf '%b\n' " ${td}${clm}boost${cend} ${td}--------------${cend} ${td}${clr}required${cend} ${td}Download, extract and build the boost library files${cend}"
			printf '%b\n' " ${td}${clm}libtorrent${cend} ${td}---------${cend} ${td}${clr}required${cend} ${td}Build libtorrent locally${cend}"
			printf '%b\n' " ${td}${clm}double_conversion${cend} ${td}--${cend} ${td}${clr}required${cend} ${td}A cmakke + Qt6 build compenent on modern OS only.${cend}"
			printf '%b\n' " ${td}${clm}qtbase${cend} ${td}-------------${cend} ${td}${clr}required${cend} ${td}Build qtbase locally${cend}"
			printf '%b\n' " ${td}${clm}qttools${cend} ${td}------------${cend} ${td}${clr}required${cend} ${td}Build qttools locally${cend}"
			printf '%b\n' " ${td}${clm}qbittorrent${cend} ${td}--------${cend} ${td}${clr}required${cend} ${td}Build qbittorrent locally${cend}"

			printf '\n%b\n' " ${tb}${tu}env help - supported exportable evironment variables${cend}"

			printf '\n%b\n' " ${td}${clm}export qbt_libtorrent_version=\"\"${cend} ${td}--------${cend} ${td}${clr}options${cend} ${td}1.2 - 2.0${cend}"
			printf '%b\n' " ${td}${clm}export qbt_qt_version=\"\"${cend} ${td}----------------${cend} ${td}${clr}options${cend} ${td}5 - 5.15 - 6 - 6.2 - 6.3 and so on${cend}"
			printf '%b\n' " ${td}${clm}export qbt_build_tool=\"\"${cend} ${td}----------------${cend} ${td}${clr}options${cend} ${td}qmake - cmake${cend}"
			printf '%b\n' " ${td}${clm}export qbt_cross_name=\"\"${cend} ${td}----------------${cend} ${td}${clr}options${cend} ${td}x86_64 - aarch64 - armv7 - armhf${cend}"
			printf '%b\n' " ${td}${clm}export qbt_patches_url=\"\"${cend} ${td}---------------${cend} ${td}${clr}options${cend} ${td}userdocs/qbittorrent-nox-static.${cend}"
			printf '%b\n' " ${td}${clm}export qbt_workflow_files=\"\"${cend} ${td}------------${cend} ${td}${clr}options${cend} ${td}yes no - use qbt-workflow-files for dependencies${cend}"
			printf '%b\n' " ${td}${clm}export qbt_debian_mode=\"\"${cend} ${td}---------------${cend} ${td}${clr}options${cend} ${td}standard alternate - defaults to standard${cend}"
			printf '%b\n' " ${td}${clm}export qbt_cache_dir=\"\"${cend} ${td}-----------------${cend} ${td}${clr}options${cend} ${td}path empty - provide a path to a cache directory${cend}"
			printf '%b\n' " ${td}${clm}export qbt_libtorrent_master_jamfile=\"\"${cend} ${td}-${cend} ${td}${clr}options${cend} ${td}yes no - use RC branch instead of release jamfile${cend}"
			printf '%b\n' " ${td}${clm}export qbt_optimise_strip=\"\"${cend} ${td}------------${cend} ${td}${clr}options${cend} ${td}yes no - strip binaries - cannot be used with debug${cend}"
			printf '%b\n' " ${td}${clm}export qbt_build_debug=\"\"${cend} ${td}---------------${cend} ${td}${clr}options${cend} ${td}yes no - debug build - cannot be used with strip${cend}"

			_print_env

			exit
			;;
		-h-b | --help-build-directory)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Default build location: ${cc}${qbt_install_dir_short}${cend}"
			printf '\n%b\n' " ${clb}-b${cend} or ${clb}--build-directory${cend} to set the location of the build directory."
			printf '\n%b\n' " ${cy}Paths are relative to the script location. I recommend that you use a full path.${cend}"
			printf '\n%b\n' " ${td}${ulbc} Usage example:${cend} ${td}${cg}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${td}${clm}all${cend} ${td}- Will install all modules and build libtorrent to the default build location${cend}"
			printf '\n%b\n' " ${td}${ulbc} Usage example:${cend} ${td}${cg}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${td}${clm}module${cend} ${td}- Will install a single module to the default build location${cend}"
			printf '\n%b\n\n' " ${td}${ulbc} Usage example:${cend} ${td}${cg}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${td}${clm}module${cend} ${clb}-b${cend} ${td}${clc}\"\$HOME/build\"${cend} ${td}- will specify a custom build directory and install a specific module use to that custom location${cend}"
			exit
			;;
		-h-bs | --help-boot-strap)
			apply_patches bootstrap-help
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Creates dirs in this structure: ${cc}${qbt_install_dir_short}/patches/app_name/tag/patch${cend}"
			printf '\n%b\n' " Add your patches there, for example."
			printf '\n%b\n' " ${cc}${qbt_install_dir_short}/patches/libtorrent/${libtorrent_patch_tag}/patch${cend}"
			printf '\n%b\n\n' " ${cc}${qbt_install_dir_short}/patches/qbittorrent/${qbittorrent_patch_tag}/patch${cend}"
			exit
			;;
		-h-bs-c | --help-boot-cmake)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " This bootstrap will install cmake and ninja build to the build directory"
			printf '\n%b\n\n'"${clg} Usage:${cend} ${clc}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${clb}-bs-c${cend}"
			exit
			;;
		-h-bs-r | --help-boot-strap-release)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' "${clr} Github action specific. You probably dont need it${cend}"
			printf '\n%b\n' " This switch creates some github release template files in this directory"
			printf '\n%b\n' " ${qbt_install_dir_short}/release_info"
			printf '\n%b\n\n' "${clg} Usage:${cend} ${clc}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${clb}-bs-r${cend}"
			exit
			;;
		-h-bs-ma | --help-boot-strap-multi-arch)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " ${urc}${clr} Github action and ALpine specific. You probably dont need it${cend}"
			printf '\n%b\n' " This switch bootstraps the musl cross build files needed for any provided and supported architecture"
			printf '\n%b\n' " ${uyc} armhf"
			printf '%b\n' " ${uyc} armv7"
			printf '%b\n' " ${uyc} aarch64"
			printf '\n%b\n' "${clg} Usage:${cend} ${clc}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${clb}-bs-ma ${qbt_cross_name:-aarch64}${cend}"
			printf '\n%b\n\n' " ${uyc} You can also set it as a variable to trigger cross building: ${clb}export qbt_cross_name=${qbt_cross_name:-aarch64}${cend}"

			exit
			;;
		-h-bs-a | --help-boot-strap-all)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " ${urc}${clr} Github action specific and Apine only. You probably dont need it${cend}"
			printf '\n%b\n' " Performs all bootstrapping options"
			printf '\n%b\n' "${clg} Usage:${cend} ${clc}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${clb}-bs-a${cend}"
			printf '\n%b\n' " ${uyc} ${cly}Patches${cend}"
			printf '%b\n' " ${uyc} ${cly}Release info${cend}"
			printf '%b\n' " ${uyc} ${cly}Cmake and ninja build${cend} if the ${clb}-c${cend} flag is passed"
			printf '%b\n' " ${uyc} ${cly}Multi arch${cend} if the ${clb}-ma${cend} flag is passed"
			printf '\n%b\n' " Equivalent of doing: ${clc}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${clb}-bs -bs-r${cend}"
			printf '\n%b\n\n' " And with ${clb}-c${cend} and ${clb}-ma${cend} : ${clc}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${clb}-bs -bs-c -bs-ma -bs-r ${cend}"
			exit
			;;
		-h-bv | --help-boost-version)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " This will let you set a specific version of boost to use with older build combos"
			printf '\n%b\n\n' " ${ulbc} Usage example: ${clb}-bv 1.76.0${cend}"
			exit
			;;
		-h-c | --help-cmake)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " This flag can change the build process in a few ways."
			printf '\n%b\n' " ${uyc} Use cmake to build libtorrent."
			printf '%b\n' " ${uyc} Use cmake to build qbittorrent."
			printf '\n%b\n\n' " ${uyc} You can use this flag with ICU and qtbase will use ICU instead of iconv."
			exit
			;;
		-h-d | --help-debug)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n\n' " Enables debug symbols for libtorrent and qbitorrent when building - required for gdb backtrace"
			exit
			;;
		-h-n | --help-no-delete)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Skip all delete functions for selected modules to leave source code directories behind."
			printf '\n%b\n' " ${td}This flag is provided with no arguments.${cend}"
			printf '\n%b\n\n' " ${clb}-n${cend}"
			exit
			;;
		-h-i | --help-icu)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Use ICU libraries when building qBittorrent. Final binary size will be around ~50Mb"
			printf '\n%b\n' " ${td}This flag is provided with no arguments.${cend}"
			printf '\n%b\n\n' " ${clb}-i${cend}"
			exit
			;;
		-h-m | --help-master)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Always use the master branch for ${cg}libtorrent RC_${qbt_libtorrent_version//./_}${cend}"
			printf '\n%b\n' " Always use the master branch for ${cg}qBittorrent ${github_tag[qbittorrent]/release-/}${cend}"
			printf '\n%b\n' " ${td}This flag is provided with no arguments.${cend}"
			printf '\n%b\n\n' " ${clb}-lm${cend}"
			exit
			;;
		-h-ma | --help-multi-arch)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " ${urc}${clr} Github action and ALpine specific. You probably dont need it${cend}"
			printf '\n%b\n' " This switch will make the script use the cross build configuration for these supported architectures"
			printf '\n%b\n' " ${uyc} armhf"
			printf '%b\n' " ${uyc} armv7"
			printf '%b\n' " ${uyc} aarch64"
			printf '\n%b\n' "${clg} Usage:${cend} ${clc}${qbt_working_dir_short}/$(basename -- "$0")${cend} ${clb}-bs-ma ${qbt_cross_name:-aarch64}${cend}"
			printf '\n%b\n\n' " ${uyc} You can also set it as a variable to trigger cross building: ${clb}export qbt_cross_name=${qbt_cross_name:-aarch64}${cend}"
			exit
			;;
		-h-lm | --help-libtorrent-master)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Always use the master branch for ${cg}libtorrent-${qbt_libtorrent_version}${cend}"
			printf '\n%b\n' " This master that will be used is: ${cg}RC_${qbt_libtorrent_version//./_}${cend}"
			printf '\n%b\n' " ${td}This flag is provided with no arguments.${cend}"
			printf '\n%b\n\n' " ${clb}-lm${cend}"
			exit
			;;
		-h-lt | --help-libtorrent-tag)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Use a provided libtorrent tag when cloning from github."
			printf '\n%b\n' " ${cy}You can use this flag with this help command to see the value if called before the help option.${cend}"
			printf '\n%b\n' " ${cg}${qbt_working_dir_short}/$(basename -- "$0")${cend}${clb} -lt ${clc}${github_tag[libtorrent]}${cend} ${clb}-h-lt${cend}"
			if [[ ! "${github_tag[libtorrent]}" =~ (error_tag|error_22) ]]; then
				printf '\n%b\n' " ${td}This is tag that will be used is: ${cg}${github_tag[libtorrent]}${cend}"
			fi
			printf '\n%b\n' " ${td}This flag must be provided with arguments.${cend}"
			printf '\n%b\n\n' " ${clb}-lt${cend} ${clc}${github_tag[libtorrent]}${cend}"
			exit
			;;
		-h-pr | --help-patch-repo)
			apply_patches bootstrap-help
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Specify a username and repo to use patches hosted on github${cend}"
			printf '\n%b\n' " ${cg}${ulbc} Usage example:${cend} ${clb}-pr${cend} ${clc}usnerame/repo${cend}"
			printf '\n%b\n' " ${cy}There is a specific github directory format you need to use with this flag${cend}"
			printf '\n%b\n' " ${clc}patches/libtorrent/$libtorrent_patch_tag/patch${cend}"
			printf '%b\n' " ${clc}patches/libtorrent/$libtorrent_patch_tag/Jamfile${cend} ${clr}(defaults to branch master)${cend}"
			printf '\n%b\n' " ${clc}patches/qbittorrent/$qbittorrent_patch_tag/patch${cend}"
			printf '\n%b\n' " ${cy}If an installation tag matches a hosted tag patch file, it will be automaticlaly used.${cend}"
			printf '\n%b\n\n' " The tag name will alway be an abbreviated version of the default or specificed tag.${cend}"
			exit
			;;
		-h-qm | --help-qbittorrent-master)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Always use the master branch for ${cg}qBittorrent${cend}"
			printf '\n%b\n' " This master that will be used is: ${cg}master${cend}"
			printf '\n%b\n' " ${td}This flag is provided with no arguments.${cend}"
			printf '\n%b\n\n' " ${clb}-qm${cend}"
			exit
			;;
		-h-qt | --help-qbittorrent-tag)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Use a provided qBittorrent tag when cloning from github."
			printf '\n%b\n' " ${cy}You can use this flag with this help command to see the value if called before the help option.${cend}"
			printf '\n%b\n' " ${cg}${qbt_working_dir_short}/$(basename -- "$0")${cend}${clb} -qt ${clc}${github_tag[qbittorrent]}${cend} ${clb}-h-qt${cend}"
			#
			if [[ ! "${github_tag[qbittorrent]}" =~ (error_tag|error_22) ]]; then
				printf '\n%b\n' " ${td}This tag that will be used is: ${cg}${github_tag[qbittorrent]}${cend}"
			fi
			printf '\n%b\n' " ${td}This flag must be provided with arguments.${cend}"
			printf '\n%b\n\n' " ${clb}-qt${cend} ${clc}${github_tag[qbittorrent]}${cend}"
			exit
			;;
		-h-s | --help-strip)
			printf '\n%b\n' " ${ulcc} ${tb}${tu}Here is the help description for this flag:${cend}"
			printf '\n%b\n' " Strip the qbittorrent-nox binary of unneeded symbols to decrease file size"
			printf '\n%b\n' " ${uyc} Static musl builds don't work with qBittorrents built in stacktrace."
			printf '\n%b\n' " If you need to debug a build with gdb you must build a debug build using the flag ${clb}-d${cend}"
			printf '\n%b\n' " ${td}This flag is provided with no arguments.${cend}"
			printf '\n%b\n\n' " ${clb}-s${cend}"
			exit
			;;
		--) # end argument parsing
			shift
			break
			;;
		-*) # unsupported flags
			printf '\n%b\n' " Error: Unsupported flag ${cr}${1}${cend} - use ${cg}-h${cend} or ${cg}--help${cend} to see the valid options$" >&2
			exit 1
			;;
		*) # preserve positional arguments
			params2+=("${1}")
			shift
			;;
	esac
done

set -- "${params2[@]}" # Set positional arguments in their proper place.
#######################################################################################################################################################
# Functions part 2: Use some of our functions
#######################################################################################################################################################
[[ "${*}" =~ ([[:space:]]|^)"install"([[:space:]]|$) ]] && install_qbittorrent "${@}" # see functions
#######################################################################################################################################################
# Lets dip out now if we find that any github tags failed validation or the urls are invalid
#######################################################################################################################################################
_error_url

_error_tag
#######################################################################################################################################################
# Functions part 3: Use some of our functions
#######################################################################################################################################################
_script_version # see functions

_debug "${@}" # see functions

_installation_modules "${@}" # see functions

_cache_dirs "${@}" # see functions

_cmake # see functions

_multi_arch # see functions
#######################################################################################################################################################
# bison installation
#######################################################################################################################################################
_application_name bison

if [[ "${!app_name_skip:-yes}" == "no" || "${1}" == "${app_name}" ]]; then
	custom_flags_set

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]]; then
		_download_folder "${app_name}"
	else
		download_file "${app_name}"
	fi

	./configure "${multi_bison[@]}" --prefix="${qbt_install_dir}" |& tee "${qbt_install_dir}/logs/${app_name}.log"
	make -j"$(nproc)" CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	post_command build

	make install |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# gawk installation
#######################################################################################################################################################
_application_name gawk

if [[ "${!app_name_skip:-yes}" == "no" || "$1" == "${app_name}" ]]; then
	custom_flags_set

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]]; then
		_download_folder "${app_name}"
	else
		download_file "${app_name}"
	fi

	./configure "${multi_gawk[@]}" --prefix="$qbt_install_dir" |& tee "${qbt_install_dir}/logs/${app_name}.log"
	make -j"$(nproc)" CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	post_command build

	make install |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	_fix_static_links "${app_name}"

	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# glibc installation
#######################################################################################################################################################
_application_name glibc

if [[ "${!app_name_skip:-yes}" == "no" || "${1}" == "${app_name}" ]]; then
	custom_flags_reset

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]]; then
		_download_folder "${app_name}"
		source_dir="${qbt_install_dir}/${app_name}"
	else
		download_file "${app_name}"
	fi

	mkdir -p build
	_pushd "${source_dir}/build"

	"${source_dir}/configure" "${multi_glibc[@]}" --prefix="${qbt_install_dir}" --enable-static-nss --disable-nscd |& tee "${qbt_install_dir}/logs/${app_name}.log"
	make -j"$(nproc)" |& tee -a "${qbt_install_dir}/logs/$app_name.log"

	post_command build

	make install |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	_fix_static_links "${app_name}"

	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# zlib installation
#######################################################################################################################################################
_application_name zlib

if [[ "${!app_name_skip:-yes}" == "no" || "${1}" == "${app_name}" ]]; then
	custom_flags_set

	if [[ "${qbt_workflow_files}" == "yes" || "${qbt_workflow_artifacts}" == "yes" ]]; then
		download_file "${app_name}"
	else
		_download_folder "${app_name}"
	fi

	if [[ "${qbt_build_tool}" == "cmake" ]]; then
		mkdir -p "${qbt_install_dir}/graphs/${app_version[zlib]}"

		# force set some ARCH when using zlib-ng, cmake and musl-cross since it does detect the arch correctly.
		[[ "${qbt_cross_target}" =~ ^(alpine)$ ]] && printf '%b\n' "\narchfound ${qbt_zlib_arch:-x86_64}" >> "${qbt_install_dir}/zlib/cmake/detect-arch.c"

		cmake -Wno-dev -Wno-deprecated --graphviz="${qbt_install_dir}/graphs/${app_version[zlib]}/dep-graph.dot" -G Ninja -B build \
			-D CMAKE_VERBOSE_MAKEFILE="${qbt_cmake_debug}" \
			-D CMAKE_CXX_STANDARD="${standard}" \
			-D CMAKE_PREFIX_PATH="${qbt_install_dir}" \
			-D BUILD_SHARED_LIBS=OFF \
			-D ZLIB_COMPAT=ON \
			-D CMAKE_INSTALL_PREFIX="${qbt_install_dir}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
		cmake --build build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

		post_command build

		cmake --install build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

		dot -Tpng -o "${qbt_install_dir}/completed/${app_name}-graph.png" "${qbt_install_dir}/graphs/${app_version[zlib]}/dep-graph.dot"
	else
		# force set some ARCH when using zlib-ng, configure and musl-cross since it does detect the arch correctly.
		[[ "${qbt_cross_target}" =~ ^(alpine)$ ]] && sed "s|  CFLAGS=\"-O2 \${CFLAGS}\"|  ARCH=${qbt_zlib_arch:-x86_64}\n  CFLAGS=\"-O2 \${CFLAGS}\"|g" -i "${qbt_install_dir}/zlib/configure"

		./configure --prefix="${qbt_install_dir}" --static --zlib-compat |& tee "${qbt_install_dir}/logs/${app_name}.log"
		make -j"$(nproc)" CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

		post_command build

		make install |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
	fi

	_fix_static_links "${app_name}"

	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# iconv installation
#######################################################################################################################################################
_application_name iconv

if [[ "${!app_name_skip:-yes}" == "no" || "${1}" == "${app_name}" ]]; then
	custom_flags_reset

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]]; then
		_download_folder "${app_name}"
		./gitsub.sh pull --depth 1
		./autogen.sh
	else
		download_file "${app_name}"
	fi

	./configure "${multi_iconv[@]}" --prefix="${qbt_install_dir}" --disable-shared --enable-static CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee "${qbt_install_dir}/logs/${app_name}.log"

	make -j"$(nproc)" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	make install |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	_fix_static_links "${app_name}"

	post_command build

	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# icu installation
#######################################################################################################################################################
_application_name icu

if [[ "${!app_name_skip:-yes}" == "no" || "${1}" == "${app_name}" ]]; then
	custom_flags_reset

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]]; then
		_download_folder "${app_name}" "/icu4c/source"
	else
		download_file "${app_name}" "/source"
	fi

	if [[ "${qbt_cross_name}" =~ ^(x86_64|armhf|armv7|aarch64)$ ]]; then
		mkdir -p "${qbt_install_dir}/${app_name}/cross"
		_pushd "${qbt_install_dir}/${app_name}/cross"
		"${qbt_install_dir}/${app_name}/source/runConfigureICU" Linux/gcc
		make -j"$(nproc)"
		_pushd "${qbt_install_dir}/${app_name}/source"
	fi

	./configure "${multi_icu[@]}" --prefix="${qbt_install_dir}" --disable-shared --enable-static --disable-samples --disable-tests --with-data-packaging=static CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee "${qbt_install_dir}/logs/${app_name}.log"

	make -j"$(nproc)" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	post_command build

	make install |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	_fix_static_links "${app_name}"

	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# openssl installation
#######################################################################################################################################################
_application_name openssl
#
if [[ "${!app_name_skip:-yes}" == "no" || "${1}" == "${app_name}" ]]; then
	custom_flags_set

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]]; then
		_download_folder "${app_name}"
	else
		download_file "${app_name}"
	fi

	"${multi_openssl[@]}" --prefix="${qbt_install_dir}" --libdir="${lib_dir}" --openssldir="/etc/ssl" threads no-shared no-dso no-comp CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" |& tee "${qbt_install_dir}/logs/${app_name}.log"
	make -j"$(nproc)" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	post_command build

	make install_sw |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

	_fix_static_links "${app_name}"

	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# boost install
#######################################################################################################################################################
_application_name boost
#
if [[ "${!app_name_skip:-yes}" == "no" ]] || [[ "${1}" == "${app_name}" ]]; then
	custom_flags_set

	[[ -d "${qbt_install_dir}/boost" ]] && delete_function "${app_name}"

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]] || [[ "${boost_url_status}" =~ (403|404) ]]; then
		_download_folder "${app_name}"
	elif [[ "${qbt_workflow_files}" == "yes" || "${qbt_workflow_artifacts}" == "yes" || "${boost_url_status}" =~ (200) ]]; then
		download_file "${app_name}"
		mv -f "${qbt_install_dir}/boost_${app_version[boost]//./_}/" "${qbt_install_dir}/boost"
		_pushd "${qbt_install_dir}/boost"
	fi

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]] || [[ "${qbt_build_tool}" != 'cmake' ]]; then
		"${qbt_install_dir}/boost/bootstrap.sh" |& tee "${qbt_install_dir}/logs/${app_name}.log"
		ln -s "${qbt_install_dir}/boost/boost" "${qbt_install_dir}/boost/include"
	else
		printf '%b\n' " ${uyc} Skipping b2 as we are using cmake"
	fi

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]] || [[ "${boost_url_status}" =~ (403|404) ]]; then
		"${qbt_install_dir}/boost/b2" headers |& tee "${qbt_install_dir}/logs/${app_name}.log"
	fi
else
	application_skip
fi
#######################################################################################################################################################
# libtorrent installation
#######################################################################################################################################################
_application_name libtorrent

if [[ "${!app_name_skip:-yes}" == "no" ]] || [[ "${1}" == "${app_name}" ]]; then
	if [[ ! -d "${qbt_install_dir}/boost" ]]; then
		printf '\n%b\n' " ${urc}${clr} Warning${cend} This module depends on the boost module. Use them together: ${clm}boost libtorrent${cend}"
	else
		custom_flags_set

		if [[ "${override_workflow}" != "yes" ]] && [[ "${qbt_workflow_files}" == "yes" || "${qbt_workflow_artifacts}" == "yes" ]]; then
			download_file "${app_name}"
		else
			_download_folder "${app_name}"
		fi

		apply_patches "${app_name}"

		BOOST_ROOT="${qbt_install_dir}/boost"
		BOOST_INCLUDEDIR="${qbt_install_dir}/boost"
		BOOST_BUILD_PATH="${qbt_install_dir}/boost"

		if [[ "${qbt_build_tool}" == 'cmake' ]]; then
			mkdir -p "${qbt_install_dir}/graphs/${github_tag[libtorrent]}"
			cmake -Wno-dev -Wno-deprecated --graphviz="${qbt_install_dir}/graphs/${github_tag[libtorrent]}/dep-graph.dot" -G Ninja -B build \
				"${multi_libtorrent[@]}" \
				-D CMAKE_VERBOSE_MAKEFILE="${qbt_cmake_debug}" \
				-D CMAKE_BUILD_TYPE="Release" \
				-D CMAKE_CXX_STANDARD="${standard}" \
				-D CMAKE_PREFIX_PATH="${qbt_install_dir};${qbt_install_dir}/boost" \
				-D Boost_NO_BOOST_CMAKE=TRUE \
				-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
				-D BUILD_SHARED_LIBS=OFF \
				-D Iconv_LIBRARY="${lib_dir}/libiconv.a" \
				-D CMAKE_INSTALL_PREFIX="${qbt_install_dir}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
			cmake --build build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

			post_command build

			cmake --install build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

			dot -Tpng -o "${qbt_install_dir}/completed/${app_name}-graph.png" "${qbt_install_dir}/graphs/${github_tag[libtorrent]}/dep-graph.dot"
		else
			[[ ${qbt_cross_name} =~ ^(armhf|armv7)$ ]] && arm_libatomic="-l:libatomic.a"

			# Check the actual version of the cloned libtorrent instead of using the tag so that we can determine RC_1_1, RC_1_2 or RC_2_0 when a custom pr branch was used. This will always give an accurate result.
			libtorrent_version_hpp="$(sed -rn 's|(.*)LIBTORRENT_VERSION "(.*)"|\2|p' include/libtorrent/version.hpp)"

			if [[ "${libtorrent_version_hpp}" =~ ^1\.1\. ]]; then
				libtorrent_library_filename="libtorrent.a"
			else
				libtorrent_library_filename="libtorrent-rasterbar.a"
			fi

			if [[ "${libtorrent_version_hpp}" =~ ^2\. ]]; then
				lt_version_options=()
				libtorrent_libs="-l:libboost_system.a -l:${libtorrent_library_filename} -l:libtry_signal.a ${arm_libatomic}"
				lt_cmake_flags="-DTORRENT_USE_LIBCRYPTO -DTORRENT_USE_OPENSSL -DTORRENT_USE_I2P=1 -DBOOST_ALL_NO_LIB -DBOOST_ASIO_ENABLE_CANCELIO -DBOOST_ASIO_HAS_STD_CHRONO -DBOOST_MULTI_INDEX_DISABLE_SERIALIZATION -DBOOST_SYSTEM_NO_DEPRECATED -DBOOST_SYSTEM_STATIC_LINK=1 -DTORRENT_SSL_PEERS -DBOOST_ASIO_NO_DEPRECATED"
			else
				lt_version_options=("iconv=on")
				libtorrent_libs="-l:libboost_system.a -l:${libtorrent_library_filename} ${arm_libatomic} -l:libiconv.a"
				lt_cmake_flags="-DTORRENT_USE_LIBCRYPTO -DTORRENT_USE_OPENSSL -DTORRENT_USE_I2P=1 -DBOOST_ALL_NO_LIB -DBOOST_ASIO_ENABLE_CANCELIO -DBOOST_ASIO_HAS_STD_CHRONO -DBOOST_MULTI_INDEX_DISABLE_SERIALIZATION -DBOOST_SYSTEM_NO_DEPRECATED -DBOOST_SYSTEM_STATIC_LINK=1 -DTORRENT_USE_ICONV=1"
			fi
			#
			"${qbt_install_dir}/boost/b2" "${multi_libtorrent[@]}" -j"$(nproc)" "${lt_version_options[@]}" address-model="$(getconf LONG_BIT)" "${qbt_libtorrent_debug}" optimization=speed cxxstd="${standard}" dht=on encryption=on crypto=openssl i2p=on extensions=on variant=release threading=multi link=static boost-link=static cxxflags="${CXXFLAGS}" cflags="${CPPFLAGS}" linkflags="${LDFLAGS}" install --prefix="${qbt_install_dir}" |& tee "${qbt_install_dir}/logs/${app_name}.log"
			#
			post_command build
			#
			libtorrent_strings_version="$(strings -d "${lib_dir}/${libtorrent_library_filename}" | grep -Eom1 "^libtorrent/[0-9]\.(.*)")" # ${libtorrent_strings_version#*/}
			#
			cat > "${PKG_CONFIG_PATH}/libtorrent-rasterbar.pc" <<- LIBTORRENT_PKG_CONFIG
				prefix=${qbt_install_dir}
				libdir=\${prefix}/lib
				includedir=\${prefix}/include

				Name: libtorrent-rasterbar
				Description: The libtorrent-rasterbar libraries
				Version: ${libtorrent_strings_version#*/}

				Requires:
				Libs: -L\${libdir} ${libtorrent_libs}
				Cflags: -I\${includedir} -I${BOOST_ROOT} ${lt_cmake_flags}
			LIBTORRENT_PKG_CONFIG
		fi
		#
		_fix_static_links "${app_name}"
		#
		delete_function "${app_name}"
	fi
else
	application_skip
fi
#######################################################################################################################################################
# double conversion installation
#######################################################################################################################################################
_application_name double_conversion

if [[ "${!app_name_skip:-yes}" == "no" || "${1}" == "${app_name}" ]]; then
	custom_flags_set

	if [[ "${qbt_workflow_files}" == "yes" || "${qbt_workflow_artifacts}" == "yes" ]]; then
		download_file "${app_name}"
	else
		_download_folder "${app_name}"
	fi

	if [[ "${qbt_build_tool}" == 'cmake' && "${qbt_qt_version}" =~ ^6 ]]; then
		cmake -Wno-dev -Wno-deprecated --graphviz="${qbt_install_dir}/graphs/${github_tag[double_conversion]}/dep-graph.dot" -G Ninja -B build \
			"${multi_libtorrent[@]}" \
			-D CMAKE_VERBOSE_MAKEFILE="${qbt_cmake_debug}" \
			-D CMAKE_PREFIX_PATH="${qbt_install_dir}" \
			-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
			-D CMAKE_INSTALL_LIBDIR=lib \
			-D BUILD_SHARED_LIBS=OFF \
			-D CMAKE_INSTALL_PREFIX="${qbt_install_dir}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
		cmake --build build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
		cmake --install build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
		post_command build
		dot -Tpng -o "${qbt_install_dir}/completed/${app_name}-graph.png" "${qbt_install_dir}/graphs/${github_tag[double_conversion]}/dep-graph.dot"
	fi

	_fix_static_links "${app_name}"
	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# qtbase installation
#######################################################################################################################################################
_application_name qtbase

if [[ "${!app_name_skip:-yes}" == "no" ]] || [[ "${1}" == "${app_name}" ]]; then
	custom_flags_set

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]]; then
		_download_folder "${app_name}"
	else
		download_file "${app_name}"
	fi

	case "${qbt_cross_name}" in
		armhf | armv7)
			sed "s|arm-linux-gnueabi|${qbt_cross_host}|g" -i "mkspecs/linux-arm-gnueabi-g++/qmake.conf"
			;;
		aarch64)
			sed "s|aarch64-linux-gnu|${qbt_cross_host}|g" -i "mkspecs/linux-aarch64-gnu-g++/qmake.conf"
			;;
	esac

	if [[ "${qbt_build_tool}" == 'cmake' && "${qbt_qt_version}" =~ ^6 ]]; then
		mkdir -p "${qbt_install_dir}/graphs/${github_tag[libtorrent]}"
		cmake -Wno-dev -Wno-deprecated --graphviz="${qbt_install_dir}/graphs/${app_version[qtbase]}/dep-graph.dot" -G Ninja -B build \
			"${multi_libtorrent[@]}" \
			-D CMAKE_VERBOSE_MAKEFILE="${qbt_cmake_debug}" \
			-D CMAKE_BUILD_TYPE="release" \
			-D QT_FEATURE_optimize_full=on -D QT_FEATURE_static=on -D QT_FEATURE_shared=off \
			-D QT_FEATURE_gui=off -D QT_FEATURE_openssl_linked=on \
			-D QT_FEATURE_dbus=off -D QT_FEATURE_system_pcre2=off -D QT_FEATURE_widgets=off \
			-D QT_FEATURE_testlib=off -D QT_BUILD_EXAMPLES=off -D QT_BUILD_TESTS=off \
			-D CMAKE_CXX_STANDARD="${standard}" \
			-D CMAKE_PREFIX_PATH="${qbt_install_dir}" \
			-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
			-D BUILD_SHARED_LIBS=OFF \
			-D CMAKE_SKIP_RPATH=on -D CMAKE_SKIP_INSTALL_RPATH=on \
			-D CMAKE_INSTALL_PREFIX="${qbt_install_dir}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
		cmake --build build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

		post_command build

		cmake --install build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

		dot -Tpng -o "${qbt_install_dir}/completed/${app_name}-graph.png" "${qbt_install_dir}/graphs/${app_version[qtbase]}/dep-graph.dot"
	elif [[ "${qbt_qt_version}" =~ ^5 ]]; then
		if [[ "${qbt_skip_icu}" == "no" ]]; then
			icu=("-icu" "-no-iconv" "QMAKE_CXXFLAGS=-w -fpermissive")
		else
			icu=("-no-icu" "-iconv" "QMAKE_CXXFLAGS=-w -fpermissive")
		fi

		# Fix 5.15.4 to build on gcc 11
		sed '/^#  include <utility>/a #  include <limits>' -i "src/corelib/global/qglobal.h"

		# Don't strip by default by disabling these options. We will set it as off by default and use it with a switch
		printf '%b\n' "CONFIG                 += ${qbt_strip_qmake}" >> "mkspecs/common/linux.conf"

		./configure "${multi_qtbase[@]}" -prefix "${qbt_install_dir}" "${icu[@]}" -opensource -confirm-license -release \
			-openssl-linked -static -c++std "${cxx_standard}" -qt-pcre \
			-no-feature-glib -no-feature-opengl -no-feature-dbus -no-feature-gui -no-feature-widgets -no-feature-testlib -no-compile-examples \
			-skip tests -nomake tests -skip examples -nomake examples \
			-I "${include_dir}" -L "${lib_dir}" QMAKE_LFLAGS="${LDFLAGS}" |& tee "${qbt_install_dir}/logs/${app_name}.log"
		make -j"$(nproc)" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

		post_command build

		make install |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
	else
		printf '\n%b\n' " ${urc} Please use a correct qt and build tool combination"
		printf '\n%b\n\n' " ${urc} ${utick} qt5 + qmake ${utick} qt6 + cmake ${ucross} qt5 + cmake ${ucross} qt6 + qmake"
		exit 1
	fi

	_fix_static_links "${app_name}"

	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# qttools installation
#######################################################################################################################################################
_application_name qttools
#
if [[ "${!app_name_skip:-yes}" == "no" ]] || [[ "${1}" == "${app_name}" ]]; then
	custom_flags_set

	if [[ -n "${qbt_cache_dir}" && -d "${qbt_cache_dir}/${app_name}" ]]; then
		_download_folder "${app_name}"
	else
		download_file "${app_name}"
	fi

	if [[ "${qbt_build_tool}" == 'cmake' && "${qbt_qt_version}" =~ ^6 ]]; then
		mkdir -p "${qbt_install_dir}/graphs/${github_tag[libtorrent]}"
		cmake -Wno-dev -Wno-deprecated --graphviz="${qbt_install_dir}/graphs/${app_version[qttools]}/dep-graph.dot" -G Ninja -B build \
			"${multi_libtorrent[@]}" \
			-D CMAKE_VERBOSE_MAKEFILE="${qbt_cmake_debug}" \
			-D CMAKE_BUILD_TYPE="release" \
			-D CMAKE_CXX_STANDARD="${standard}" \
			-D CMAKE_PREFIX_PATH="${qbt_install_dir}" \
			-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
			-D BUILD_SHARED_LIBS=OFF \
			-D CMAKE_SKIP_RPATH=on -D CMAKE_SKIP_INSTALL_RPATH=on \
			-D CMAKE_INSTALL_PREFIX="${qbt_install_dir}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
		cmake --build build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

		post_command build

		cmake --install build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

		dot -Tpng -o "${qbt_install_dir}/completed/${app_name}-graph.png" "${qbt_install_dir}/graphs/${app_version[qttools]}/dep-graph.dot"
	elif [[ "${qbt_qt_version}" =~ ^5 ]]; then
		"${qbt_install_dir}/bin/qmake" -set prefix "${qbt_install_dir}" |& tee "${qbt_install_dir}/logs/${app_name}.log"

		"${qbt_install_dir}/bin/qmake" QMAKE_CXXFLAGS="-std=${cxx_standard} -static -w -fpermissive" QMAKE_LFLAGS="-static" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
		make -j"$(nproc)" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

		post_command build

		make install |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
	else
		printf '\n%b\n' " ${urc} Please use a correct qt and build tool combination"
		printf '\n%b\n' " ${urc} ${utick} qt5 + qmake ${utick} qt6 + cmake ${ucross} qt5 + cmake ${ucross} qt6 + qmake"
		exit 1
	fi
	_fix_static_links "${app_name}"

	delete_function "${app_name}"
else
	application_skip
fi
#######################################################################################################################################################
# qBittorrent installation
#######################################################################################################################################################
_application_name qbittorrent

if [[ "${!app_name_skip:-yes}" == "no" ]] || [[ "${1}" == "${app_name}" ]]; then
	if [[ ! -d "${qbt_install_dir}/boost" ]]; then
		printf '\n%b\n\n' " ${urc}${clr} Warning${cend} This module depends on the boost module. Use them together: ${clm}boost qbittorrent${cend}"
	else
		custom_flags_set

		if [[ "${override_workflow}" != "yes" ]] && [[ "${qbt_workflow_files}" == "yes" || "${qbt_workflow_artifacts}" == "yes" ]]; then
			download_file "${app_name}"
		else
			_download_folder "${app_name}"
		fi

		apply_patches "${app_name}"

		[[ "${what_id}" =~ ^(alpine)$ ]] && stacktrace="OFF"

		if [[ "${qbt_build_tool}" == 'cmake' ]]; then
			mkdir -p "${qbt_install_dir}/graphs/${github_tag[qbittorrent]#release-}"
			cmake -Wno-dev -Wno-deprecated --graphviz="${qbt_install_dir}/graphs/${github_tag[qbittorrent]#release-}/dep-graph.dot" -G Ninja -B build \
				"${multi_qbittorrent[@]}" \
				-D CMAKE_VERBOSE_MAKEFILE="${qbt_cmake_debug}" \
				-D CMAKE_BUILD_TYPE="release" \
				-D QT6="${qbt_use_qt6}" \
				-D STACKTRACE="${stacktrace:-ON}" \
				-D CMAKE_CXX_STANDARD="${standard}" \
				-D CMAKE_PREFIX_PATH="${qbt_install_dir};${qbt_install_dir}/boost" \
				-D Boost_NO_BOOST_CMAKE=TRUE \
				-D CMAKE_CXX_FLAGS="${CXXFLAGS}" \
				-D Iconv_LIBRARY="${lib_dir}/libiconv.a" \
				-D GUI=OFF \
				-D CMAKE_INSTALL_PREFIX="${qbt_install_dir}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
			cmake --build build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

			post_command build

			cmake --install build |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

			dot -Tpng -o "${qbt_install_dir}/completed/${app_name}-graph.png" "${qbt_install_dir}/graphs/${github_tag[qbittorrent]#release-}/dep-graph.dot"
		else
			./bootstrap.sh |& tee "${qbt_install_dir}/logs/${app_name}.log"
			./configure \
				QT_QMAKE="${qbt_install_dir}/bin" \
				--prefix="${qbt_install_dir}" \
				"${multi_qbittorrent[@]}" \
				"${qbt_qbittorrent_debug}" \
				--disable-gui \
				CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" \
				--with-boost="${qbt_install_dir}/boost" --with-boost-libdir="${lib_dir}" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
			make -j"$(nproc)" |& tee -a "${qbt_install_dir}/logs/${app_name}.log"

			post_command build

			make install |& tee -a "${qbt_install_dir}/logs/${app_name}.log"
		fi

		[[ -f "${qbt_install_dir}/bin/qbittorrent-nox" ]] && cp -f "${qbt_install_dir}/bin/qbittorrent-nox" "${qbt_install_dir}/completed/qbittorrent-nox"

		_application_name boost && delete_function boost
		_application_name qbittorrent && delete_function "${app_name}" last
	fi
else
	application_skip last
fi
#######################################################################################################################################################
# We are all done so now exit
#######################################################################################################################################################
exit
