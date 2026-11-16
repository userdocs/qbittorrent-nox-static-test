#!/bin/bash
#
# Unit tests for qbt-nox-static.bash (all core features except module building)
#
# shellcheck disable=SC2034,SC2154

set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
target_script="${repo_root}/qbt-nox-static.bash"

if [[ ! -f ${target_script} ]]; then
	printf 'ERROR: Target script not found: %s\n' "${target_script}" >&2
	exit 1
fi

test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT

# Extract all declarations and function definitions from qbt-nox-static.bash (stopping before option loop 1)
# and replace the live OS check so functions can be unit-tested deterministically on any Linux host.
lib_file="${test_root}/qbt_lib.bash"
awk '
	/^# Checks to see if we are on a supported OS and release\./ { skip = 1; next }
	/^# Multi arch stuff/ { skip = 0 }
	/^# This is first help section/ { exit }
	!skip { print }
' "${target_script}" > "${lib_file}"

# Remove top-level ctest side effect when sourcing the function library
sed -i 's/^\[\[ \${1} == "ctest" \]\] && _color_test.*/:/' "${lib_file}"

passed=0
failed=0
declare -a failed_names=()

pass() {
	((passed++))
	printf '  [PASS] %s\n' "${1}"
}

fail() {
	((failed++))
	failed_names+=("${1}")
	printf '  [FAIL] %s: %s\n' "${1}" "${2:-assertion failed}" >&2
}

assert_eq() {
	local name="${1}" expected="${2}" actual="${3}"
	if [[ ${actual} == "${expected}" ]]; then
		pass "${name}"
	else
		fail "${name}" "expected '${expected}', got '${actual}'"
	fi
}

assert_contains() {
	local name="${1}" haystack="${2}" needle="${3}"
	if [[ ${haystack} == *"${needle}"* ]]; then
		pass "${name}"
	else
		fail "${name}" "expected output to contain '${needle}', got '${haystack}'"
	fi
}

assert_not_contains() {
	local name="${1}" haystack="${2}" needle="${3}"
	if [[ ${haystack} != *"${needle}"* ]]; then
		pass "${name}"
	else
		fail "${name}" "expected output NOT to contain '${needle}', got '${haystack}'"
	fi
}

assert_exit() {
	local name="${1}" expected="${2}" actual="${3}"
	if [[ ${actual} -eq ${expected} ]]; then
		pass "${name}"
	else
		fail "${name}" "expected exit code ${expected}, got ${actual}"
	fi
}

# Load the extracted function library with controlled mock OS variables inside a subshell
load_lib() {
	local mock_os_id="${1:-ubuntu}"
	local mock_codename="${2:-resolute}"
	local mock_version="${3:-26.04}"
	local mock_arch="${4:-amd64}"

	# shellcheck source=/dev/null
	source "${lib_file}"
	os_id="${mock_os_id}"
	os_version_codename="${mock_codename}"
	os_version_id="${mock_version}"
	os_arch="${mock_arch}"
	script_full_path="${test_root}/qbt-nox-static.bash"
	script_parent_path="${test_root}"
	script_basename="qbt-nox-static.bash"
}

# Build a CLI test copy of qbt-nox-static.bash with mocked /etc/os-release and optional offline stubs
make_cli_copy() {
	local dest_dir="${1}"
	local os_id_val="${2:-ubuntu}"
	local codename_val="${3:-resolute}"
	local version_val="${4:-26.04}"
	local offline_stubs="${5:-no}"

	mkdir -p "${dest_dir}"
	cat > "${dest_dir}/mock_os_release" <<- EOF
		ID=${os_id_val}
		VERSION_CODENAME=${codename_val}
		VERSION_ID=${version_val}
	EOF

	cp "${target_script}" "${dest_dir}/qbt-nox-static.bash"
	sed -i "s|source /etc/os-release|source \"${dest_dir}/mock_os_release\"|g" "${dest_dir}/qbt-nox-static.bash"

	if [[ ${os_id_val} == "alpine" ]]; then
		sed -i 's|apk --print-arch|printf "%s" "x86_64"|g' "${dest_dir}/qbt-nox-static.bash"
		sed -i 's|apk version -t "\${os_version_id}" "3.18"|printf "%s" ">"|g' "${dest_dir}/qbt-nox-static.bash"
	else
		sed -i 's|dpkg --print-architecture|printf "%s" "amd64"|g' "${dest_dir}/qbt-nox-static.bash"
	fi

	if [[ ${offline_stubs} == "yes" ]]; then
		awk '
			/^_check_dependencies "\$\{@\}"/ {
				print "filtered_check_dependency_args=(\"$@\")"
				print "_test_url() { test_url_status=\"200\"; }"
				print "_script_version() { return 0; }"
				print "_curl() { return 1; }"
				print "_git_git() { return 1; }"
				print "_set_module_urls() {"
				print "  github_url[glibc]=\"https://sourceware.org/git/glibc.git\""
				print "  github_url[zlib]=\"https://github.com/madler/zlib.git\""
				print "  github_url[iconv]=\"https://https.git.savannah.gnu.org/git/libiconv.git\""
				print "  github_url[icu]=\"https://github.com/unicode-org/icu.git\""
				print "  github_url[openssl]=\"https://github.com/openssl/openssl.git\""
				print "  github_url[boost]=\"https://github.com/boostorg/boost.git\""
				print "  github_url[libtorrent]=\"https://github.com/arvidn/libtorrent.git\""
				print "  github_url[qtbase]=\"https://github.com/qt/qtbase.git\""
				print "  github_url[qttools]=\"https://github.com/qt/qttools.git\""
				print "  github_url[qbittorrent]=\"https://github.com/qbittorrent/qBittorrent.git\""
				print "  github_tag[glibc]=\"glibc-2.44\"; app_version[glibc]=\"2.44\""
				print "  github_tag[zlib]=\"v1.3.2\"; app_version[zlib]=\"1.3.2\""
				print "  github_tag[iconv]=\"v1.19\"; app_version[iconv]=\"1.19\""
				print "  github_tag[icu]=\"release-76-1\"; app_version[icu]=\"76-1\""
				print "  github_tag[openssl]=\"openssl-3.5.9\"; app_version[openssl]=\"3.5.9\""
				print "  github_tag[boost]=\"boost-1.88.0\"; app_version[boost]=\"1.88.0\""
				print "  github_tag[libtorrent]=\"v2.0.11\"; app_version[libtorrent]=\"2.0.11\""
				print "  github_tag[qtbase]=\"v6.8.2\"; app_version[qtbase]=\"6.8.2\""
				print "  github_tag[qttools]=\"v6.8.2\"; app_version[qttools]=\"6.8.2\""
				print "  github_tag[qbittorrent]=\"release-5.1.0\"; app_version[qbittorrent]=\"5.1.0\""
				print "  qt_version_short_array=(6 8); qt_version_short=\"6.8\""
				print "  source_default[openssl]=\"file\"; source_default[boost]=\"file\""
				print "  source_default[libtorrent]=\"file\"; source_default[qtbase]=\"file\""
				print "  source_default[qttools]=\"file\"; source_default[qbittorrent]=\"file\""
				print "}"
				print "set -- \"${filtered_check_dependency_args[@]}\""
				next
			}
			{ print }
		' "${dest_dir}/qbt-nox-static.bash" > "${dest_dir}/qbt-nox-static.bash.tmp"
		mv "${dest_dir}/qbt-nox-static.bash.tmp" "${dest_dir}/qbt-nox-static.bash"
	fi

	chmod +x "${dest_dir}/qbt-nox-static.bash"
}

printf '\n=== 1. Semantic Version Tests ===\n'
(
	load_lib
	assert_eq "semver strips v prefix" "$(_semantic_version "1.2.20")" "$(_semantic_version "v1.2.20")"
	assert_eq "semver strips release- prefix" "$(_semantic_version "5.1.0")" "$(_semantic_version "release-5.1.0")"
	assert_eq "semver strips boost- prefix" "$(_semantic_version "1.88.0")" "$(_semantic_version "boost-1.88.0")"
	assert_eq "semver strips openssl- prefix" "$(_semantic_version "3.5.9")" "$(_semantic_version "openssl-3.5.9")"
	assert_eq "semver strips libtorrent- prefix" "$(_semantic_version "1.2.20")" "$(_semantic_version "libtorrent-1_2_20")"
	assert_eq "semver strips libtorrent_ prefix" "$(_semantic_version "1.2.20")" "$(_semantic_version "libtorrent_1_2_20")"
	assert_eq "semver strips glibc- prefix" "$(_semantic_version "2.44")" "$(_semantic_version "glibc-2.44")"
	assert_eq "semver RC_1_2 elevates to 1.2.999" "$(_semantic_version "1.2.999")" "$(_semantic_version "RC_1_2")"
	assert_eq "semver v5_1_x elevates to 5.1.999" "$(_semantic_version "5.1.999")" "$(_semantic_version "v5_1_x")"
	assert_eq "semver master/main/latest equal max" "$(_semantic_version "master")" "$(_semantic_version "MAIN")"
	assert_eq "semver latest equals master" "$(_semantic_version "master")" "$(_semantic_version "latest")"

	v_alpha="$(_semantic_version "2.1.0-alpha1")"
	v_beta="$(_semantic_version "boost-2.1.0.beta1")"
	v_rc="$(_semantic_version "2.1.0_rc2")"
	v_final="$(_semantic_version "2.1.0")"
	if ((v_alpha < v_beta && v_beta < v_rc && v_rc < v_final)); then
		pass "semver prerelease ordering alpha < beta < rc < final"
	else
		fail "semver prerelease ordering" "got alpha=${v_alpha} beta=${v_beta} rc=${v_rc} final=${v_final}"
	fi

	v_octal="$(_semantic_version "0.8.9")"
	v_higher="$(_semantic_version "0.9.0")"
	if [[ ${v_octal} -lt ${v_higher} ]]; then
		pass "semver handles leading zero and 8/9 without octal errors"
	else
		fail "semver octal safety" "${v_octal} not < ${v_higher}"
	fi

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 2. C++ Standard Resolution & Iconv Check Tests ===\n'
(
	load_lib "ubuntu" "resolute" "26.04" "amd64"

	github_tag[libtorrent]="v1.2.18"
	app_version[libtorrent]="1.2.18"
	github_tag[qbittorrent]="release-4.5.2"
	app_version[qbittorrent]="4.5.2"
	qbt_qt_version="5.15"
	_set_cxx_standard
	assert_eq "cxx standard lt 1.2.18 + qbt 4.5.2 + qt 5.15 = 17" "17" "${qbt_standard}"

	github_tag[libtorrent]="v1.2.20"
	app_version[libtorrent]="1.2.20"
	github_tag[qbittorrent]="release-5.1.0"
	app_version[qbittorrent]="5.1.0"
	qbt_qt_version="6.8"
	_set_cxx_standard
	assert_eq "cxx standard lt 1.2.20 + qbt 5.1.0 + qt 6.8 = 20" "20" "${qbt_standard}"

	github_tag[libtorrent]="RC_2_1"
	app_version[libtorrent]="RC_2_1"
	github_tag[qbittorrent]="master"
	app_version[qbittorrent]="master"
	qbt_qt_version="6"
	_set_cxx_standard
	assert_eq "cxx standard RC_2_1 + master + qt 6 = 23" "23" "${qbt_standard}"

	github_tag[libtorrent]="custom-feature-branch"
	app_version[libtorrent]="custom-feature-branch"
	github_tag[qbittorrent]="release-4.3.2"
	app_version[qbittorrent]="4.3.2"
	qbt_qt_version="6"
	_set_cxx_standard
	assert_eq "cxx standard non-numeric custom branch uses default 17 (not 14)" "17" "${qbt_standard}"

	# Incompatible combo: Qt5 (cap 17) vs qbt 5.1.0 (floor 20)
	release_info_dir="${test_root}/rel_incompat"
	mkdir -p "${release_info_dir}"
	github_tag[libtorrent]="v2.0.11"
	app_version[libtorrent]="2.0.11"
	github_tag[qbittorrent]="release-5.1.0"
	app_version[qbittorrent]="5.1.0"
	qbt_qt_version="5.15"
	(_set_cxx_standard > /dev/null 2>&1)
	rc=$?
	assert_exit "cxx standard incompatible Qt5 + qbt 5.1 exits 1" 1 "${rc}"
	if [[ -f "${release_info_dir}/disable-qt5" ]]; then
		pass "cxx standard touches release_info_dir/disable-qt5 on conflict"
	else
		fail "cxx standard disable-qt5" "marker file not created"
	fi

	# _libtorrent_v2_iconv_check
	qbt_libtorrent_version="1.2"
	github_tag[libtorrent]="v1.2.20"
	_libtorrent_v2_iconv_check
	assert_eq "iconv kept for libtorrent 1.2" "" "${qbt_modules_delete[iconv]:-}"

	qbt_libtorrent_version="2.1"
	github_tag[libtorrent]="v2.1.0"
	_libtorrent_v2_iconv_check
	assert_eq "iconv deleted for libtorrent 2.1" "true" "${qbt_modules_delete[iconv]:-}"

	qbt_libtorrent_version="2.0"
	github_tag[libtorrent]="RC_1_2"
	_libtorrent_v2_iconv_check
	assert_eq "iconv kept when github_tag is RC_1_2" "" "${qbt_modules_delete[iconv]:-}"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 3. Default Values & Build Directory Tests ===\n'
(
	# Default cmake + qt6
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values
		assert_eq "default build tool is cmake" "cmake" "${qbt_build_tool}"
		assert_eq "default qt version is 6" "6" "${qbt_qt_version}"
		assert_eq "default use_qt6 is ON" "ON" "${qbt_use_qt6}"
		assert_eq "default libtorrent version is 2.1" "2.1" "${qbt_libtorrent_version}"
		assert_eq "default ubuntu LTO is yes" "yes" "${qbt_use_lto}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# Absolute -b path and ~ expansion
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_build_dir="/tmp/custom-abs-build/"
		# shellcheck disable=SC2088
		qbt_cache_dir="~/my-cache/"
		_set_default_values
		assert_eq "absolute qbt_build_dir not prefixed with pwd" "/tmp/custom-abs-build" "${qbt_install_dir}"
		assert_eq "alpine qbt_mcm_dir matches absolute install dir" "/tmp/custom-abs-build" "${qbt_mcm_dir}"
		assert_eq "alpine qbt_cross_tool_dir matches absolute install dir" "/tmp/custom-abs-build/bin" "${qbt_cross_tool_dir}"
		assert_eq "qbt_host_deps_path matches absolute install dir" "/tmp/custom-abs-build/host_deps" "${qbt_host_deps_path}"
		assert_eq "tilde expanded in qbt_cache_dir" "${HOME}/my-cache" "${qbt_cache_dir}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# CLI -c overrides qt5 and CLI -q overrides qt6
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_qt_version="5.15"
		qbt_build_tool="cmake"
		qbt_build_tool_cli="cmake"
		_set_default_values
		assert_eq "CLI -c overrides qbt_qt_version=5.15 to cmake" "cmake" "${qbt_build_tool}"
		assert_eq "CLI -c upgrades qbt_qt_version=5.15 to 6" "6" "${qbt_qt_version}"
		assert_eq "CLI -c sets qbt_use_qt6=ON" "ON" "${qbt_use_qt6}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_qt_version="6"
		qbt_build_tool="qmake"
		qbt_build_tool_cli="qmake"
		_set_default_values
		assert_eq "CLI -q overrides qbt_qt_version=6 to qmake" "qmake" "${qbt_build_tool}"
		assert_eq "CLI -q switches qbt_qt_version=6 to 5" "5" "${qbt_qt_version}"
		assert_eq "CLI -q sets qbt_use_qt6=OFF" "OFF" "${qbt_use_qt6}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# Native qbt_with_qemu=no deletes *_host_deps; cross qbt_with_qemu=no + positional icu keeps icu_host_deps
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="default"
		qbt_with_qemu="no"
		_set_default_values
		assert_eq "native qbt_with_qemu=no deletes icu_host_deps" "true" "${qbt_modules_delete[icu_host_deps]:-}"
		assert_eq "native qbt_with_qemu=no deletes qtbase_host_deps" "true" "${qbt_modules_delete[qtbase_host_deps]:-}"
		assert_eq "native qbt_with_qemu=no deletes qttools_host_deps" "true" "${qbt_modules_delete[qttools_host_deps]:-}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="aarch64"
		qbt_with_qemu="no"
		_set_default_values icu > /dev/null
		assert_eq "cross qbt_with_qemu=no positional icu keeps icu_host_deps" "" "${qbt_modules_delete[icu_host_deps]:-}"
		assert_eq "cross qbt_with_qemu=no positional icu sets qbt_skip_icu=no" "no" "${qbt_skip_icu}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# Debug disables strip and LTO; Alpine LTO depends on mcm url
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_cross_name="aarch64"
		qbt_mcm_url="userdocs/qbt-musl-cross-make"
		_set_default_values > /dev/null
		assert_eq "alpine cross with qbt-musl-cross-make disables LTO" "no" "${qbt_use_lto}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_cross_name="aarch64"
		qbt_mcm_url="userdocs/musl-cross-make"
		_set_default_values > /dev/null
		assert_eq "alpine cross with musl-cross-make enables LTO" "yes" "${qbt_use_lto}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_build_debug="yes"
		_set_default_values
		assert_eq "debug disables strip" "no" "${qbt_optimise_strip}"
		assert_eq "debug disables LTO" "no" "${qbt_use_lto}"
		assert_eq "debug sets CMAKE_BUILD_TYPE=Debug" "Debug" "${qbt_cmake_build_type}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# Cross + static-ish and Cross + optimise must fail
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="aarch64"
		qbt_static_ish="yes"
		_set_default_values > /dev/null 2>&1
	)
	assert_exit "cross + qbt_static_ish=yes exits 1" 1 "$?"

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="aarch64"
		qbt_optimise="yes"
		_set_default_values > /dev/null 2>&1
	)
	assert_exit "cross + qbt_optimise=yes exits 1" 1 "$?"

	# _set_build_directory updates HOME, PATH, PKG_CONFIG_PATH, include_dir, lib_dir
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		orig_home="${HOME}"
		qbt_working_dir="${test_root}/wd"
		qbt_working_dir_short="${qbt_working_dir}"
		qbt_local_paths="/usr/bin:/bin"
		qbt_build_dir="${test_root}/my-build/"
		_set_build_directory
		assert_eq "_set_build_directory strips trailing slash" "${test_root}/my-build" "${qbt_install_dir}"
		assert_eq "_set_build_directory sets HOME to install dir" "${test_root}/my-build" "${HOME}"
		assert_eq "_set_build_directory preserves LOCAL_USER_HOME" "${orig_home}" "${LOCAL_USER_HOME}"
		assert_eq "_set_build_directory sets PKG_CONFIG_PATH" "${test_root}/my-build/lib/pkgconfig" "${PKG_CONFIG_PATH}"
		assert_eq "_set_build_directory prepends install/bin to PATH" "${test_root}/my-build/bin:/usr/bin:/bin" "${PATH}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 4. Compiler & Linker Flags (_custom_flags) Tests ===\n'
(
	load_lib "ubuntu" "resolute" "26.04" "amd64"
	qbt_build_debug="no"
	qbt_optimise_strip="yes"
	qbt_use_lto="yes"
	qbt_linker_mold="yes"
	qbt_static_ish="no"
	qbt_optimise="no"
	qbt_standard="20"
	qbt_cross_name="riscv64"
	qbt_cross_host="riscv64-linux-gnu"
	qbt_cross_tool_dir="/usr/bin"
	qbt_build_tool="cmake"
	include_dir="${test_root}/build/include"
	lib_dir="${test_root}/build/lib"
	app_version[glibc]="2.44"
	CFLAGS="-DUSER_CFLAG"
	CXXFLAGS=""
	CPPFLAGS=""
	LDFLAGS="-Wl,--user-ld"

	# Normal module (zlib) on Debian/Ubuntu static build
	app_name="zlib"
	_custom_flags
	assert_contains "zlib Debian static CFLAGS has -B lib_dir" "${CFLAGS}" "-B${lib_dir}"
	assert_contains "zlib Debian static LDFLAGS has -B lib_dir" "${LDFLAGS}" "-B${lib_dir}"
	assert_contains "zlib CFLAGS keeps -fno-plt" "${CFLAGS}" "-fno-plt"
	assert_contains "zlib CFLAGS keeps -flto=auto" "${CFLAGS}" "-flto=auto"
	assert_contains "zlib LDFLAGS has -fuse-ld=mold" "${LDFLAGS}" "-fuse-ld=mold"
	assert_contains "zlib CFLAGS appends user CFLAGS" "${CFLAGS}" "-DUSER_CFLAG"
	assert_not_contains "glibc 2.44 omits -D_FORTIFY_SOURCE=3" "${CPPFLAGS}" "-D_FORTIFY_SOURCE=3"
	assert_eq "cross zlib AR uses cross gcc-ar" "/usr/bin/riscv64-linux-gnu-gcc-ar" "${AR}"
	assert_eq "cross zlib CC uses cross gcc" "/usr/bin/riscv64-linux-gnu-gcc" "${CC}"

	# Calling _custom_flags again must NOT duplicate user CFLAGS
	_custom_flags
	cflag_count="$(printf '%s' "${CFLAGS}" | grep -o -- '-DUSER_CFLAG' | wc -l)"
	assert_eq "user CFLAGS not duplicated across _custom_flags calls" "1" "${cflag_count}"

	# glibc must exclude -fno-plt, LTO, -B lib_dir, and reset stale LDFLAGS from zlib
	app_name="glibc"
	_custom_flags
	assert_not_contains "glibc CFLAGS excludes -fno-plt" "${CFLAGS}" "-fno-plt"
	assert_not_contains "glibc CXXFLAGS excludes -fno-plt" "${CXXFLAGS}" "-fno-plt"
	assert_not_contains "glibc CFLAGS excludes -flto" "${CFLAGS}" "-flto"
	assert_not_contains "glibc CFLAGS excludes -B lib_dir" "${CFLAGS}" "-B${lib_dir}"
	assert_eq "glibc resets LDFLAGS to user qbt_ldflags only" "-Wl,--user-ld" "${LDFLAGS}"
	assert_eq "glibc AR uses non-LTO cross ar" "/usr/bin/riscv64-linux-gnu-ar" "${AR}"

	# *_host_deps must use host /usr/bin/gcc-* LTO wrappers and omit -B lib_dir
	app_name="qtbase_host_deps"
	_custom_flags
	assert_eq "host_deps CC uses /usr/bin/gcc" "/usr/bin/gcc" "${CC}"
	assert_eq "host_deps CXX uses /usr/bin/g++" "/usr/bin/g++" "${CXX}"
	assert_eq "host_deps AR uses /usr/bin/gcc-ar" "/usr/bin/gcc-ar" "${AR}"
	assert_eq "host_deps NM uses /usr/bin/gcc-nm" "/usr/bin/gcc-nm" "${NM}"
	assert_eq "host_deps RANLIB uses /usr/bin/gcc-ranlib" "/usr/bin/gcc-ranlib" "${RANLIB}"
	assert_eq "host_deps CHOST is empty" "" "${CHOST}"
	assert_not_contains "host_deps omits -B lib_dir" "${CFLAGS}" "-B${lib_dir}"

	# Static-ish omits -static and -B lib_dir
	qbt_static_ish="yes"
	app_name="zlib"
	_custom_flags
	assert_not_contains "static-ish omits -B lib_dir" "${CFLAGS}" "-B${lib_dir}"
	assert_not_contains "static-ish omits -static" "${CFLAGS}" "-static"

	# Cross build never injects -march=native even if qbt_optimise=yes
	qbt_optimise="yes"
	_custom_flags
	assert_not_contains "cross build omits -march=native" "${CFLAGS}" "-march=native"

	# glibc < 2.41 adds -D_FORTIFY_SOURCE=3
	app_version[glibc]="2.40"
	_custom_flags
	assert_contains "glibc 2.40 adds -D_FORTIFY_SOURCE=3" "${CPPFLAGS}" "-D_FORTIFY_SOURCE=3"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 5. Path Validation & Archive Extraction Name Tests ===\n'
(
	load_lib
	_validate_path "glibc-2.44" "name"
	assert_exit "_validate_path accepts safe name" 0 "$?"
	_validate_path "/abs/path" "name"
	assert_exit "_validate_path rejects absolute path in name mode" 1 "$?"
	_validate_path "foo/../bar" "dir"
	assert_exit "_validate_path rejects .. traversal" 1 "$?"
	_validate_path "" "file"
	assert_exit "_validate_path rejects empty path" 1 "$?"
	_validate_path $'bad\nname' "dir"
	assert_exit "_validate_path rejects control chars" 1 "$?"
	_validate_path "bad;name" "name"
	assert_exit "_validate_path rejects shell chars in name mode" 1 "$?"

	# Archive tests with real tarballs
	arch_tmp="${test_root}/archives"
	mkdir -p "${arch_tmp}/src/zlib-1.3.2/sub"
	printf 'hi\n' > "${arch_tmp}/src/zlib-1.3.2/sub/file.txt"
	tar -czf "${arch_tmp}/normal.tar.gz" -C "${arch_tmp}/src" "zlib-1.3.2"
	tar -czf "${arch_tmp}/dotslash.tar.gz" -C "${arch_tmp}/src" "./zlib-1.3.2"
	: > "${arch_tmp}/empty.tar.gz"

	assert_eq "_get_archive_dir_name extracts top dir" "zlib-1.3.2" "$(_get_archive_dir_name "${arch_tmp}/normal.tar.gz")"
	assert_eq "_get_archive_dir_name strips leading ./" "zlib-1.3.2" "$(_get_archive_dir_name "${arch_tmp}/dotslash.tar.gz")"
	_get_archive_dir_name "${arch_tmp}/empty.tar.gz" > /dev/null 2>&1
	assert_exit "_get_archive_dir_name rejects empty/corrupt archive" 1 "$?"

	# Archive with unsafe directory name (space / semicolon)
	mkdir -p "${arch_tmp}/bad/evil dir"
	printf 'x\n' > "${arch_tmp}/bad/evil dir/f"
	tar -czf "${arch_tmp}/badname.tar.gz" -C "${arch_tmp}/bad" "evil dir"
	_get_archive_dir_name "${arch_tmp}/badname.tar.gz" > /dev/null 2>&1
	assert_exit "_get_archive_dir_name rejects unsafe archive dir name" 1 "$?"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 6. Core Helper Function Tests (_cmd, _post_command, _pushd/_popd, _tee, _error_tag) ===\n'
(
	load_lib
	(_cmd true)
	assert_exit "_cmd returns 0 on success" 0 "$?"
	(_cmd false > /dev/null 2>&1)
	assert_exit "_cmd exits 1 on failure" 1 "$?"

	(_post_command build 0 0)
	assert_exit "_post_command passes on 0 0" 0 "$?"
	(_post_command build 1 0 > /dev/null 2>&1)
	assert_exit "_post_command exits 1 on 1 0" 1 "$?"
	(_post_command install 139 0 > /dev/null 2>&1)
	assert_exit "_post_command exits 1 on 139 0" 1 "$?"
	(_post_command configure 0 10 > /dev/null 2>&1)
	assert_exit "_post_command exits 1 on 0 10" 1 "$?"

	mkdir -p "${test_root}/pushd_dir"
	_pushd "${test_root}/pushd_dir"
	assert_eq "_pushd changes directory" "${test_root}/pushd_dir" "${PWD}"
	_popd
	(_pushd "${test_root}/does_not_exist" > /dev/null 2>&1)
	assert_exit "_pushd exits 1 on missing dir" 1 "$?"

	# _tee with single-level relative dir and nested dir
	mkdir -p "${test_root}/tee_wd"
	(
		cd "${test_root}/tee_wd" || exit 1
		printf 'line1\n' | _tee "logs/single.log" > /dev/null
		printf 'line2\n' | _tee -a "nested/a/b/multi.log" > /dev/null
	)
	assert_eq "_tee creates single-level relative parent dir" "line1" "$(< "${test_root}/tee_wd/logs/single.log")"
	assert_eq "_tee -a creates nested parent dirs" "line2" "$(< "${test_root}/tee_wd/nested/a/b/multi.log")"

	# _error_tag
	github_tag[zlib]="v1.3.2"
	(_error_tag)
	assert_exit "_error_tag returns 0 when no error_tag present" 0 "$?"
	(_error_tag "zlib" "custom fail" > /dev/null 2>&1)
	assert_exit "_error_tag exits 1 when called with args" 1 "$?"
	github_tag[zlib]="error_tag"
	(_error_tag > /dev/null 2>&1)
	assert_exit "_error_tag exits 1 when github_tag contains error_tag" 1 "$?"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 7. Module Sorting & Validation (_sort_modules, _installation_modules) Tests ===\n'
(
	load_lib "ubuntu" "resolute" "26.04" "amd64"
	qbt_working_dir="${test_root}/mod_wd"
	mkdir -p "${qbt_working_dir}"
	qbt_build_dir="${test_root}/mod_build"
	_set_default_values
	_set_build_directory

	_sort_modules
	first_len="${#qbt_modules_install_processed[@]}"
	_sort_modules
	second_len="${#qbt_modules_install_processed[@]}"
	assert_eq "_sort_modules resets array on repeated calls" "${first_len}" "${second_len}"

	# Substring "qt" must NOT match "qtbase"
	(
		qbt_modules_test=""
		_installation_modules qt > /dev/null
		assert_eq "substring module 'qt' rejected as fail" "fail" "${qbt_modules_test}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# Mixed "zlib all" must expand to all sorted modules (no literal "all")
	(
		qbt_modules_test=""
		_installation_modules zlib all > /dev/null
		assert_eq "mixed 'zlib all' passes validation" "" "${qbt_modules_test}"
		assert_not_contains "mixed 'zlib all' does not leave literal 'all' in processed list" " ${qbt_modules_install_processed[*]} " " all "
		assert_contains "mixed 'zlib all' includes qbittorrent" " ${qbt_modules_install_processed[*]} " " qbittorrent "
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# Single module selection
	(
		qbt_modules_test=""
		_installation_modules zlib openssl > /dev/null
		assert_eq "explicit modules preserved in order" "zlib openssl" "${qbt_modules_install_processed[*]}"
		assert_eq "skip_modules marked no for selected" "no" "${skip_modules[zlib]}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 8. Multi-Arch Configuration (_multi_arch) Tests ===\n'
(
	# Debian/Ubuntu riscv64 with LTO and host_deps
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/ma_build"
		qbt_cross_name="riscv64"
		qbt_cross_target="ubuntu"
		qbt_cross_tool_dir="/usr/bin"
		qbt_build_tool="cmake"
		qbt_use_lto="yes"
		qbt_host_deps="yes"
		qbt_host_deps_path="${qbt_install_dir}/host_deps"
		_multi_arch > /dev/null
		assert_eq "ubuntu riscv64 host triplet" "riscv64-linux-gnu" "${qbt_cross_host}"
		assert_eq "ubuntu riscv64 cross_arch" "riscv64" "${cross_arch}"
		assert_contains "cmake toolchain uses cross gcc-ar for LTO" "${multi_qtbase[*]}" "-D CMAKE_AR=/usr/bin/riscv64-linux-gnu-gcc-ar"
		assert_contains "cmake toolchain includes QT_HOST_PATH" "${multi_qtbase[*]}" "-D QT_HOST_PATH=${qbt_host_deps_path}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# Debian aarch64 maps cross_arch=arm64, armv7 maps armhf
	(
		load_lib "debian" "trixie" "13" "amd64"
		qbt_cross_target="debian"
		qbt_cross_name="aarch64"
		_multi_arch info_bootstrap > /dev/null
		assert_eq "debian aarch64 cross_arch is arm64" "arm64" "${cross_arch}"
		qbt_cross_name="armv7"
		_multi_arch info_bootstrap > /dev/null
		assert_eq "debian armv7 cross_arch is armhf" "armhf" "${cross_arch}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# loongarch64 allowed on Alpine Qt 6.8, rejected on Alpine Qt 5 and Debian
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_cross_target="alpine"
		qbt_cross_name="loongarch64"
		qbt_qt_version="6.8"
		_multi_arch info_bootstrap > /dev/null
		assert_eq "alpine loongarch64 accepts Qt 6.8" "loongarch64-linux-musl" "${qbt_cross_host}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_cross_target="alpine"
		qbt_cross_name="loongarch64"
		qbt_qt_version="5.15"
		_multi_arch info_bootstrap > /dev/null 2>&1
	)
	assert_exit "alpine loongarch64 rejects Qt 5.15" 1 "$?"

	(
		load_lib "debian" "trixie" "13" "amd64"
		qbt_cross_target="debian"
		qbt_cross_name="loongarch64"
		qbt_qt_version="6"
		_multi_arch info_bootstrap > /dev/null 2>&1
	)
	assert_exit "debian loongarch64 exits 1" 1 "$?"

	# default sets multi_openssl=("./config"), invalid arch exits 1
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="default"
		_multi_arch
		assert_eq "default cross_name sets multi_openssl to ./config" "./config" "${multi_openssl[*]}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="sparc99"
		_multi_arch > /dev/null 2>&1
	)
	assert_exit "invalid cross_name exits 1" 1 "$?"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 9. Git Tag Validation (_git) Tests ===\n'
(
	load_lib
	git_repo="${test_root}/local_git_repo"
	git init -q "${git_repo}"
	git -C "${git_repo}" config user.email "test@example.com"
	git -C "${git_repo}" config user.name "Test"
	printf 'hello\n' > "${git_repo}/file.txt"
	git -C "${git_repo}" add file.txt
	git -C "${git_repo}" commit -qm "init"
	git -C "${git_repo}" branch -M master
	git -C "${git_repo}" tag v1.2.20

	# Mock _curl so URL reachability check succeeds without network, and map fake https URL to local git repo
	_curl() { return 0; }
	_git_git() {
		local -a rewritten=()
		local a
		for a in "${@}"; do
			if [[ ${a} == "https://example.invalid/repo.git" ]]; then
				rewritten+=("${git_repo}")
			else
				rewritten+=("${a}")
			fi
		done
		command git "${rewritten[@]}"
	}

	assert_eq "_git -t accepts exact tag" "v1.2.20" "$(_git "https://example.invalid/repo.git" -t "v1.2.20")"
	assert_eq "_git -t accepts exact branch" "master" "$(_git "https://example.invalid/repo.git" -t "master")"
	assert_eq "_git -t rejects leading dash option injection" "error_tag" "$(_git "https://example.invalid/repo.git" -t "-h-qt")"
	assert_eq "_git -t rejects wildcard *" "error_tag" "$(_git "https://example.invalid/repo.git" -t "*")"
	assert_eq "_git -t rejects wildcard v1.*" "error_tag" "$(_git "https://example.invalid/repo.git" -t "v1.*")"
	assert_eq "_git -t rejects bracket glob [v]1.2.20" "error_tag" "$(_git "https://example.invalid/repo.git" -t "[v]1.2.20")"
	assert_eq "_git -t rejects whitespace in ref" "error_tag" "$(_git "https://example.invalid/repo.git" -t "master extra")"
	assert_eq "_git -t rejects partial suffix match" "error_tag" "$(_git "https://example.invalid/repo.git" -t "20")"
	assert_eq "_git -t rejects nonexistent tag" "error_tag" "$(_git "https://example.invalid/repo.git" -t "v9.9.9")"

	(_git status > /dev/null 2>&1)
	assert_exit "_git exits 1 when no URL in args" 1 "$?"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 10. Module URL & Version Resolution (_set_module_urls) Tests ===\n'
(
	# Workflow JSON mode (both jq and sed fallback) + zlib-ng tag + iconv derived URL
	mock_wf_json='{
  "glibc": "2.44",
  "zlib": "1.3.2",
  "zlib_ng": "2.2.4",
  "iconv": "1.19",
  "icu": "76-1",
  "double_conversion": "3.3.1",
  "openssl": "3.5.9",
  "boost": "1.88.0",
  "libtorrent_1_2": "1.2.20",
  "libtorrent_2_1": "2.1.0",
  "qt6": "6.8.2",
  "qbittorrent": "5.1.0"
}'

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_workflow_files="yes"
		qbt_zlib_type="zlib"
		qbt_qt_version="6.8"
		qbt_libtorrent_version="1.2"
		curl_hits="${test_root}/curl_hits.log"
		: > "${curl_hits}"
		_curl() {
			printf '%s\n' "${*}" >> "${curl_hits}"
			if [[ ${*} == *"dependency-version.json"* ]]; then
				printf '%s' "${mock_wf_json}"
				return 0
			fi
			return 0
		}
		_git_git() { return 1; }
		_set_module_urls
		assert_eq "workflow JSON maps glibc 2.44" "2.44" "${app_version[glibc]}"
		assert_eq "workflow JSON maps qt6 from qt_version 6.8" "6.8.2" "${app_version[qtbase]}"
		assert_eq "workflow JSON maps libtorrent_1_2" "1.2.20" "${app_version[libtorrent]}"
		assert_eq "iconv archive URL derived from app_version" "https://ftpmirror.gnu.org/gnu/libiconv/libiconv-1.19.tar.gz" "${source_archive_url[iconv]}"
		assert_not_contains "does not scrape ftpmirror.gnu.org/gnu/libiconv/ on startup" "$(< "${curl_hits}")" "ftpmirror.gnu.org/gnu/libiconv/"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# Test sed fallback path (hide jq via PATH) and zlib-ng tagged URL + empty version fallback
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_workflow_files="yes"
		qbt_zlib_type="zlib-ng"
		qbt_qt_version="6"
		qbt_libtorrent_version="2.1"
		no_jq_bin="${test_root}/no_jq_bin"
		mkdir -p "${no_jq_bin}"
		for cmd_name in sed awk sort head grep tr rm mkdir cp mv cat; do
			cmd_path="$(command -v "${cmd_name}" || true)"
			[[ -n ${cmd_path} ]] && ln -fsn "${cmd_path}" "${no_jq_bin}/${cmd_name}"
		done
		PATH="${no_jq_bin}"
		_curl() {
			if [[ ${*} == *"dependency-version.json"* ]]; then
				printf '%s' "${mock_wf_json}"
				return 0
			fi
			return 1
		}
		_git_git() { return 1; }
		_set_module_urls
		assert_eq "sed JSON fallback resolves zlib-ng tag" "2.2.4" "${github_tag[zlib]}"
		assert_eq "zlib-ng empty curl falls back to tag version" "2.2.4" "${app_version[zlib]}"
		assert_eq "zlib-ng tagged URL uses refs/tags" "https://github.com/zlib-ng/zlib-ng/archive/refs/tags/2.2.4.tar.gz" "${source_archive_url[zlib]}"
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	# Test awk boundary matching (1.2 vs 1.20, 6.1 vs 6.10) and awk injection resistance
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_workflow_files="no"
		qbt_zlib_type="zlib"
		qbt_qt_version="6.1"
		qbt_libtorrent_version="1.2"
		_curl() { return 1; }
		_git_git() {
			case "${*}" in
				*libtorrent.git*)
					printf 'aaa\trefs/tags/v1.2.20\nbbb\trefs/tags/v1.20.0\nccc\trefs/tags/v1.2.19\n'
					;;
				*qtbase.git* | *qttools.git*)
					printf 'aaa\trefs/tags/v6.1.3\nbbb\trefs/tags/v6.10.0\nccc\trefs/tags/v6.1.4-beta1\n'
					;;
				*zlib.git*)
					printf 'aaa\trefs/tags/v1.3.2\n'
					;;
				*libiconv.git*)
					printf 'aaa\trefs/tags/v1.19\n'
					;;
				*icu.git*)
					printf 'aaa\trefs/tags/release-76-1\n'
					;;
				*double-conversion.git*)
					printf 'aaa\trefs/tags/v3.3.1\n'
					;;
				*openssl.git*)
					printf 'aaa\trefs/tags/openssl-3.5.9\n'
					;;
				*boost.git*)
					printf 'aaa\trefs/tags/boost-1.88.0\n'
					;;
				*qBittorrent.git*)
					printf 'aaa\trefs/tags/release-5.1.0\n'
					;;
				*) ;;
			esac
		}
		_set_module_urls
		assert_eq "libtorrent 1.2 matches v1.2.20 (not v1.20.0)" "v1.2.20" "${github_tag[libtorrent]}"
		assert_eq "qtbase 6.1 matches v6.1.3 (not v6.10.0 or beta)" "v6.1.3" "${github_tag[qtbase]}"

		# Attempt awk code injection via qbt_libtorrent_version
		pwn_file="${test_root}/awk_pwned"
		qbt_libtorrent_version="1.2/{system(\"touch ${pwn_file}\")}/"
		_set_module_urls
		if [[ ! -e ${pwn_file} ]]; then
			pass "awk prefix lookup immune to code injection"
		else
			fail "awk injection" "arbitrary command executed via qbt_libtorrent_version"
		fi
		printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
	)
	read -r passed failed < "${test_root}/counts"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 11. Patching System (_apply_patches) Tests ===\n'
(
	load_lib "ubuntu" "resolute" "26.04" "amd64"
	qbt_install_dir="${test_root}/patch_build"
	qbt_libtorrent_version="1.2"
	qbt_libtorrent_master_jamfile="no"
	mkdir -p "${qbt_install_dir}"

	# 11a. bootstrap creates dirs and excludes *_host_deps from count
	qbt_modules_install=(["all"]="true" ["install"]="true" ["zlib"]="true" ["icu_host_deps"]="true" ["icu"]="true")
	qbt_modules_order=("all" "install" "zlib" "icu_host_deps" "icu")
	qbt_modules_delete=()
	app_version=([zlib]="1.3.2" [icu]="76-1")
	bs_out="$(_apply_patches bootstrap)"
	assert_contains "_apply_patches bootstrap counts only modules with app_version (2)" "${bs_out}" "Patch directories created for 2 modules"
	if [[ -d "${qbt_install_dir}/patches/zlib/1.3.2/source" && -d "${qbt_install_dir}/patches/icu/76-1/source" ]]; then
		pass "_apply_patches bootstrap creates expected patch directories"
	else
		fail "_apply_patches bootstrap" "expected patch directories missing"
	fi

	# 11b. source/ directory method + *_host_deps key stripping
	src_target="${test_root}/icu_src"
	mkdir -p "${src_target}"
	printf 'patched-file\n' > "${qbt_install_dir}/patches/icu/76-1/source/override.txt"
	printf 'dotfile\n' > "${qbt_install_dir}/patches/icu/76-1/source/.hidden"
	qbt_dl_folder_path="${src_target}"
	app_name="icu_host_deps"
	_apply_patches > /dev/null
	assert_eq "_apply_patches strips _host_deps and copies source/ files" "patched-file" "$(< "${src_target}/override.txt")"
	assert_eq "_apply_patches copies dotfiles from source/" "dotfile" "$(< "${src_target}/.hidden")"

	# 11c. local patch + url (scheme validation + dedup) + *.patch merge & apply
	zlib_src="${test_root}/zlib_src"
	mkdir -p "${zlib_src}"
	printf 'lineA\nlineB\n' > "${zlib_src}/hello.txt"
	cat > "${qbt_install_dir}/patches/zlib/1.3.2/patch" << 'EOF'
--- a/hello.txt
+++ b/hello.txt
@@ -1,2 +1,2 @@
-lineA
+lineA_patched
 lineB
EOF
	cat > "${qbt_install_dir}/patches/zlib/1.3.2/url" << 'EOF'
file:///etc/passwd
https://example.invalid/dup.patch
EOF
	cat > "${qbt_install_dir}/patches/zlib/1.3.2/02.diff" << 'EOF'
--- a/hello.txt
+++ b/hello.txt
@@ -1,2 +1,2 @@
 lineA_patched
-lineB
+lineB_patched
EOF
	# Mock _curl so dup.patch returns the exact same content as patch (must be deduplicated!)
	_curl() {
		local out="" i=1
		while ((i <= $#)); do
			if [[ ${!i} == "-o" ]]; then
				((i++))
				out="${!i}"
			fi
			((i++))
		done
		cp "${qbt_install_dir}/patches/zlib/1.3.2/patch" "${out}"
		return 0
	}
	qbt_dl_folder_path="${zlib_src}"
	app_name="zlib"
	patch_out="$(_apply_patches)"
	assert_contains "_apply_patches rejects unsafe file:// URL" "${patch_out}" "Skipping unsafe patch URL"
	assert_eq "_apply_patches deduplicates url and applies merged patch + diff" $'lineA_patched\nlineB_patched' "$(< "${zlib_src}/hello.txt")"

	# 11d. Remote Jamfile fallback must NOT overwrite/delete original Jamfile on empty download
	lt_src="${test_root}/lt_src"
	mkdir -p "${lt_src}"
	printf 'ORIGINAL_JAMFILE\n' > "${lt_src}/Jamfile"
	app_version[libtorrent]="1.2.20"
	qbt_dl_folder_path="${lt_src}"
	qbt_patches_url="validowner/validrepo bad/repo/extra *"
	app_name="libtorrent"
	_git_git() { printf 'ref: refs/heads/master\tHEAD\n'; }
	_curl() {
		local out="" i=1
		while ((i <= $#)); do
			if [[ ${!i} == "-o" ]]; then
				((i++))
				out="${!i}"
			fi
			((i++))
		done
		[[ -n ${out} ]] && : > "${out}"
		printf '404'
		return 0
	}
	_apply_patches > /dev/null
	assert_eq "empty remote Jamfile preserves original source Jamfile" "ORIGINAL_JAMFILE" "$(< "${lt_src}/Jamfile")"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 12. Cache Directory & .qbt_env Drift Tests ===\n'
(
	load_lib
	script_parent_path="${test_root}/cache_env_test"
	qbt_cache_dir="${test_root}/cache_store"
	mkdir -p "${script_parent_path}" "${qbt_cache_dir}"
	printf 'qbt_qt_version="6"\n' > "${script_parent_path}/.qbt_env"

	# Initial copy
	qbt_cache_dir_options=""
	_cache_dirs_qbt_env_copy > /dev/null
	assert_eq "initial cache copy writes .qbt_env" 'qbt_qt_version="6"' "$(< "${qbt_cache_dir}/.qbt_env")"

	# Modify main .qbt_env: non-bs run must NOT overwrite cached copy and must warn (return 1)
	printf 'qbt_qt_version="5"\n' > "${script_parent_path}/.qbt_env"
	_cache_dirs_qbt_env > /dev/null
	assert_exit "modified .qbt_env triggers drift warning (return 1)" 1 "$?"
	assert_eq "non-bs run preserves cached .qbt_env" 'qbt_qt_version="6"' "$(< "${qbt_cache_dir}/.qbt_env")"

	# bs mode updates cached .qbt_env
	qbt_cache_dir_options="bs"
	_cache_dirs_qbt_env > /dev/null
	assert_exit "bs mode syncs .qbt_env and returns 0" 0 "$?"
	assert_eq "bs mode updates cached .qbt_env" 'qbt_qt_version="5"' "$(< "${qbt_cache_dir}/.qbt_env")"

	# _download_file recovers from corrupt cached archive in bs mode
	qbt_install_dir="${test_root}/dl_bs_build"
	qbt_working_dir="${test_root}"
	mkdir -p "${qbt_install_dir}/logs"
	app_name="zlib"
	app_version[zlib]="1.3.2"
	source_type="source"
	qbt_dl_dir="${qbt_cache_dir}"
	qbt_dl_file_path="${qbt_cache_dir}/zlib.tar.xz"
	qbt_dl_source_url="https://example.invalid/zlib.tar.xz"
	printf 'corrupt-bytes' > "${qbt_dl_file_path}"
	mkdir -p "${test_root}/good_src/zlib-1.3.2"
	printf 'ok\n' > "${test_root}/good_src/zlib-1.3.2/README"
	tar -czf "${test_root}/good_zlib.tar.gz" -C "${test_root}/good_src" "zlib-1.3.2"
	_curl() {
		local out="" i=1
		while ((i <= $#)); do
			if [[ ${!i} == "-o" ]]; then
				((i++))
				out="${!i}"
			fi
			((i++))
		done
		cp "${test_root}/good_zlib.tar.gz" "${out}"
		return 0
	}
	_download_file > /dev/null
	assert_exit "_download_file in bs mode recovers from corrupt cached archive" 0 "$?"
	assert_eq "_download_file sets qbt_dl_folder_path to extracted dir" "${qbt_install_dir}/zlib-1.3.2" "${qbt_dl_folder_path}"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 13. Static Link Fixes, Cleanup (_delete_function), & Install Tests ===\n'
(
	load_lib
	qbt_working_dir="${test_root}"
	qbt_install_dir="${test_root}/links_build"
	lib_dir="${qbt_install_dir}/lib"
	mkdir -p "${lib_dir}" "${qbt_install_dir}/logs" "${qbt_install_dir}/aarch64-linux-musl/lib"
	: > "${lib_dir}/libz.a"
	: > "${qbt_install_dir}/aarch64-linux-musl/lib/libfoo.a"
	app_name="zlib"
	_fix_static_links
	assert_eq "_fix_static_links points libz.so to libz.a" "libz.a" "$(readlink "${lib_dir}/libz.so")"
	_fix_multiarch_static_links "aarch64-linux-musl"
	assert_eq "_fix_multiarch_static_links points libfoo.so to libfoo.a" "libfoo.a" "$(readlink "${qbt_install_dir}/aarch64-linux-musl/lib/libfoo.so")"

	# _delete_function removes archive dir + base_app_name.tar.xz for *_host_deps
	mkdir -p "${test_root}/del_src/icu-76" "${qbt_install_dir}/icu-76" "${qbt_install_dir}/icu"
	printf 'x\n' > "${test_root}/del_src/icu-76/f"
	tar -czf "${qbt_install_dir}/icu.tar.xz" -C "${test_root}/del_src" "icu-76"
	app_name="icu_host_deps"
	qbt_dl_file_path="${qbt_install_dir}/icu.tar.xz"
	qbt_skip_delete="no"
	_delete_function > /dev/null
	if [[ ! -e "${qbt_install_dir}/icu.tar.xz" && ! -d "${qbt_install_dir}/icu-76" && ! -d "${qbt_install_dir}/icu" ]]; then
		pass "_delete_function removes extracted dir and base_app_name.tar.xz for *_host_deps"
	else
		fail "_delete_function" "leftover files remained after deletion"
	fi

	# _delete_function respects qbt_skip_delete=yes
	mkdir -p "${qbt_install_dir}/zlib"
	app_name="zlib"
	qbt_dl_file_path="${qbt_install_dir}/nonexistent.tar.xz"
	qbt_skip_delete="yes"
	_delete_function > /dev/null
	if [[ -d "${qbt_install_dir}/zlib" ]]; then
		pass "_delete_function preserves files when qbt_skip_delete=yes"
	else
		fail "_delete_function skip" "deleted directory despite qbt_skip_delete=yes"
	fi

	# _install_qbittorrent tests
	inst_home="${test_root}/inst_home"
	inst_build="${test_root}/inst_build"
	mkdir -p "${inst_home}" "${inst_build}/completed"
	LOCAL_USER_HOME="${inst_home}"
	qbt_install_dir="${inst_build}"
	qbt_install_dir_short="${inst_build}"
	qbt_local_paths="${inst_home}/bin:/usr/bin"
	command_privilege=("printf" "PRIV_USED:")

	# Missing binary exits 1
	(_install_qbittorrent install > /dev/null 2>&1)
	assert_exit "_install_qbittorrent exits 1 when binary missing" 1 "$?"

	printf '#!/bin/sh\nexit 0\n' > "${inst_build}/completed/qbittorrent-nox"
	chmod 0644 "${inst_build}/completed/qbittorrent-nox"

	# Local install
	(_install_qbittorrent install > /dev/null)
	assert_exit "_install_qbittorrent local exits 0" 0 "$?"
	if [[ -x "${inst_home}/bin/qbittorrent-nox" ]]; then
		pass "_install_qbittorrent local installs executable to LOCAL_USER_HOME/bin"
	else
		fail "_install_qbittorrent local" "binary missing or not executable"
	fi

	# Custom install inside LOCAL_USER_HOME must NOT invoke command_privilege
	out_user_custom="$(_install_qbittorrent install custom "${inst_home}/mybin")"
	assert_exit "_install_qbittorrent custom inside home exits 0" 0 "$?"
	assert_not_contains "_install_qbittorrent custom inside home avoids command_privilege" "${out_user_custom}" "PRIV_USED:"
	if [[ -x "${inst_home}/mybin/qbittorrent-nox" ]]; then
		pass "_install_qbittorrent custom inside home installed executable"
	else
		fail "_install_qbittorrent custom inside home" "binary not found"
	fi

	# Custom install outside LOCAL_USER_HOME must invoke command_privilege
	out_sys_custom="$(_install_qbittorrent install custom "${test_root}/outside_home_bin")"
	assert_exit "_install_qbittorrent custom outside home exits 0" 0 "$?"
	assert_contains "_install_qbittorrent custom outside home uses command_privilege" "${out_sys_custom}" "PRIV_USED:"

	# Custom install with .. traversal must be rejected
	(_install_qbittorrent install custom "${inst_home}/../escape" > /dev/null 2>&1)
	assert_exit "_install_qbittorrent custom rejects .. traversal" 1 "$?"

	# Custom install missing 3rd arg exits 1
	(_install_qbittorrent install custom > /dev/null 2>&1)
	assert_exit "_install_qbittorrent custom exits 1 when path omitted" 1 "$?"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 14. Script Version Check & Release Info Tests ===\n'
(
	load_lib
	script_full_path="${test_root}/ver_script.bash"
	script_url="https://example.invalid/qbt-nox-static.bash"
	printf 'script_version="2.2.6"\n' > "${script_full_path}"
	script_version="2.2.6"

	_curl() { return 0; }
	out="$(_script_version)"
	assert_contains "_script_version handles empty remote content" "${out}" "Could not fetch remote script"

	_curl() { printf 'not a script\n'; }
	out="$(_script_version)"
	assert_contains "_script_version handles unparseable remote version" "${out}" "Could not parse remote script version"

	_curl() { printf 'script_version="2.2.7"\n'; }
	out="$(_script_version)"
	assert_contains "_script_version detects update available" "${out}" "Script update available"

	_curl() { printf 'script_version="2.2.5"\n'; }
	out="$(_script_version)"
	assert_contains "_script_version detects dev version" "${out}" "2.2.6-dev"

	_curl() { printf 'script_version="2.2.6"\n'; }
	out="$(_script_version)"
	assert_not_contains "_script_version clean on exact match" "${out}" "differs from the remote"

	_curl() { printf 'script_version="2.2.6"\n# extra\n'; }
	out="$(_script_version)"
	assert_contains "_script_version warns on SHA256 mismatch" "${out}" "differs from the remote version"

	# _release_info with mocked remote revision = 3 -> generates revision 4
	qbt_install_dir="${test_root}/rel_build"
	qbt_revision_url="userdocs/qbittorrent-nox-static"
	qbt_libtorrent_version="1.2"
	qbt_zlib_type="zlib"
	qbt_workflow_files="yes"
	qbt_cross_name="riscv64"
	qt_version_short_array=(6 8)
	github_tag=([qbittorrent]="release-5.1.0" [libtorrent]="v1.2.20")
	app_version=([qbittorrent]="5.1.0" [libtorrent]="1.2.20" [qtbase]="6.8.2" [boost]="1.88.0" [openssl]="3.5.9" [zlib]="1.3.2")
	_git_git() { return 0; }
	_curl() {
		case "${*}" in
			*releases/tags/*) printf '{"assets":[{"name":"dependency-version.json"}]}' ;;
			*dependency-version.json*) printf '{"revision":"3"}' ;;
			*) return 1 ;;
		esac
	}
	_release_info > /dev/null
	assert_eq "_release_info writes tag.md" "release-5.1.0_v1.2.20" "$(< "${qbt_install_dir}/release_info/tag.md")"
	assert_eq "_release_info writes title.md" "qbittorrent 5.1.0 libtorrent 1.2.20" "$(< "${qbt_install_dir}/release_info/title.md")"
	assert_contains "_release_info increments remote revision (compact JSON)" "$(< "${qbt_install_dir}/release_info/qt6-dependency-version.json")" '"revision": "4"'
	assert_contains "_release_info includes riscv64 tuning table row" "$(< "${qbt_install_dir}/release_info/qt6-riscv64-release.md")" "riscv64-linux-musl"

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n=== 15. End-to-End CLI Tests (Option Loops, Security Guards, Offline Commands) ===\n'
(
	# 15a. Unsupported OS rejected cleanly
	cli_bad_os="${test_root}/cli_bad_os"
	make_cli_copy "${cli_bad_os}" "ubuntu" "noble" "24.04" "no"
	out="$("${cli_bad_os}/qbt-nox-static.bash" -h 2>&1)"
	assert_exit "unsupported OS codename exits 1" 1 "$?"
	assert_contains "unsupported OS prints helpful message" "${out}" "This is not a supported OS"

	# 15b. Supported OS CLI tests (Option Loop 1 — no network stubs needed!)
	cli_dir="${test_root}/cli_live"
	make_cli_copy "${cli_dir}" "ubuntu" "resolute" "26.04" "no"

	# ctest non-TTY exits 1
	out="$("${cli_dir}/qbt-nox-static.bash" ctest < /dev/null 2>&1)"
	assert_exit "ctest exits 1 when stdout is not a TTY" 1 "$?"
	assert_contains "ctest reports no color support" "${out}" "does not support color"

	# -bs-e creates clean .qbt_env in script_parent_path with zero ANSI codes and valid bash syntax
	(
		mkdir -p "${test_root}/other_cwd"
		cd "${test_root}/other_cwd" || exit 1
		"${cli_dir}/qbt-nox-static.bash" -bs-e > /dev/null
	)
	assert_exit "-bs-e exits 0" 0 "$?"
	if [[ -f "${cli_dir}/.qbt_env" && ! -f "${test_root}/other_cwd/.qbt_env" ]]; then
		pass "-bs-e writes .qbt_env to script_parent_path (not cwd)"
	else
		fail "-bs-e path" "expected ${cli_dir}/.qbt_env"
	fi
	if ! grep -q $'\e' "${cli_dir}/.qbt_env"; then
		pass "-bs-e strips all ANSI escape sequences"
	else
		fail "-bs-e ANSI" "ANSI escapes found in generated .qbt_env"
	fi
	bash -n "${cli_dir}/.qbt_env"
	assert_exit "-bs-e produces syntactically valid bash file" 0 "$?"
	rm -f "${cli_dir}/.qbt_env"

	# -cd <dir> rm refuses unsafe paths including trailing slashes and /.
	safe_home="${test_root}/cli_home"
	mkdir -p "${safe_home}/legit_cache"
	for unsafe_path in "/" "///" "." "./" ".." "${safe_home}" "${safe_home}//" "${safe_home}/." "${cli_dir}" "${cli_dir}/."; do
		HOME="${safe_home}" "${cli_dir}/qbt-nox-static.bash" -cd "${unsafe_path}" rm > /dev/null 2>&1
		assert_exit "-cd '${unsafe_path}' rm refused with exit 1" 1 "$?"
	done
	if [[ -d ${safe_home} && -d ${cli_dir} ]]; then
		pass "unsafe -cd rm attempts left protected directories intact"
	else
		fail "unsafe -cd rm" "a protected directory was deleted!"
	fi

	HOME="${safe_home}" "${cli_dir}/qbt-nox-static.bash" -cd "${safe_home}/legit_cache" rm > /dev/null
	assert_exit "-cd safe_dir rm exits 0" 0 "$?"
	if [[ ! -d "${safe_home}/legit_cache" ]]; then
		pass "-cd safe_dir rm removed target cache directory"
	else
		fail "-cd safe_dir rm" "target cache dir was not removed"
	fi

	# Value-taking option-loop-1 flags reject missing or -* values
	"${cli_dir}/qbt-nox-static.bash" -b -d > /dev/null 2>&1
	assert_exit "-b rejects leading-dash value" 1 "$?"
	"${cli_dir}/qbt-nox-static.bash" -cd -d > /dev/null 2>&1
	assert_exit "-cd rejects leading-dash value" 1 "$?"
	"${cli_dir}/qbt-nox-static.bash" -p -d > /dev/null 2>&1
	assert_exit "-p rejects leading-dash value" 1 "$?"
	"${cli_dir}/qbt-nox-static.bash" -ma bogusarch > /dev/null 2>&1
	assert_exit "-ma rejects invalid architecture" 1 "$?"

	# -o / -si combined with -ma rejected in BOTH orders
	"${cli_dir}/qbt-nox-static.bash" -ma aarch64 -o > /dev/null 2>&1
	assert_exit "-ma aarch64 -o exits 1" 1 "$?"
	"${cli_dir}/qbt-nox-static.bash" -o -ma aarch64 > /dev/null 2>&1
	assert_exit "-o -ma aarch64 exits 1" 1 "$?"
	"${cli_dir}/qbt-nox-static.bash" -ma aarch64 -si > /dev/null 2>&1
	assert_exit "-ma aarch64 -si exits 1" 1 "$?"
	"${cli_dir}/qbt-nox-static.bash" -si -ma aarch64 > /dev/null 2>&1
	assert_exit "-si -ma aarch64 exits 1" 1 "$?"

	# Offline install subcommand short-circuits before network/dependency checks
	inst_cli_build="${test_root}/cli_inst_build"
	mkdir -p "${inst_cli_build}/completed"
	HOME="${safe_home}" "${cli_dir}/qbt-nox-static.bash" -b "${inst_cli_build}" install > /dev/null 2>&1
	assert_exit "offline install exits 1 when binary missing" 1 "$?"
	printf '#!/bin/sh\nexit 0\n' > "${inst_cli_build}/completed/qbittorrent-nox"
	HOME="${safe_home}" "${cli_dir}/qbt-nox-static.bash" -b "${inst_cli_build}" install custom "${safe_home}/cli_bin" > /dev/null
	assert_exit "offline install custom exits 0 when binary exists" 0 "$?"
	if [[ -x "${safe_home}/cli_bin/qbittorrent-nox" ]]; then
		pass "offline install short-circuit installed executable without network"
	else
		fail "offline install" "installed binary missing"
	fi

	# 15c. Option Loop 2 & Bootstrap CLI tests (offline stubs for network/deps)
	cli_off="${test_root}/cli_offline"
	make_cli_copy "${cli_off}" "ubuntu" "resolute" "26.04" "yes"

	"${cli_off}/qbt-nox-static.bash" -bs-c > /dev/null
	assert_exit "-bs-c handled cleanly (no Unsupported flag crash)" 0 "$?"

	out="$("${cli_off}/qbt-nox-static.bash" -h)"
	assert_exit "-h exits 0" 0 "$?"
	assert_contains "-h documents qbt_use_lto" "${out}" "qbt_use_lto"
	assert_contains "-h documents qbt_linker_mold" "${out}" "qbt_linker_mold"
	assert_contains "-h documents qbt_with_qemu" "${out}" "qbt_with_qemu"

	"${cli_off}/qbt-nox-static.bash" --help-static-ish > /dev/null
	assert_exit "--help-static-ish exits 0" 0 "$?"
	"${cli_off}/qbt-nox-static.bash" --help-staticish > /dev/null
	assert_exit "--help-staticish alias exits 0" 0 "$?"
	"${cli_off}/qbt-nox-static.bash" --help-multi-arch > /dev/null
	assert_exit "--help-multi-arch exits 0" 0 "$?"
	"${cli_off}/qbt-nox-static.bash" --help-multiarch > /dev/null
	assert_exit "--help-multiarch alias exits 0" 0 "$?"

	# Unsupported flag exits 1
	"${cli_off}/qbt-nox-static.bash" --nonexistent-flag > /dev/null 2>&1
	assert_exit "unsupported flag exits 1" 1 "$?"

	# Option Loop 2 value-taking flags reject -* values
	for flag in -ot -bt -lt -pr -qt -qtt; do
		"${cli_off}/qbt-nox-static.bash" "${flag}" -h > /dev/null 2>&1
		assert_exit "${flag} rejects leading-dash argument" 1 "$?"
	done

	# -pr rejects malformed owner/repo format
	"${cli_off}/qbt-nox-static.bash" -pr "owner/repo/extra" > /dev/null 2>&1
	assert_exit "-pr rejects malformed repo path" 1 "$?"

	# -ot lts with empty git output sets error_tag and exits 1
	"${cli_off}/qbt-nox-static.bash" -ot lts > /dev/null 2>&1
	assert_exit "-ot lts fails via error_tag when lookup returns empty" 1 "$?"

	# -bs-ma rejects default cross_name
	"${cli_off}/qbt-nox-static.bash" -bs-ma > /dev/null 2>&1
	assert_exit "-bs-ma rejects default arch" 1 "$?"

	# -bs-ef honors -q overriding .qbt_env qbt_qt_version="6" (with Qt5-compatible qbt 4.5.2)
	cli_off_qt5="${test_root}/cli_offline_qt5"
	make_cli_copy "${cli_off_qt5}" "ubuntu" "resolute" "26.04" "yes"
	sed -i 's|release-5.1.0|release-4.5.2|g; s|app_version\[qbittorrent\]="5.1.0"|app_version[qbittorrent]="4.5.2"|g' "${cli_off_qt5}/qbt-nox-static.bash"
	printf 'qbt_qt_version="6"\nqbt_build_tool="cmake"\n' > "${cli_off_qt5}/.qbt_env"
	"${cli_off_qt5}/qbt-nox-static.bash" -q -bs-ef > /dev/null
	assert_exit "-q -bs-ef exits 0 with Qt5-compatible qbt" 0 "$?"
	assert_contains "-q overrides .qbt_env qt6 to qmake in -bs-ef" "$(< "${cli_off_qt5}/.qbt_env")" 'qbt_build_tool="qmake"'
	assert_contains "-q overrides .qbt_env qt6 to qt5 in -bs-ef" "$(< "${cli_off_qt5}/.qbt_env")" 'qbt_qt_version="5"'
	rm -f "${cli_off_qt5}/.qbt_env"

	# -q overriding .qbt_env qt6 against qbt 5.1.0 correctly triggers C++ standard conflict (exit 1)
	printf 'qbt_qt_version="6"\nqbt_build_tool="cmake"\n' > "${cli_off}/.qbt_env"
	"${cli_off}/qbt-nox-static.bash" -q -bs-ef > /dev/null 2>&1
	assert_exit "-q overrides .qbt_env qt6 and rejects incompatible qbt 5.1.0" 1 "$?"
	rm -f "${cli_off}/.qbt_env"

	# Invalid module exits 1; -- preserves positional argument into module test
	"${cli_off}/qbt-nox-static.bash" not_a_module > /dev/null 2>&1
	assert_exit "invalid module exits 1" 1 "$?"
	"${cli_off}/qbt-nox-static.bash" -- -not-a-flag > /dev/null 2>&1
	assert_exit "-- passes positional arg to module validation and exits 1" 1 "$?"

	# Deferred -bs-p and -bs-r create directories/files in -b custom path
	bs_build="${test_root}/cli_bs_build"
	"${cli_off}/qbt-nox-static.bash" -b "${bs_build}" -bs-p -bs-r > /dev/null
	assert_exit "-b <dir> -bs-p -bs-r exits 0" 0 "$?"
	if [[ -d "${bs_build}/patches/qbittorrent/5.1.0/source" && -f "${bs_build}/release_info/tag.md" ]]; then
		pass "-bs-p and -bs-r create patch dirs and release_info in custom -b dir"
	else
		fail "-bs-p -bs-r" "expected bootstrap outputs missing in ${bs_build}"
	fi

	printf '%d %d\n' "${passed}" "${failed}" > "${test_root}/counts"
)
read -r p f < "${test_root}/counts"
passed="${p}"
failed="${f}"

printf '\n========================================\n'
printf 'Unit Test Summary: %d passed, %d failed\n' "${passed}" "${failed}"
printf '========================================\n'

if ((failed > 0)); then
	exit 1
fi
exit 0
