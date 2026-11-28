#!/bin/bash
#
# Comprehensive offline unit tests for qbt-nox-static.bash
# Covers all script logic, CLI parsing, security guards, sourcing safety, helpers,
# mocked module command generation, and structural contracts without compiling any module.
#
# shellcheck disable=SC2030,SC2031,SC2034,SC2154,SC2317,SC2329

set -o pipefail

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
script_dir="${script_path%/*}"
repo_root="$(readlink -f -- "${script_dir}/..")"
target_script="${repo_root}/qbt-nox-static.bash"

if [[ ! -f ${target_script} ]]; then
	printf 'ERROR: Target script not found: %s\n' "${target_script}" >&2
	exit 1
fi

test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT

export GIT_CONFIG_GLOBAL="${test_root}/mock_gitconfig"
: > "${GIT_CONFIG_GLOBAL}"

passed=0
failed=0
counts_file="${test_root}/counts"
failures_file="${test_root}/failures.log"
: > "${failures_file}"

save_counts() {
	printf '%d %d\n' "${passed}" "${failed}" > "${counts_file}"
}

load_counts() {
	local p f
	read -r p f < "${counts_file}"
	passed="${p}"
	failed="${f}"
}

pass() {
	((passed++))
	printf '  [PASS] %s\n' "${1}"
}

fail() {
	((failed++))
	printf '%s: %s\n' "${1}" "${2:-assertion failed}" >> "${failures_file}"
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

assert_pass_eq() {
	local name="${1}" rc="${2}" expected="${3}" actual="${4}"
	if ((rc != 0)); then
		fail "${name}" "expected exit code 0, got ${rc} (output: '${actual}')"
	elif [[ ${actual} == "${expected}" ]]; then
		pass "${name}"
	else
		fail "${name}" "expected '${expected}', got '${actual}'"
	fi
}

assert_contains() {
	local name="${1}" rc="${2}" haystack="${3}" needle="${4}"
	if ((rc != 0)); then
		fail "${name}" "expected exit code 0, got ${rc} (output: '${haystack}')"
	elif [[ ${haystack} == *"${needle}"* ]]; then
		pass "${name}"
	else
		fail "${name}" "expected output to contain '${needle}', got '${haystack}'"
	fi
}

assert_not_contains() {
	local name="${1}" rc="${2}" haystack="${3}" needle="${4}"
	if ((rc != 0)); then
		fail "${name}" "expected exit code 0, got ${rc} (output: '${haystack}')"
	elif [[ ${haystack} != *"${needle}"* ]]; then
		pass "${name}"
	else
		fail "${name}" "expected output NOT to contain '${needle}', got '${haystack}'"
	fi
}

assert_fail_contains() {
	local name="${1}" rc="${2}" haystack="${3}" needle="${4}"
	if ((rc == 0)); then
		fail "${name}" "expected non-zero exit code, got 0 (output: '${haystack}')"
	elif [[ ${haystack} == *"${needle}"* ]]; then
		pass "${name}"
	else
		fail "${name}" "expected failure output to contain '${needle}', got '${haystack}'"
	fi
}

assert_fail_not_contains() {
	local name="${1}" rc="${2}" haystack="${3}" needle="${4}"
	if ((rc == 0)); then
		fail "${name}" "expected non-zero exit code, got 0 (output: '${haystack}')"
	elif [[ ${haystack} != *"${needle}"* ]]; then
		pass "${name}"
	else
		fail "${name}" "expected failure output NOT to contain '${needle}', got '${haystack}'"
	fi
}

assert_match() {
	local name="${1}" rc="${2}" haystack="${3}" pattern="${4}"
	if ((rc != 0)); then
		fail "${name}" "expected exit code 0, got ${rc} (output: '${haystack}')"
	elif [[ ${haystack} =~ ${pattern} ]]; then
		pass "${name}"
	else
		fail "${name}" "expected '${haystack}' to match regex '${pattern}'"
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

assert_file_exists() {
	local name="${1}" path="${2}"
	if [[ -f ${path} ]]; then
		pass "${name}"
	else
		fail "${name}" "expected file to exist: ${path}"
	fi
}

assert_file_missing() {
	local name="${1}" path="${2}"
	if [[ ! -e ${path} && ! -L ${path} ]]; then
		pass "${name}"
	else
		fail "${name}" "expected file NOT to exist: ${path}"
	fi
}

assert_dir_exists() {
	local name="${1}" path="${2}"
	if [[ -d ${path} ]]; then
		pass "${name}"
	else
		fail "${name}" "expected directory to exist: ${path}"
	fi
}

assert_dir_missing() {
	local name="${1}" path="${2}"
	if [[ ! -d ${path} ]]; then
		pass "${name}"
	else
		fail "${name}" "expected directory NOT to exist: ${path}"
	fi
}

# Create a recording mock command inside a bin directory
make_mock_cmd() {
	local bin_dir="${1}" cmd_name="${2}" log_file="${3}" rc="${4:-0}" extra_body="${5:-}"
	mkdir -p -- "${bin_dir}"
	cat > "${bin_dir}/${cmd_name}" <<- EOF
		#!/bin/bash
		printf '%s' "${cmd_name}" >> "${log_file}"
		for a in "\$@"; do
			printf ' %s' "\${a}" >> "${log_file}"
		done
		printf '\n' >> "${log_file}"
		${extra_body}
		exit ${rc}
	EOF
	chmod +x -- "${bin_dir}/${cmd_name}"
}

# Source target_script directly via its ${BASH_SOURCE[0]} == "${0}" guard with mock OS variables
load_lib() {
	local mock_os_id="${1:-ubuntu}"
	local mock_codename="${2:-resolute}"
	local mock_version="${3:-26.04}"
	local mock_arch="${4:-amd64}"

	# shellcheck source=/dev/null
	source "${target_script}"
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
	local arch_val="${6:-}"

	mkdir -p -- "${dest_dir}"
	cat > "${dest_dir}/mock_os_release" <<- EOF
		ID=${os_id_val}
		VERSION_CODENAME=${codename_val}
		VERSION_ID=${version_val}
	EOF

	cp -f -- "${target_script}" "${dest_dir}/qbt-nox-static.bash"
	sed -i "s|source /etc/os-release|source \"${dest_dir}/mock_os_release\"|g" "${dest_dir}/qbt-nox-static.bash"

	if [[ ${os_id_val} == "alpine" ]]; then
		local alpine_arch="${arch_val:-x86_64}"
		local ver_cmp=">"
		if [[ ${version_val} == "3.18" ]]; then
			ver_cmp="="
		elif [[ "$(printf '%s\n%s\n' "${version_val}" "3.18" | sort -V | head -n1)" == "${version_val}" ]]; then
			ver_cmp="<"
		fi
		sed -i "s|apk --print-arch|printf '%s' '${alpine_arch}'|g" "${dest_dir}/qbt-nox-static.bash"
		sed -i "s|apk version -t \"\${os_version_id}\" \"3.18\"|printf '%s' '${ver_cmp}'|g" "${dest_dir}/qbt-nox-static.bash"
	else
		local deb_arch="${arch_val:-amd64}"
		sed -i "s|dpkg --print-architecture|printf '%s' '${deb_arch}'|g" "${dest_dir}/qbt-nox-static.bash"
	fi

	if [[ ${offline_stubs} == "yes" ]]; then
		awk '
			/^[[:space:]]*_check_dependencies "\$\{@\}"/ {
				print "\tfiltered_check_dependency_args=(\"$@\")"
				print "\t_test_url() { test_url_status=\"200\"; }"
				print "\t_script_version() { return 0; }"
				print "\t_curl() { return 1; }"
				print "\t_git_git() { return 1; }"
				print "\t_set_module_urls() {"
				print "\t  github_url[glibc]=\"https://sourceware.org/git/glibc.git\""
				print "\t  github_url[zlib]=\"https://github.com/madler/zlib.git\""
				print "\t  github_url[iconv]=\"https://https.git.savannah.gnu.org/git/libiconv.git\""
				print "\t  github_url[icu]=\"https://github.com/unicode-org/icu.git\""
				print "\t  github_url[double_conversion]=\"https://github.com/google/double-conversion.git\""
				print "\t  github_url[openssl]=\"https://github.com/openssl/openssl.git\""
				print "\t  github_url[boost]=\"https://github.com/boostorg/boost.git\""
				print "\t  github_url[libtorrent]=\"https://github.com/arvidn/libtorrent.git\""
				print "\t  github_url[qtbase]=\"https://github.com/qt/qtbase.git\""
				print "\t  github_url[qttools]=\"https://github.com/qt/qttools.git\""
				print "\t  github_url[qbittorrent]=\"https://github.com/qbittorrent/qBittorrent.git\""
				print "\t  github_tag[glibc]=\"glibc-2.44\"; app_version[glibc]=\"2.44\""
				print "\t  github_tag[zlib]=\"v1.3.2\"; app_version[zlib]=\"1.3.2\""
				print "\t  github_tag[iconv]=\"v1.19\"; app_version[iconv]=\"1.19\""
				print "\t  github_tag[icu]=\"release-76-1\"; app_version[icu]=\"76-1\""
				print "\t  github_tag[double_conversion]=\"v3.3.1\"; app_version[double_conversion]=\"3.3.1\""
				print "\t  github_tag[openssl]=\"openssl-3.5.9\"; app_version[openssl]=\"3.5.9\""
				print "\t  github_tag[boost]=\"boost-1.88.0\"; app_version[boost]=\"1.88.0\""
				print "\t  github_tag[libtorrent]=\"v2.0.11\"; app_version[libtorrent]=\"2.0.11\""
				print "\t  github_tag[qtbase]=\"v6.8.2\"; app_version[qtbase]=\"6.8.2\""
				print "\t  github_tag[qttools]=\"v6.8.2\"; app_version[qttools]=\"6.8.2\""
				print "\t  github_tag[qbittorrent]=\"release-5.1.0\"; app_version[qbittorrent]=\"5.1.0\""
				print "\t  qt_version_short_array=(6 8); qt_version_short=\"6.8\""
				print "\t  source_default[glibc]=\"file\"; source_default[zlib]=\"file\"; source_default[iconv]=\"file\""
				print "\t  source_default[icu]=\"file\"; source_default[openssl]=\"file\"; source_default[boost]=\"file\""
				print "\t  source_default[libtorrent]=\"file\"; source_default[qtbase]=\"file\""
				print "\t  source_default[qttools]=\"file\"; source_default[qbittorrent]=\"file\""
				print "\t  source_archive_url[zlib]=\"https://example.invalid/zlib.tar.gz\""
				print "\t  source_archive_url[openssl]=\"https://example.invalid/openssl.tar.gz\""
				print "\t  source_archive_url[boost]=\"https://example.invalid/boost.tar.xz\""
				print "\t  source_archive_url[libtorrent]=\"https://example.invalid/libtorrent.tar.gz\""
				print "\t  source_archive_url[qtbase]=\"https://example.invalid/qtbase.tar.xz\""
				print "\t  source_archive_url[qttools]=\"https://example.invalid/qttools.tar.xz\""
				print "\t  source_archive_url[qbittorrent]=\"https://example.invalid/qbittorrent.tar.gz\""
				print "\t}"
				print "\tset -- \"${filtered_check_dependency_args[@]}\""
				next
			}
			{ print }
		' "${dest_dir}/qbt-nox-static.bash" > "${dest_dir}/qbt-nox-static.bash.tmp"
		mv -f -- "${dest_dir}/qbt-nox-static.bash.tmp" "${dest_dir}/qbt-nox-static.bash"
	fi

	chmod +x -- "${dest_dir}/qbt-nox-static.bash"
}

printf '\n=== 1. Semantic Version Tests ===\n'
(
	load_lib
	for pair in \
		"v prefix|1.2.20|v1.2.20" \
		"release- prefix|5.1.0|release-5.1.0" \
		"boost- prefix|1.88.0|boost-1.88.0" \
		"openssl- prefix|3.5.9|openssl-3.5.9" \
		"libtorrent- prefix|1.2.20|libtorrent-1_2_20" \
		"libtorrent_ prefix|1.2.20|libtorrent_1_2_20" \
		"glibc- prefix|2.44|glibc-2.44" \
		"dash-separated icu release-76-1|76.1|release-76-1" \
		"single component version|6.0.0|6" \
		"two component version|2.44.0|2.44" \
		"RC_1_1 elevates to 1.1.999|1.1.999|RC_1_1" \
		"RC_1_2 elevates to 1.2.999|1.2.999|RC_1_2" \
		"RC_2_0 elevates to 2.0.999|2.0.999|RC_2_0" \
		"RC_2_1 elevates to 2.1.999|2.1.999|RC_2_1" \
		"v5_1_x elevates to 5.1.999|5.1.999|v5_1_x" \
		"v6_8_x elevates to 6.8.999|6.8.999|v6_8_x" \
		"master/MAIN equal max|master|MAIN" \
		"latest equals master|master|latest" \
		"Latest case-insensitive|master|Latest"; do
		IFS='|' read -r label lhs rhs <<< "${pair}"
		lhs_v="$(_semantic_version "${lhs}")"
		lhs_rc=$?
		rhs_v="$(_semantic_version "${rhs}")"
		rhs_rc=$?
		assert_pass_eq "semver ${label}" "$((lhs_rc | rhs_rc))" "${lhs_v}" "${rhs_v}"
	done

	v1="$(_semantic_version "5.1.0")"
	v2="$(_semantic_version "5.1.0.1")"
	v3="$(_semantic_version "5.1.1")"
	v4="$(_semantic_version "5.2.0")"
	if ((v1 < v2 && v2 < v3 && v3 < v4)); then
		pass "semver 4-component monotonic ordering 5.1.0 < 5.1.0.1 < 5.1.1 < 5.2.0"
	else
		fail "semver 4-component ordering" "got ${v1}, ${v2}, ${v3}, ${v4}"
	fi

	v_lt12="$(_semantic_version "v1.2.20")"
	v_rc12="$(_semantic_version "RC_1_2")"
	v_lt20="$(_semantic_version "v2.0.0")"
	v_rc20="$(_semantic_version "RC_2_0")"
	v_lt21="$(_semantic_version "v2.1.0")"
	v_rc21="$(_semantic_version "RC_2_1")"
	v_mast="$(_semantic_version "master")"
	if ((v_lt12 < v_rc12 && v_rc12 < v_lt20 && v_lt20 < v_rc20 && v_rc20 < v_lt21 && v_lt21 < v_rc21 && v_rc21 < v_mast)); then
		pass "semver branch progression v1.2.20 < RC_1_2 < v2.0.0 < RC_2_0 < v2.1.0 < RC_2_1 < master"
	else
		fail "semver branch progression" "unexpected ordering"
	fi

	v_alpha1="$(_semantic_version "2.1.0-alpha1")"
	v_alpha2="$(_semantic_version "2.1.0-alpha2")"
	v_beta1="$(_semantic_version "boost-2.1.0.beta1")"
	v_beta2="$(_semantic_version "boost-2.1.0.beta2")"
	v_rc1="$(_semantic_version "2.1.0_rc1")"
	v_rc2="$(_semantic_version "2.1.0_rc2")"
	v_final="$(_semantic_version "2.1.0")"
	if ((v_alpha1 < v_alpha2 && v_alpha2 < v_beta1 && v_beta1 < v_beta2 && v_beta2 < v_rc1 && v_rc1 < v_rc2 && v_rc2 < v_final)); then
		pass "semver prerelease ordering alpha1 < alpha2 < beta1 < beta2 < rc1 < rc2 < final"
	else
		fail "semver prerelease ordering" "got ${v_alpha1} ${v_alpha2} ${v_beta1} ${v_beta2} ${v_rc1} ${v_rc2} ${v_final}"
	fi

	# Dash-separated version with prerelease suffix (e.g. ICU release-77-1-rc1 < release-77-1)
	v_icu_rc="$(_semantic_version "release-77-1-rc1")"
	v_icu_rel="$(_semantic_version "release-77-1")"
	if ((v_icu_rc < v_icu_rel)); then
		pass "semver dash-separated prerelease release-77-1-rc1 ranks below release-77-1"
	else
		fail "semver dash-separated prerelease" "${v_icu_rc} not < ${v_icu_rel}"
	fi

	v_octal="$(_semantic_version "0.8.9")"
	v_octal_pad="$(_semantic_version "0.08.09")"
	pad_rc=$?
	v_higher="$(_semantic_version "0.9.0")"
	assert_pass_eq "semver leading zeros 0.08.09 equals 0.8.9" "${pad_rc}" "${v_octal}" "${v_octal_pad}"
	if [[ ${v_octal} -lt ${v_higher} ]]; then
		pass "semver handles leading zero and 8/9 without octal errors"
	else
		fail "semver octal safety" "${v_octal} not < ${v_higher}"
	fi

	v_empty="$(_semantic_version "")"
	rc_empty=$?
	assert_match "semver empty string returns numeric value" "${rc_empty}" "${v_empty}" '^[0-9]+$'
	v_nonnum="$(_semantic_version "feature-branch")"
	rc_nonnum=$?
	assert_match "semver non-numeric string returns numeric value" "${rc_nonnum}" "${v_nonnum}" '^[0-9]+$'

	save_counts
)
load_counts

printf '\n=== 2. C++ Standard Resolution & Iconv Check Tests ===\n'
(
	load_lib "ubuntu" "resolute" "26.04" "amd64"

	for std_case in \
		"v1.1.14|1.1.14|release-4.3.2|4.3.2|5.15|14" \
		"v1.2.18|1.2.18|release-4.3.2|4.3.2|5.15|17" \
		"v1.2.18|1.2.18|release-4.5.2|4.5.2|5.15|17" \
		"v2.0.9|2.0.9|release-4.5.2|4.5.2|5.15|17" \
		"v2.0.11|2.0.11|release-4.5.2|4.5.2|6.8|17" \
		"v1.2.20|1.2.20|release-5.1.0|5.1.0|6.8|20" \
		"v2.0.11|2.0.11|release-5.1.0|5.1.0|6.8|20" \
		"v2.1.0|2.1.0|release-5.1.0|5.1.0|6.8|23" \
		"v2.0.11|2.0.11|release-5.2.0|5.2.0|6.8|23" \
		"RC_2_1|RC_2_1|master|master|6|23" \
		"custom-feature-branch|custom-feature-branch|release-4.3.2|4.3.2|6|17"; do
		IFS='|' read -r lt_t lt_v qbt_t qbt_v qt_v exp_std <<< "${std_case}"
		github_tag[libtorrent]="${lt_t}"
		app_version[libtorrent]="${lt_v}"
		github_tag[qbittorrent]="${qbt_t}"
		app_version[qbittorrent]="${qbt_v}"
		qbt_qt_version="${qt_v}"
		_set_cxx_standard
		rc=$?
		assert_pass_eq "cxx standard lt ${lt_v} + qbt ${qbt_v} + qt ${qt_v} = ${exp_std}" "${rc}" "${exp_std}" "${qbt_standard}"
	done

	# _resolve_app_cxx_val picks higher of tag vs app_version
	github_tag[libtorrent]="v1.2.18"
	app_version[libtorrent]="2.1.0"
	res_val="$(_resolve_app_cxx_val "libtorrent" "cxx_version_map" "17")"
	res_rc=$?
	assert_pass_eq "_resolve_app_cxx_val uses higher of tag vs version" "${res_rc}" "23" "${res_val}"

	# Incompatible combo 1: Qt5 (cap 17) vs qbt 5.1.0 (floor 20) + release_info_dir & GITHUB_REPOSITORY markers + symlink protection
	release_info_dir="${test_root}/rel_incompat"
	gh_marker_dir="${test_root}/gh_marker_wd"
	mkdir -p -- "${release_info_dir}" "${gh_marker_dir}"
	github_tag[libtorrent]="v2.0.11"
	app_version[libtorrent]="2.0.11"
	github_tag[qbittorrent]="release-5.1.0"
	app_version[qbittorrent]="5.1.0"
	qbt_qt_version="5.15"
	incompat_out="$(
		cd "${gh_marker_dir}" || exit 1
		GITHUB_REPOSITORY="owner/repo" _set_cxx_standard 2>&1
	)"
	incompat_rc=$?
	assert_fail_contains "cxx standard incompatible Qt5 + qbt 5.1 exits 1 with message" "${incompat_rc}" "${incompat_out}" "Incompatible C++ standards"
	assert_file_exists "cxx standard creates release_info_dir/disable-qt5 on conflict" "${release_info_dir}/disable-qt5"
	assert_file_exists "cxx standard creates cwd disable-qt5 when GITHUB_REPOSITORY set" "${gh_marker_dir}/disable-qt5"

	# Incompatible combo 2: lt 1.2.19 (floor 20) vs qbt 4.5.2 (cap 17)
	github_tag[libtorrent]="v1.2.19"
	app_version[libtorrent]="1.2.19"
	github_tag[qbittorrent]="release-4.5.2"
	app_version[qbittorrent]="4.5.2"
	qbt_qt_version="6.8"
	(_set_cxx_standard > /dev/null 2>&1)
	assert_exit "cxx standard incompatible lt 1.2.19 (20) + qbt 4.5.2 (cap 17) exits 1" 1 "$?"

	# Incompatible combo 3: lt 2.1.0 (floor 23) vs qbt 4.5.2 (cap 17)
	github_tag[libtorrent]="v2.1.0"
	app_version[libtorrent]="2.1.0"
	github_tag[qbittorrent]="release-4.5.2"
	app_version[qbittorrent]="4.5.2"
	qbt_qt_version="6.8"
	(_set_cxx_standard > /dev/null 2>&1)
	assert_exit "cxx standard incompatible lt 2.1.0 (23) + qbt 4.5.2 (cap 17) exits 1" 1 "$?"

	# Incompatible combo 4: OS cap restriction
	(
		cxx_os_cap["resolute"]=17
		github_tag[libtorrent]="v2.0.11"
		app_version[libtorrent]="2.0.11"
		github_tag[qbittorrent]="release-5.1.0"
		app_version[qbittorrent]="5.1.0"
		qbt_qt_version="6.8"
		_set_cxx_standard > /dev/null 2>&1
	)
	assert_exit "cxx standard respects OS ceiling cap" 1 "$?"

	# _libtorrent_v2_iconv_check matrix
	for combo in "1.1:v1.1.14:keep" "1.2:v1.2.20:keep" "2.0:v2.0.11:del" "2.1:v2.1.0:del" "2.0:RC_1_1:keep" "2.0:RC_1_2:keep" "2.1:RC_2_1:del" "2.1:v1.2.20:keep"; do
		IFS=':' read -r lt_v lt_t expect <<< "${combo}"
		qbt_libtorrent_version="${lt_v}"
		github_tag[libtorrent]="${lt_t}"
		_libtorrent_v2_iconv_check
		if [[ ${expect} == "keep" ]]; then
			assert_eq "iconv kept for ver=${lt_v} tag=${lt_t}" "" "${qbt_modules_delete[iconv]:-}"
		else
			assert_eq "iconv deleted for ver=${lt_v} tag=${lt_t}" "true" "${qbt_modules_delete[iconv]:-}"
		fi
	done

	save_counts
)
load_counts

printf '\n=== 3. Default Values, OS Info, Env Display & Build Directory Tests ===\n'
(
	# get_os_info strips Alpine _alpha suffix, handles missing file, rejects bad var names, and does not pollute caller globals
	(
		load_lib
		mock_osr="${test_root}/osr_alpine"
		printf 'ID=alpine\nVERSION_ID=3.21.0_alpha20241201\nPRETTY_NAME="Alpine Linux"\n' > "${mock_osr}"
		eval "$(declare -f get_os_info | sed "s|/etc/os-release|${mock_osr}|g")"
		unset ID PRETTY_NAME
		id_val="$(get_os_info ID)"
		id_rc=$?
		assert_pass_eq "get_os_info returns ID" "${id_rc}" "alpine" "${id_val}"
		ver_val="$(get_os_info VERSION_ID)"
		ver_rc=$?
		assert_pass_eq "get_os_info strips Alpine _alpha suffix" "${ver_rc}" "3.21.0" "${ver_val}"
		get_os_info ID > /dev/null
		assert_eq "get_os_info does not leak PRETTY_NAME into caller scope" "" "${PRETTY_NAME:-}"
		bad_key="$(get_os_info "1INVALID")"
		bad_rc=$?
		assert_pass_eq "get_os_info rejects invalid identifier" "${bad_rc}" "unknown" "${bad_key}"
		empty_key="$(get_os_info "")"
		empty_rc=$?
		assert_pass_eq "get_os_info rejects empty key" "${empty_rc}" "unknown" "${empty_key}"
		eval "$(declare -f get_os_info | sed "s|${mock_osr}|${test_root}/no_such_osr|g")"
		miss_val="$(get_os_info ID)"
		miss_rc=$?
		assert_pass_eq "get_os_info returns unknown when file missing" "${miss_rc}" "unknown" "${miss_val}"
		save_counts
	)
	load_counts

	# _short_path exact prefix boundary checks
	(
		load_lib
		assert_pass_eq "_short_path exact home match returns ~" 0 "~" "$(_short_path "/home/bob" "/home/bob")"
		# shellcheck disable=SC2088
		assert_pass_eq "_short_path home child returns ~/sub" 0 "~/sub" "$(_short_path "/home/bob/sub" "/home/bob")"
		assert_pass_eq "_short_path sibling prefix /home/al vs /home/alice unchanged" 0 "/home/alice/build" "$(_short_path "/home/alice/build" "/home/al")"
		assert_pass_eq "_short_path root HOME=/ leaves /work/build unchanged" 0 "/work/build" "$(_short_path "/work/build" "/")"
		save_counts
	)
	load_counts

	# Default Ubuntu cmake + qt6 + locale exports + mold/cache/deps
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values
		assert_exit "_set_default_values ubuntu exits 0" 0 "$?"
		assert_eq "ubuntu exports LANG=C.UTF-8" "C.UTF-8" "${LANG}"
		assert_eq "ubuntu exports DEBIAN_FRONTEND=noninteractive" "noninteractive" "${DEBIAN_FRONTEND}"
		assert_eq "default build tool is cmake" "cmake" "${qbt_build_tool}"
		assert_eq "default qt version is 6" "6" "${qbt_qt_version}"
		assert_eq "default use_qt6 is ON" "ON" "${qbt_use_qt6}"
		assert_eq "default libtorrent version is 2.1" "2.1" "${qbt_libtorrent_version}"
		assert_eq "default ubuntu LTO is yes" "yes" "${qbt_use_lto}"
		assert_eq "default linker mold is no" "no" "${qbt_linker_mold}"
		assert_eq "default ubuntu cross_tool_dir is /usr/bin" "/usr/bin" "${qbt_cross_tool_dir}"
		assert_eq "default native cross_arch matches uname -m" "$(uname -m)" "${cross_arch}"
		assert_eq "default deletes install module" "true" "${qbt_modules_delete[install]:-}"
		assert_eq "default deletes icu module" "true" "${qbt_modules_delete[icu]:-}"
		assert_eq "default deletes autopoint/gperf when cache empty" "true:true" "${qbt_deps_delete[autopoint]:-}:${qbt_deps_delete[gperf]:-}"
		assert_eq "default ubuntu cmake build type is Release" "Release" "${qbt_cmake_build_type}"
		assert_eq "default openssl build type is --release" "--release" "${qbt_openssl_build_type}"
		save_counts
	)
	load_counts

	# First arg install keeps install module
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values install
		assert_eq "first arg install keeps install module" "" "${qbt_modules_delete[install]:-}"
		save_counts
	)
	load_counts

	# Absolute -b path, ~ expansion, Alpine QBT_MCM_DOCKER=NO vs YES, QBT_CROSS_NAME override
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_build_dir="/tmp/custom-abs-build/"
		# shellcheck disable=SC2088
		qbt_cache_dir="~/my-cache/"
		QBT_CROSS_NAME="aarch64"
		qbt_cross_name="x86"
		_set_default_values > /dev/null
		assert_eq "absolute qbt_build_dir not prefixed with pwd" "/tmp/custom-abs-build" "${qbt_install_dir}"
		assert_eq "alpine qbt_mcm_dir matches absolute install dir" "/tmp/custom-abs-build" "${qbt_mcm_dir}"
		assert_eq "alpine qbt_cross_tool_dir matches absolute install dir" "/tmp/custom-abs-build/bin" "${qbt_cross_tool_dir}"
		assert_eq "qbt_host_deps_path matches absolute install dir" "/tmp/custom-abs-build/host_deps" "${qbt_host_deps_path}"
		assert_eq "tilde expanded in qbt_cache_dir" "${HOME}/my-cache" "${qbt_cache_dir}"
		assert_eq "QBT_CROSS_NAME overrides qbt_cross_name" "aarch64" "${qbt_cross_name}"
		assert_eq "alpine deletes glibc module" "true" "${qbt_modules_delete[glibc]:-}"
		assert_eq "alpine with cache keeps coreutils and gpg" ":" "${qbt_deps_delete[coreutils]:-}:${qbt_deps_delete[gpg]:-}"
		save_counts
	)
	load_counts

	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		QBT_MCM_DOCKER="YES"
		_set_default_values
		assert_eq "QBT_MCM_DOCKER=YES sets qbt_mcm_dir=/usr/local" "/usr/local" "${qbt_mcm_dir}"
		assert_eq "QBT_MCM_DOCKER=YES sets qbt_cross_tool_dir=/usr/local/bin" "/usr/local/bin" "${qbt_cross_tool_dir}"
		assert_eq "alpine without cache deletes coreutils and gpg" "true:true" "${qbt_deps_delete[coreutils]:-}:${qbt_deps_delete[gpg]:-}"
		save_counts
	)
	load_counts

	# Qt version and build tool matrix
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_qt_version="5.15"
		qbt_build_tool="cmake"
		qbt_build_tool_cli="cmake"
		_set_default_values
		assert_eq "CLI -c overrides qbt_qt_version=5.15 to cmake" "cmake" "${qbt_build_tool}"
		assert_eq "CLI -c upgrades qbt_qt_version=5.15 to 6" "6" "${qbt_qt_version}"
		assert_eq "CLI -c sets qbt_use_qt6=ON" "ON" "${qbt_use_qt6}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_qt_version="6"
		qbt_build_tool="qmake"
		qbt_build_tool_cli="qmake"
		_set_default_values
		assert_eq "CLI -q overrides qbt_qt_version=6 to qmake" "qmake" "${qbt_build_tool}"
		assert_eq "CLI -q switches qbt_qt_version=6 to 5" "5" "${qbt_qt_version}"
		assert_eq "CLI -q sets qbt_use_qt6=OFF" "OFF" "${qbt_use_qt6}"
		assert_eq "qmake deletes cmake/ninja/graphviz/double_conversion" "true:true:true" "${qbt_deps_delete[cmake]:-}:${qbt_deps_delete["ninja-build"]:-}:${qbt_modules_delete[double_conversion]:-}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_qt_version="5.15"
		qbt_workflow_files="yes"
		_set_default_values
		assert_eq "qbt_qt_version=5.15 selects qmake" "qmake" "${qbt_build_tool}"
		assert_eq "qbt_qt_version=5.15 disables workflow files" "no" "${qbt_workflow_files}"
		assert_eq "qbt_qt_version=5.15 sets qbt_use_qt6=OFF" "OFF" "${qbt_use_qt6}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_qt_version="6.8"
		qbt_workflow_files="yes"
		_set_default_values
		assert_eq "qbt_qt_version=6.8 keeps cmake" "cmake" "${qbt_build_tool}"
		assert_eq "qbt_qt_version=6.8 disables workflow files" "no" "${qbt_workflow_files}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_qt_version=""
		qbt_build_tool="qmake"
		_set_default_values
		assert_eq "empty qt + qmake defaults qt to 5" "5" "${qbt_qt_version}"
		assert_eq "empty qt + qmake sets qbt_use_qt6=OFF" "OFF" "${qbt_use_qt6}"
		save_counts
	)
	load_counts

	# host_deps / qemu / icu module deletion & flag-argument isolation matrix
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="default"
		qbt_with_qemu="no"
		_set_default_values
		assert_eq "native qbt_with_qemu=no deletes icu_host_deps" "true" "${qbt_modules_delete[icu_host_deps]:-}"
		assert_eq "native qbt_with_qemu=no deletes qtbase_host_deps" "true" "${qbt_modules_delete[qtbase_host_deps]:-}"
		assert_eq "native qbt_with_qemu=no deletes qttools_host_deps" "true" "${qbt_modules_delete[qttools_host_deps]:-}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="aarch64"
		qbt_with_qemu="no"
		qbt_host_deps="no"
		_set_default_values > /dev/null
		assert_eq "cross qemu=no skip_icu=yes deletes icu_host_deps" "true" "${qbt_modules_delete[icu_host_deps]:-}"
		assert_eq "cross qemu=no host_deps=no keeps qtbase_host_deps" "" "${qbt_modules_delete[qtbase_host_deps]:-}"
		assert_eq "cross qemu=no host_deps=no keeps qttools_host_deps" "" "${qbt_modules_delete[qttools_host_deps]:-}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="aarch64"
		qbt_with_qemu="no"
		qbt_host_deps="yes"
		_set_default_values > /dev/null
		assert_eq "cross qemu=no host_deps=yes deletes qtbase_host_deps" "true" "${qbt_modules_delete[qtbase_host_deps]:-}"
		assert_eq "cross host_deps=yes deletes build-essential on debian" "true" "${qbt_deps_delete["build-essential"]:-}"
		assert_eq "cross host_deps=yes adds libc6-dev/make/patch" "false:false:false" "${qbt_core_deps["libc6-dev"]:-}:${qbt_core_deps[make]:-}:${qbt_core_deps[patch]:-}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="aarch64"
		qbt_with_qemu="no"
		_set_default_values icu > /dev/null
		assert_eq "cross qbt_with_qemu=no positional icu keeps icu_host_deps" "" "${qbt_modules_delete[icu_host_deps]:-}"
		assert_eq "cross qbt_with_qemu=no positional icu sets qbt_skip_icu=no" "no" "${qbt_skip_icu}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values -qt icu -pr "owner/repo icu" > /dev/null
		assert_eq "icu as value of -qt or -pr does NOT enable icu module" "yes" "${qbt_skip_icu}"
		_set_default_values -- icu > /dev/null
		assert_eq "icu after -- enables icu module" "no" "${qbt_skip_icu}"
		save_counts
	)
	load_counts

	# Alpine vs Debian mold core_deps + LTO + Debug + static-ish
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_cross_name="aarch64"
		qbt_mcm_url="userdocs/qbt-musl-cross-make"
		qbt_linker_mold="yes"
		_set_default_values > /dev/null
		assert_eq "alpine cross with qbt-musl-cross-make disables LTO" "no" "${qbt_use_lto}"
		assert_eq "alpine cross mold does NOT add host mold package" "" "${qbt_core_deps[mold]:-}"
		assert_eq "alpine cross with qemu deletes build-base" "true" "${qbt_deps_delete["build-base"]:-}"
		save_counts
	)
	load_counts

	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_cross_name="default"
		qbt_linker_mold="yes"
		_set_default_values
		assert_eq "alpine native mold adds host mold package" "false" "${qbt_core_deps[mold]:-}"
		assert_eq "alpine native enables LTO" "yes" "${qbt_use_lto}"
		save_counts
	)
	load_counts

	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_cross_name="aarch64"
		qbt_mcm_url="userdocs/musl-cross-make"
		_set_default_values > /dev/null
		assert_eq "alpine cross with musl-cross-make enables LTO" "yes" "${qbt_use_lto}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_use_lto="no"
		qbt_linker_mold="yes"
		qbt_static_ish="yes"
		_set_default_values
		assert_eq "explicit qbt_use_lto=no honored on ubuntu" "no" "${qbt_use_lto}"
		assert_eq "ubuntu mold adds mold core dep" "false" "${qbt_core_deps[mold]:-}"
		assert_eq "ubuntu static-ish deletes glibc module" "true" "${qbt_modules_delete[glibc]:-}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_build_debug="yes"
		_set_default_values
		assert_eq "debug disables strip" "no" "${qbt_optimise_strip}"
		assert_eq "debug disables LTO" "no" "${qbt_use_lto}"
		assert_eq "debug sets CMAKE_BUILD_TYPE=Debug" "Debug" "${qbt_cmake_build_type}"
		assert_eq "debug sets qbt_cmake_debug=ON" "ON" "${qbt_cmake_debug}"
		assert_eq "debug sets qbt_openssl_build_type=--debug" "--debug" "${qbt_openssl_build_type}"
		assert_eq "debug sets qbt_libtorrent_debug" "debug-symbols=on" "${qbt_libtorrent_debug}"
		assert_eq "debug sets qbt_qbittorrent_debug" "--enable-debug" "${qbt_qbittorrent_debug}"
		save_counts
	)
	load_counts

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

	# _print_env basic vs advanced view
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values
		qbt_advanced_view="no"
		out_basic="$(_print_env)"
		rc_basic=$?
		assert_contains "_print_env basic shows qbt_libtorrent_version" "${rc_basic}" "${out_basic}" "qbt_libtorrent_version="
		assert_not_contains "_print_env basic hides qbt_use_lto" "${rc_basic}" "${out_basic}" "qbt_use_lto="
		qbt_advanced_view="yes"
		out_adv="$(_print_env)"
		rc_adv=$?
		assert_contains "_print_env advanced shows qbt_use_lto" "${rc_adv}" "${out_adv}" "qbt_use_lto="
		assert_contains "_print_env advanced shows qbt_linker_mold" "${rc_adv}" "${out_adv}" "qbt_linker_mold="
		assert_contains "_print_env advanced shows qbt_with_qemu" "${rc_adv}" "${out_adv}" "qbt_with_qemu="
		save_counts
	)
	load_counts

	# _set_build_directory updates HOME, PATH, PKG_CONFIG_PATH, include_dir, lib_dir
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		orig_home="${HOME}"
		qbt_working_dir="${test_root}/wd"
		qbt_working_dir_short="${qbt_working_dir}"
		qbt_local_paths="/usr/bin:/bin"
		qbt_build_dir="${test_root}/my-build"
		_set_build_directory
		assert_eq "_set_build_directory uses an absolute path as the install dir" "${test_root}/my-build" "${qbt_install_dir}"
		assert_eq "_set_build_directory sets HOME to install dir" "${test_root}/my-build" "${HOME}"
		assert_eq "_set_build_directory preserves LOCAL_USER_HOME" "${orig_home}" "${LOCAL_USER_HOME}"
		assert_eq "_set_build_directory sets PKG_CONFIG_PATH" "${test_root}/my-build/lib/pkgconfig" "${PKG_CONFIG_PATH}"
		assert_eq "_set_build_directory prepends install/bin to PATH" "${test_root}/my-build/bin:/usr/bin:/bin" "${PATH}"

		qbt_build_dir="rel-build"
		_set_build_directory
		assert_eq "_set_build_directory resolves relative path against qbt_working_dir" "${test_root}/wd/rel-build" "${qbt_install_dir}"
		assert_eq "_set_build_directory second call preserves original LOCAL_USER_HOME" "${orig_home}" "${LOCAL_USER_HOME}"

		qbt_build_dir="${orig_home}/sub-build"
		_set_build_directory
		# shellcheck disable=SC2088
		assert_eq "_set_build_directory formats qbt_install_dir_short against LOCAL_USER_HOME" "~/sub-build" "${qbt_install_dir_short}"

		qbt_local_paths=""
		# shellcheck disable=SC2123
		PATH=""
		_set_build_directory
		assert_eq "_set_build_directory with empty qbt_local_paths avoids trailing colon in PATH" "${orig_home}/sub-build/bin" "${PATH}"
		save_counts
	)
	load_counts

	# qbt_build_dir ~ expansion and trailing slash handling happen once, in _set_default_values
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		# shellcheck disable=SC2088
		qbt_build_dir="~/tilde-build///"
		# shellcheck disable=SC2088
		qbt_cache_dir="~/tilde-cache///"
		_set_default_values > /dev/null
		assert_eq "tilde expanded and multiple trailing slashes stripped in qbt_build_dir" "${HOME}/tilde-build" "${qbt_install_dir}"
		assert_eq "tilde expanded and multiple trailing slashes stripped in qbt_cache_dir" "${HOME}/tilde-cache" "${qbt_cache_dir}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_build_dir="/"
		_set_default_values > /dev/null
		assert_eq "qbt_build_dir / keeps the root slash" "/" "${qbt_install_dir}"
		save_counts
	)
	load_counts

	# Positional icu_host_deps enables icu + relative qbt_cache_dir resolves against qbt_working_dir
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="aarch64"
		qbt_with_qemu="no"
		qbt_cache_dir="rel/cache/"
		_set_default_values icu_host_deps > /dev/null
		assert_eq "positional icu_host_deps sets qbt_skip_icu=no" "no" "${qbt_skip_icu}"
		assert_eq "positional icu_host_deps keeps icu_host_deps" "" "${qbt_modules_delete[icu_host_deps]:-}"
		assert_eq "relative qbt_cache_dir resolved and trailing slash stripped" "${qbt_working_dir}/rel/cache" "${qbt_cache_dir}"
		save_counts
	)
	load_counts

	save_counts
)
load_counts

printf '\n=== 4. Compiler & Linker Flags (_custom_flags) Tests ===\n'
(
	# 4a. Cross Debian/Ubuntu riscv64 + LTO + mold + glibc + host_deps + static-ish
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
		CXXFLAGS="-DUSER_CXXFLAG"
		CPPFLAGS="-DUSER_CPPFLAG"
		LDFLAGS="-Wl,--user-ld"

		# Normal library module (zlib)
		app_name="zlib"
		_custom_flags
		rc=$?
		assert_contains "zlib Debian static CFLAGS has -B lib_dir" "${rc}" "${CFLAGS}" "-B${lib_dir}"
		assert_contains "zlib Debian static LDFLAGS has -B lib_dir" "${rc}" "${LDFLAGS}" "-B${lib_dir}"
		assert_contains "zlib CFLAGS keeps -fno-plt" "${rc}" "${CFLAGS}" "-fno-plt"
		assert_contains "zlib CFLAGS keeps -flto=auto" "${rc}" "${CFLAGS}" "-flto=auto"
		assert_contains "zlib LDFLAGS has -fuse-ld=mold" "${rc}" "${LDFLAGS}" "-fuse-ld=mold"
		assert_contains "zlib CFLAGS appends user CFLAGS" "${rc}" "${CFLAGS}" "-DUSER_CFLAG"
		assert_contains "zlib CXXFLAGS appends user CXXFLAGS and -std=c++20" "${rc}" "${CXXFLAGS}" "-std=c++20"
		assert_contains "zlib CPPFLAGS appends user CPPFLAGS" "${rc}" "${CPPFLAGS}" "-DUSER_CPPFLAG"
		assert_not_contains "zlib library LDFLAGS omits executable hardening -z,relro" "${rc}" "${LDFLAGS}" "-z,relro"
		assert_not_contains "cross build on amd64 omits -fcf-protection=full" "${rc}" "${CFLAGS}" "-fcf-protection=full"
		assert_not_contains "glibc 2.44 omits -D_FORTIFY_SOURCE=3" "${rc}" "${CPPFLAGS}" "-D_FORTIFY_SOURCE=3"
		assert_eq "cross zlib AR uses cross gcc-ar" "/usr/bin/riscv64-linux-gnu-gcc-ar" "${AR}"
		assert_eq "cross zlib NM uses cross gcc-nm" "/usr/bin/riscv64-linux-gnu-gcc-nm" "${NM}"
		assert_eq "cross zlib RANLIB uses cross gcc-ranlib" "/usr/bin/riscv64-linux-gnu-gcc-ranlib" "${RANLIB}"
		assert_eq "cross zlib CC uses cross gcc" "/usr/bin/riscv64-linux-gnu-gcc" "${CC}"
		assert_eq "cross zlib CXX uses cross g++" "/usr/bin/riscv64-linux-gnu-g++" "${CXX}"
		assert_eq "cross zlib CHOST set" "riscv64-linux-gnu" "${CHOST}"

		# Executable module (qbittorrent, icu, boost, qtbase) gets full linker hardening + LTO plugin
		for exe_mod in icu boost qtbase qbittorrent; do
			app_name="${exe_mod}"
			_custom_flags
			rc=$?
			assert_contains "${exe_mod} LDFLAGS includes -z,relro" "${rc}" "${LDFLAGS}" "-z,relro"
			assert_contains "${exe_mod} LDFLAGS includes -flto -fuse-linker-plugin" "${rc}" "${LDFLAGS}" "-flto -fuse-linker-plugin"
		done

		# Calling _custom_flags repeatedly must NOT duplicate user flags
		app_name="zlib"
		_custom_flags
		tmp_cf="${CFLAGS}"
		cflag_count=0
		while [[ ${tmp_cf} == *"-DUSER_CFLAG"* ]]; do
			((cflag_count++))
			tmp_cf="${tmp_cf#*-DUSER_CFLAG}"
		done
		assert_eq "user CFLAGS not duplicated across _custom_flags calls" "1" "${cflag_count}"

		# openssl excludes LTO and uses non-LTO cross binutils
		app_name="openssl"
		_custom_flags
		rc=$?
		assert_not_contains "openssl excludes -flto=auto" "${rc}" "${CFLAGS}" "-flto=auto"
		assert_eq "openssl AR uses non-LTO cross ar" "/usr/bin/riscv64-linux-gnu-ar" "${AR}"
		assert_eq "openssl NM uses non-LTO cross nm" "/usr/bin/riscv64-linux-gnu-nm" "${NM}"
		assert_eq "openssl RANLIB uses non-LTO cross ranlib" "/usr/bin/riscv64-linux-gnu-ranlib" "${RANLIB}"

		# glibc excludes -fno-plt, LTO, -B lib_dir, -static, and resets LDFLAGS
		app_name="glibc"
		_custom_flags
		rc=$?
		assert_not_contains "glibc CFLAGS excludes -fno-plt" "${rc}" "${CFLAGS}" "-fno-plt"
		assert_not_contains "glibc CXXFLAGS excludes -fno-plt" "${rc}" "${CXXFLAGS}" "-fno-plt"
		assert_not_contains "glibc CFLAGS excludes -flto" "${rc}" "${CFLAGS}" "-flto"
		assert_not_contains "glibc CFLAGS excludes -B lib_dir" "${rc}" "${CFLAGS}" "-B${lib_dir}"
		assert_not_contains "glibc CFLAGS excludes -static" "${rc}" "${CFLAGS}" "-static"
		assert_eq "glibc resets LDFLAGS to user qbt_ldflags only" "-Wl,--user-ld" "${LDFLAGS}"
		assert_eq "glibc AR uses non-LTO cross ar" "/usr/bin/riscv64-linux-gnu-ar" "${AR}"

		# *_host_deps uses /usr/bin host compilers + LTO wrappers, isolates -I/-L to qbt_host_deps_path, and omits -B lib_dir
		qbt_host_deps_path="${test_root}/build/host_deps"
		app_name="qtbase_host_deps"
		_custom_flags
		rc=$?
		assert_eq "host_deps CC uses /usr/bin/gcc" "/usr/bin/gcc" "${CC}"
		assert_eq "host_deps CXX uses /usr/bin/g++" "/usr/bin/g++" "${CXX}"
		assert_eq "host_deps AR uses /usr/bin/gcc-ar" "/usr/bin/gcc-ar" "${AR}"
		assert_eq "host_deps NM uses /usr/bin/gcc-nm" "/usr/bin/gcc-nm" "${NM}"
		assert_eq "host_deps RANLIB uses /usr/bin/gcc-ranlib" "/usr/bin/gcc-ranlib" "${RANLIB}"
		assert_eq "host_deps CHOST is empty" "" "${CHOST}"
		assert_not_contains "host_deps omits -B lib_dir" "${rc}" "${CFLAGS}" "-B${lib_dir}"
		assert_contains "host_deps CFLAGS uses qbt_host_deps_path/include" "${rc}" "${CFLAGS}" "-I${qbt_host_deps_path}/include"
		assert_not_contains "host_deps CFLAGS omits target include_dir" "${rc}" "${CFLAGS}" "-I${include_dir}"
		assert_contains "host_deps LDFLAGS uses qbt_host_deps_path/lib" "${rc}" "${LDFLAGS}" "-L${qbt_host_deps_path}/lib"
		assert_not_contains "host_deps LDFLAGS omits target lib_dir" "${rc}" "${LDFLAGS}" "-L${lib_dir}"

		# *_host_deps without LTO uses /usr/bin/ar, nm, ranlib
		qbt_use_lto="no"
		_custom_flags
		assert_eq "host_deps non-LTO AR uses /usr/bin/ar" "/usr/bin/ar" "${AR}"
		assert_eq "host_deps non-LTO NM uses /usr/bin/nm" "/usr/bin/nm" "${NM}"
		assert_eq "host_deps non-LTO RANLIB uses /usr/bin/ranlib" "/usr/bin/ranlib" "${RANLIB}"

		# Static-ish omits -static and -B lib_dir
		qbt_static_ish="yes"
		app_name="zlib"
		_custom_flags
		rc=$?
		assert_not_contains "static-ish omits -B lib_dir" "${rc}" "${CFLAGS}" "-B${lib_dir}"
		assert_not_contains "static-ish omits -static" "${rc}" "${CFLAGS}" "-static"

		# Cross build never injects -march=native even if qbt_optimise=yes
		qbt_optimise="yes"
		_custom_flags
		rc=$?
		assert_not_contains "cross build omits -march=native" "${rc}" "${CFLAGS}" "-march=native"

		# glibc 2.40 adds -D_FORTIFY_SOURCE=3; 2.41 omits it
		app_version[glibc]="2.40"
		_custom_flags
		rc=$?
		assert_contains "glibc 2.40 adds -D_FORTIFY_SOURCE=3" "${rc}" "${CPPFLAGS}" "-D_FORTIFY_SOURCE=3"
		app_version[glibc]="2.41"
		_custom_flags
		rc=$?
		assert_not_contains "glibc 2.41 omits -D_FORTIFY_SOURCE=3" "${rc}" "${CPPFLAGS}" "-D_FORTIFY_SOURCE=3"
		save_counts
	)
	load_counts

	# 4b. Native amd64 vs aarch64 hardening, Alpine fortify, GCC 12 vs 14 vs non-numeric, debug/strip/neither, march=native, user-config.jam
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		mock_gcc_dir="${test_root}/mock_gcc14"
		mkdir -p -- "${mock_gcc_dir}"
		cat > "${mock_gcc_dir}/gcc" << 'EOF'
#!/bin/bash
[[ ${1} == "-dumpspecs" ]] && exit 0
[[ ${1} == "-dumpversion" ]] && printf '14.2.0\n'
EOF
		chmod +x -- "${mock_gcc_dir}/gcc"
		PATH="${mock_gcc_dir}:${PATH}"

		qbt_build_debug="no"
		qbt_optimise_strip="yes"
		qbt_use_lto="yes"
		qbt_linker_mold="no"
		qbt_static_ish="no"
		qbt_optimise="yes"
		qbt_standard="23"
		qbt_cross_name="default"
		qbt_cross_host=""
		qbt_build_tool="cmake"
		include_dir="${test_root}/alp/include"
		lib_dir="${test_root}/alp/lib"
		app_name="qbittorrent"
		CFLAGS="" CXXFLAGS="" CPPFLAGS="" LDFLAGS=""
		_custom_flags
		rc=$?
		assert_contains "alpine native CPPFLAGS adds -D_FORTIFY_SOURCE=3" "${rc}" "${CPPFLAGS}" "-D_FORTIFY_SOURCE=3"
		assert_contains "alpine native CFLAGS adds -isystem /usr/include/fortify" "${rc}" "${CFLAGS}" "-isystem /usr/include/fortify"
		assert_contains "gcc 14 adds -fstrict-flex-arrays=3" "${rc}" "${CFLAGS}" "-fstrict-flex-arrays=3"
		assert_contains "native x86_64 adds -fcf-protection=full" "${rc}" "${CFLAGS}" "-fcf-protection=full"
		assert_not_contains "native x86_64 omits -mbranch-protection=standard" "${rc}" "${CFLAGS}" "-mbranch-protection=standard"
		assert_contains "native optimise=yes adds -march=native" "${rc}" "${CFLAGS}" "-march=native"
		assert_not_contains "mold=no omits -fuse-ld=mold" "${rc}" "${LDFLAGS}" "-fuse-ld=mold"
		assert_eq "native LTO AR uses gcc-ar" "gcc-ar" "${AR}"
		assert_eq "native strip=yes sets -O3" "-O3" "${qbt_optimise_gcc}"
		assert_eq "native strip=yes sets qbt_strip_flags=-s" "-s" "${qbt_strip_flags}"

		# Native aarch64 adds -mbranch-protection=standard, omits -fcf-protection=full
		os_arch="aarch64"
		_custom_flags
		rc=$?
		assert_contains "native aarch64 adds -mbranch-protection=standard" "${rc}" "${CFLAGS}" "-mbranch-protection=standard"
		assert_not_contains "native aarch64 omits -fcf-protection=full" "${rc}" "${CFLAGS}" "-fcf-protection=full"

		# GCC 12 and non-numeric dumpversion omit -fstrict-flex-arrays=3 cleanly
		cat > "${mock_gcc_dir}/gcc" << 'EOF'
#!/bin/bash
[[ ${1} == "-dumpspecs" ]] && exit 0
[[ ${1} == "-dumpversion" ]] && printf '12.3.0\n'
EOF
		_custom_flags
		rc=$?
		assert_not_contains "gcc 12 omits -fstrict-flex-arrays=3" "${rc}" "${CFLAGS}" "-fstrict-flex-arrays=3"

		cat > "${mock_gcc_dir}/gcc" << 'EOF'
#!/bin/bash
[[ ${1} == "-dumpspecs" ]] && exit 0
[[ ${1} == "-dumpversion" ]] && printf 'unknown-version\n'
EOF
		_custom_flags 2> "${test_root}/gcc_nonnum.err"
		rc=$?
		assert_not_contains "non-numeric gcc dumpversion falls back to 0 cleanly" "${rc}" "${CFLAGS}" "-fstrict-flex-arrays=3"
		assert_eq "non-numeric gcc dumpversion emits zero stderr" "" "$(< "${test_root}/gcc_nonnum.err")"

		# Debug=yes vs strip=no + debug=no
		qbt_build_debug="yes"
		_custom_flags
		assert_eq "debug=yes sets -Og -g" "-Og -g" "${qbt_optimise_gcc}"
		assert_eq "debug=yes sets qbt_strip_flags=-g" "-g" "${qbt_strip_flags}"
		assert_eq "debug=yes sets qbt_strip_qmake=-nostrip" "-nostrip" "${qbt_strip_qmake}"

		qbt_build_debug="no"
		qbt_optimise_strip="no"
		_custom_flags
		assert_eq "debug=no strip=no sets -Og -g" "-Og -g" "${qbt_optimise_gcc}"
		assert_eq "debug=no strip=no sets empty qbt_strip_flags" "" "${qbt_strip_flags}"
		assert_eq "debug=no strip=no sets -Wl,-O0" "-Wl,-O0" "${qbt_optimise_linker}"

		# qmake + boost writes user-config.jam (native and cross)
		HOME="${test_root}/jam_home"
		mkdir -p -- "${HOME}"
		qbt_build_tool="qmake"
		python_short_version="3.12"
		app_name="boost"
		qbt_cross_name="default"
		qbt_cross_host=""
		_custom_flags
		rc=$?
		assert_file_exists "qmake boost native creates user-config.jam" "${HOME}/user-config.jam"
		assert_contains "native user-config.jam uses g++" "${rc}" "$(< "${HOME}/user-config.jam")" "using gcc : : g++ :"
		assert_contains "native user-config.jam sets python 3.12" "${rc}" "$(< "${HOME}/user-config.jam")" "using python : 3.12"

		qbt_cross_name="aarch64"
		qbt_cross_host="aarch64-linux-musl"
		qbt_cross_boost="gcc-arm"
		_custom_flags
		rc=$?
		assert_contains "cross user-config.jam strips gcc- and uses cross g++" "${rc}" "$(< "${HOME}/user-config.jam")" "using gcc : arm : aarch64-linux-musl-g++ :"

		# Alpine cross build never injects -B lib_dir, handles missing cross compiler gracefully, toggles LTO wrappers
		qbt_build_tool="cmake"
		qbt_cross_tool_dir="${test_root}/alp/bin"
		qbt_use_lto="yes"
		qbt_static_ish="no"
		app_name="zlib"
		_custom_flags
		rc=$?
		assert_not_contains "alpine cross static omits -B lib_dir" "${rc}" "${CFLAGS}" "-B${lib_dir}"
		assert_not_contains "missing cross gcc falls back to version 0 (omits -fstrict-flex-arrays=3)" "${rc}" "${CFLAGS}" "-fstrict-flex-arrays=3"
		assert_eq "alpine cross LTO AR uses qbt_cross_tool_dir gcc-ar" "${test_root}/alp/bin/aarch64-linux-musl-gcc-ar" "${AR}"
		qbt_use_lto="no"
		_custom_flags
		assert_eq "alpine cross non-LTO AR uses qbt_cross_tool_dir ar" "${test_root}/alp/bin/aarch64-linux-musl-ar" "${AR}"

		# Cross gcc_command probes qbt_cross_tool_dir compiler even when qbt_cross_tool_dir is not on PATH
		mkdir -p -- "${test_root}/alp/bin"
		cat > "${test_root}/alp/bin/aarch64-linux-musl-gcc" << 'EOF'
#!/bin/bash
[[ ${1} == "-dumpspecs" ]] && exit 0
[[ ${1} == "-dumpversion" ]] && printf '14.2.0\n'
EOF
		chmod +x -- "${test_root}/alp/bin/aarch64-linux-musl-gcc"
		_custom_flags
		rc=$?
		assert_contains "cross gcc_command probes qbt_cross_tool_dir compiler when off PATH" "${rc}" "${CFLAGS}" "-fstrict-flex-arrays=3"
		save_counts
	)
	load_counts

	save_counts
)
load_counts

printf '\n=== 5. Path, Repo Validation & Archive Extraction Name Tests ===\n'
(
	load_lib

	# _validate_github_repo checks
	_validate_github_repo "userdocs/qbittorrent-nox-static"
	assert_exit "_validate_github_repo accepts standard owner/repo" 0 "$?"
	_validate_github_repo "foo..bar/baz..qux"
	assert_exit "_validate_github_repo accepts double-dots inside valid names" 0 "$?"
	for bad_repo in "" "owner" "a/b/c" "../repo" "owner/.." "../../etc" "./repo" "owner/." "owner/bad;repo"; do
		_validate_github_repo "${bad_repo}"
		assert_exit "_validate_github_repo rejects '${bad_repo}'" 1 "$?"
	done

	_validate_path "glibc-2.44" "name"
	assert_exit "_validate_path accepts safe name" 0 "$?"
	_validate_path "qtbase_6.8.2" "name"
	assert_exit "_validate_path accepts underscore and dots in name" 0 "$?"
	_validate_path "foo..bar" "name"
	assert_exit "_validate_path accepts double-dots inside valid name foo..bar" 0 "$?"
	_validate_path "/abs/foo..bar/file..v2.txt" "file"
	assert_exit "_validate_path accepts double-dots in valid file path" 0 "$?"
	_validate_path "/abs/path/ok" "file"
	assert_exit "_validate_path accepts absolute path in file mode" 0 "$?"
	_validate_path "rel/path/ok" "dir"
	assert_exit "_validate_path accepts relative path in dir mode" 0 "$?"
	_validate_path "/abs/path" "name"
	assert_exit "_validate_path rejects absolute path in name mode" 1 "$?"
	_validate_path "." "name"
	assert_exit "_validate_path rejects single dot in name mode" 1 "$?"
	_validate_path "-rf" "name"
	assert_exit "_validate_path rejects leading dash in name mode" 1 "$?"
	_validate_path ".." "dir"
	assert_exit "_validate_path rejects bare .." 1 "$?"
	_validate_path "foo/../bar" "dir"
	assert_exit "_validate_path rejects .. segment in dir mode" 1 "$?"
	_validate_path "../escape" "file"
	assert_exit "_validate_path rejects leading ../ in file mode" 1 "$?"
	_validate_path "a/.." "file"
	assert_exit "_validate_path rejects trailing /.. in file mode" 1 "$?"
	_validate_path "" "file"
	assert_exit "_validate_path rejects empty path" 1 "$?"
	_validate_path $'bad\nname' "dir"
	assert_exit "_validate_path rejects newline control char" 1 "$?"
	_validate_path $'bad\rname' "file"
	assert_exit "_validate_path rejects CR control char" 1 "$?"
	_validate_path $'bad\tname' "name"
	assert_exit "_validate_path rejects tab control char" 1 "$?"
	_validate_path "bad;name" "name"
	assert_exit "_validate_path rejects semicolon in name mode" 1 "$?"
	_validate_path "bad name" "name"
	assert_exit "_validate_path rejects space in name mode" 1 "$?"
	# shellcheck disable=SC2016
	_validate_path '$(id)' "name"
	assert_exit "_validate_path rejects command substitution in name mode" 1 "$?"
	_validate_path "a/b" "name"
	assert_exit "_validate_path rejects slash in name mode" 1 "$?"

	# _resolve_path tests (including symlinked ancestor + multiple non-existent nested directories)
	rp_base="${test_root}/rp_real"
	rp_link="${test_root}/rp_sym"
	mkdir -p -- "${rp_base}/existing"
	ln -s -- "${rp_base}" "${rp_link}"
	rp_real_resolved="$(readlink -f -- "${rp_base}")"
	rp_out="$(_resolve_path "${rp_link}/existing")"
	assert_pass_eq "_resolve_path resolves existing directory through symlink" "$?" "${rp_real_resolved}/existing" "${rp_out}"
	rp_out="$(_resolve_path "${rp_link}/new_a/new_b/new_c/")"
	assert_pass_eq "_resolve_path resolves multiple missing nested dirs under symlinked parent" "$?" "${rp_real_resolved}/new_a/new_b/new_c" "${rp_out}"
	rp_out="$(cd "${rp_link}" && _resolve_path "rel_sub/leaf")"
	assert_pass_eq "_resolve_path resolves relative path against PWD" "$?" "${rp_real_resolved}/rel_sub/leaf" "${rp_out}"
	rp_out="$(_resolve_path "///")"
	assert_pass_eq "_resolve_path preserves root slash" "$?" "/" "${rp_out}"
	_resolve_path "" > /dev/null 2>&1
	assert_exit "_resolve_path rejects empty path" 1 "$?"

	# Archive tests with real tarballs
	arch_tmp="${test_root}/archives"
	mkdir -p -- "${arch_tmp}/src/zlib-1.3.2/sub" "${arch_tmp}/dotsrc/pkg..1.0"
	printf 'hi\n' > "${arch_tmp}/src/zlib-1.3.2/sub/file.txt"
	printf 'hi\n' > "${arch_tmp}/dotsrc/pkg..1.0/file.txt"
	tar -czf "${arch_tmp}/normal.tar.gz" -C "${arch_tmp}/src" "zlib-1.3.2"
	tar -czf "${arch_tmp}/dotslash.tar.gz" -C "${arch_tmp}/src" "./zlib-1.3.2"
	tar -czf "${arch_tmp}/dotroot.tar.gz" -C "${arch_tmp}/src" "."
	tar -czf "${arch_tmp}/double_dot_name.tar.gz" -C "${arch_tmp}/dotsrc" "pkg..1.0"
	ln -s -- "${arch_tmp}/normal.tar.gz" "${arch_tmp}/symlink.tar.gz"
	: > "${arch_tmp}/empty.tar.gz"
	# Large archive: awk exits at the first entry so tar is killed by SIGPIPE, which must not fail the lookup even though this suite runs with pipefail
	mkdir -p -- "${arch_tmp}/bigsrc/big-1.0"
	for ((arch_i = 0; arch_i < 4000; arch_i++)); do : > "${arch_tmp}/bigsrc/big-1.0/file_${arch_i}"; done
	tar -cf "${arch_tmp}/big.tar" -C "${arch_tmp}/bigsrc" "big-1.0"

	ad_out="$(_get_archive_dir_name "${arch_tmp}/normal.tar.gz")"
	assert_pass_eq "_get_archive_dir_name extracts top dir" "$?" "zlib-1.3.2" "${ad_out}"
	ad_out="$(_get_archive_dir_name "${arch_tmp}/big.tar")"
	assert_pass_eq "_get_archive_dir_name tolerates tar SIGPIPE on a large archive under pipefail" "$?" "big-1.0" "${ad_out}"
	ad_out="$(_get_archive_dir_name "${arch_tmp}/dotslash.tar.gz")"
	assert_pass_eq "_get_archive_dir_name strips leading ./" "$?" "zlib-1.3.2" "${ad_out}"
	ad_out="$(_get_archive_dir_name "${arch_tmp}/dotroot.tar.gz")"
	assert_pass_eq "_get_archive_dir_name skips bare . entry" "$?" "zlib-1.3.2" "${ad_out}"
	ad_out="$(_get_archive_dir_name "${arch_tmp}/double_dot_name.tar.gz")"
	assert_pass_eq "_get_archive_dir_name accepts archive with pkg..1.0 top dir" "$?" "pkg..1.0" "${ad_out}"
	_get_archive_dir_name "${arch_tmp}/symlink.tar.gz" > /dev/null 2>&1
	assert_exit "_get_archive_dir_name rejects symlinked archive" 1 "$?"
	_get_archive_dir_name "${arch_tmp}/src" > /dev/null 2>&1
	assert_exit "_get_archive_dir_name rejects directory path" 1 "$?"
	_get_archive_dir_name "${arch_tmp}/empty.tar.gz" > /dev/null 2>&1
	assert_exit "_get_archive_dir_name rejects empty/corrupt archive" 1 "$?"
	_get_archive_dir_name "${arch_tmp}/missing.tar.gz" > /dev/null 2>&1
	assert_exit "_get_archive_dir_name rejects missing archive" 1 "$?"
	_get_archive_dir_name "${arch_tmp}/../archives/normal.tar.gz" > /dev/null 2>&1
	assert_exit "_get_archive_dir_name rejects archive path with .." 1 "$?"

	mkdir -p -- "${arch_tmp}/bad/evil dir"
	printf 'x\n' > "${arch_tmp}/bad/evil dir/f"
	tar -czf "${arch_tmp}/badname.tar.gz" -C "${arch_tmp}/bad" "evil dir"
	_get_archive_dir_name "${arch_tmp}/badname.tar.gz" > /dev/null 2>&1
	assert_exit "_get_archive_dir_name rejects unsafe archive dir name" 1 "$?"

	# Archive with leading / or .. member path rejected even when tar -tf emits it
	tar -P -cf "${arch_tmp}/abs_entry.tar" "${arch_tmp}/src/zlib-1.3.2/sub/file.txt" 2> /dev/null
	_get_archive_dir_name "${arch_tmp}/abs_entry.tar" > /dev/null 2>&1
	assert_exit "_get_archive_dir_name rejects archive with leading-slash entry" 1 "$?"

	save_counts
)
load_counts

printf '\n=== 6. Core Helper Function Tests (_nproc, _cmd, _post_command, _pushd/_popd, _tee, _error_tag, _test_url, _boost_url, _debug) ===\n'
(
	load_lib

	np_val="$(_nproc)"
	assert_match "_nproc returns positive integer" "$?" "${np_val}" '^[1-9][0-9]*$'
	(
		nproc() { return 1; }
		fb_np="$(_nproc)"
		assert_pass_eq "_nproc falls back to 1 when nproc fails" "$?" "1" "${fb_np}"
		save_counts
	)
	load_counts

	(_cmd true)
	assert_exit "_cmd returns 0 on success" 0 "$?"
	cmd_fail_out="$(_cmd false 2>&1)"
	assert_fail_contains "_cmd exits 1 and prints failed command" "$?" "${cmd_fail_out}" "false"

	(_post_command build 0 0)
	assert_exit "_post_command passes on 0 0" 0 "$?"
	(_post_command build 1 0 > /dev/null 2>&1)
	assert_exit "_post_command exits 1 on 1 0" 1 "$?"
	(_post_command install 139 0 > /dev/null 2>&1)
	assert_exit "_post_command exits 1 on 139 0" 1 "$?"
	out_pc="$(_post_command configure 0 10 2>&1)"
	assert_fail_contains "_post_command exits 1 on 0 10 and reports configure stage" "$?" "${out_pc}" "configure"

	mkdir -p -- "${test_root}/pushd_dir"
	_pushd "${test_root}/pushd_dir"
	assert_eq "_pushd changes directory" "${test_root}/pushd_dir" "${PWD}"
	_popd
	(_pushd "${test_root}/does_not_exist" > /dev/null 2>&1)
	assert_exit "_pushd exits 1 on missing dir" 1 "$?"
	(
		dirs -c
		_popd > /dev/null 2>&1
	)
	assert_exit "_popd exits 1 on empty dir stack" 1 "$?"

	# _tee with bare file, single-level relative dir, nested dir, /dev/null, and symlink/non-regular refusal
	mkdir -p -- "${test_root}/tee_wd/existing_dir"
	: > "${test_root}/tee_wd/real_target"
	ln -s -- "${test_root}/tee_wd/real_target" "${test_root}/tee_wd/sym.log"
	(
		cd "${test_root}/tee_wd" || exit 1
		printf 'bare\n' | _tee "bare.log" > /dev/null || exit 1
		printf 'line1\n' | _tee "logs/single.log" > /dev/null || exit 1
		printf 'line2\n' | _tee -a "nested/a/b/multi.log" > /dev/null || exit 1
		printf 'null\n' | _tee "/dev/null" > /dev/null || exit 1
	)
	tee_rc=$?
	assert_pass_eq "_tee writes bare file in cwd" "${tee_rc}" "bare" "$(< "${test_root}/tee_wd/bare.log")"
	assert_pass_eq "_tee creates single-level relative parent dir" "${tee_rc}" "line1" "$(< "${test_root}/tee_wd/logs/single.log")"
	assert_pass_eq "_tee -a creates nested parent dirs" "${tee_rc}" "line2" "$(< "${test_root}/tee_wd/nested/a/b/multi.log")"
	sym_tee_out="$(printf 'evil\n' | _tee "${test_root}/tee_wd/sym.log" 2>&1)"
	assert_fail_contains "_tee refuses symlinked log file" "$?" "${sym_tee_out}" "Refusing to write log"
	assert_eq "_tee did not clobber symlink target" "" "$(< "${test_root}/tee_wd/real_target")"
	dir_tee_out="$(printf 'evil\n' | _tee "${test_root}/tee_wd/existing_dir" 2>&1)"
	assert_fail_contains "_tee refuses directory target" "$?" "${dir_tee_out}" "Refusing to write log"

	# _error_tag
	github_tag[zlib]="v1.3.2"
	(_error_tag)
	assert_exit "_error_tag returns 0 when no error_tag present" 0 "$?"
	out_et="$(_error_tag "zlib" "custom fail" 2>&1)"
	assert_fail_contains "_error_tag exits 1 and prints custom reason" "$?" "${out_et}" "custom fail"
	github_tag[zlib]="error_tag"
	(_error_tag > /dev/null 2>&1)
	assert_exit "_error_tag exits 1 when github_tag contains error_tag" 1 "$?"
	github_tag[zlib]="v1.3.2"

	# _test_url
	(
		_curl() { printf '200'; }
		out="$(_test_url)"
		assert_contains "_test_url passes on HTTP 200 and prints passed" "$?" "${out}" "passed"
		save_counts
	)
	load_counts

	(
		_curl() { printf '503'; }
		_test_url > /dev/null 2>&1
	)
	assert_exit "_test_url exits 1 on HTTP 503" 1 "$?"

	(
		_curl() { printf '000'; }
		_test_url > /dev/null 2>&1
	)
	assert_exit "_test_url exits 1 on HTTP 000" 1 "$?"

	# _test_git_output
	tgo_ok="$(_test_git_output "v1.2.20" "libtorrent" "v1.2.20")"
	assert_pass_eq "_test_git_output silent on valid tag" "$?" "" "${tgo_ok}"
	tgo_bad="$(_test_git_output "error_tag" "openssl" "badtag")"
	assert_contains "_test_git_output warns on error_tag" "$?" "${tgo_bad}" "badtag"

	# _boost_url: GitHub release URL, archives.boost.io fallback, beta rewrite, and folder fallback
	(
		github_tag[boost]="boost-1.88.0"
		_curl() { [[ ${*} == *"github.com/boostorg/boost/releases/download/boost-1.88.0/boost-1.88.0-b2-nodocs.tar.xz"* ]]; }
		_boost_url
		rc=$?
		assert_eq "_boost_url GitHub release status 200" "200" "${boost_url_status}"
		assert_eq "_boost_url GitHub release sets file" "file" "${source_default[boost]}"
		assert_contains "_boost_url GitHub release URL" "${rc}" "${source_archive_url[boost]}" "boost-1.88.0-b2-nodocs.tar.xz"

		_curl() { [[ ${*} == *"archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz"* ]]; }
		_boost_url
		assert_eq "_boost_url archives.boost.io fallback status 200" "200" "${boost_url_status}"
		assert_eq "_boost_url archives.boost.io fallback URL" "https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz" "${source_archive_url[boost]}"

		github_tag[boost]="boost-1.88.0.beta1"
		_curl() { [[ ${*} == *"archives.boost.io/beta/1.88.0.beta1/source/boost_1_88_0_b1.tar.gz"* ]]; }
		_boost_url
		assert_eq "_boost_url beta tag rewrites to beta/_b1 URL" "https://archives.boost.io/beta/1.88.0.beta1/source/boost_1_88_0_b1.tar.gz" "${source_archive_url[boost]}"

		_curl() { return 1; }
		_boost_url
		assert_eq "_boost_url all fail sets status 403" "403" "${boost_url_status}"
		assert_eq "_boost_url all fail sets source_default=folder" "folder" "${source_default[boost]}"

		boost_curl_called="no"
		github_tag[boost]="error_tag"
		_curl() {
			boost_curl_called="yes"
			return 0
		}
		_boost_url
		assert_eq "_boost_url skips curl probes when github_tag[boost]=error_tag" "no" "${boost_curl_called}"
		assert_eq "_boost_url sets folder fallback on error_tag" "folder" "${source_default[boost]}"
		save_counts
	)
	load_counts

	# _debug no-op vs dump + exit 0
	script_debug_urls="no"
	out_dbg_off="$(_debug)"
	assert_pass_eq "_debug is no-op when script_debug_urls=no" "$?" "" "${out_dbg_off}"
	(
		script_debug_urls="yes"
		github_url[zlib]="https://example.invalid/zlib.git"
		github_tag[zlib]="v1.3.2"
		app_version[zlib]="1.3.2"
		source_archive_url[zlib]="https://example.invalid/zlib.tar.gz"
		qbt_workflow_archive_url[zlib]="https://example.invalid/wf-zlib.tar.xz"
		qbt_workflow_versions[zlib]="1.3.2"
		source_default[zlib]="file"
		boost_url_status="200"
		test_url_status="200"
		_debug
	) > "${test_root}/debug_out"
	dbg_rc=$?
	dbg_txt="$(< "${test_root}/debug_out")"
	assert_contains "_debug exits 0 and prints github_url section" "${dbg_rc}" "${dbg_txt}" "github_url"
	assert_contains "_debug prints qbt_workflow_versions section" "${dbg_rc}" "${dbg_txt}" "qbt_workflow_versions"
	assert_contains "_debug prints boost_url_status" "${dbg_rc}" "${dbg_txt}" "boost_url_status"

	# _debug with empty associative arrays produces zero stderr (no bad array subscript)
	(
		script_debug_urls="yes"
		github_url=()
		github_tag=()
		app_version=()
		source_archive_url=()
		qbt_workflow_archive_url=()
		qbt_workflow_versions=()
		source_default=()
		_debug
	) > /dev/null 2> "${test_root}/debug_empty_err"
	assert_pass_eq "_debug with empty arrays exits 0 with zero stderr" "$?" "" "$(< "${test_root}/debug_empty_err")"

	save_counts
)
load_counts

printf '\n=== 7. Module Sorting & Validation (_sort_modules, _installation_modules) Tests ===\n'
(
	load_lib "ubuntu" "resolute" "26.04" "amd64"
	qbt_working_dir="${test_root}/mod_wd"
	mkdir -p -- "${qbt_working_dir}"
	qbt_build_dir="${test_root}/mod_build"
	_set_default_values
	_set_build_directory

	_sort_modules
	first_len="${#qbt_modules_install_processed[@]}"
	_sort_modules
	second_len="${#qbt_modules_install_processed[@]}"
	assert_eq "_sort_modules resets array on repeated calls" "${first_len}" "${second_len}"

	# Verify canonical dependency order when all modules are enabled
	(
		qbt_modules_delete=()
		qbt_libtorrent_version="1.2"
		qbt_skip_icu="no"
		qbt_cross_name="aarch64"
		qbt_with_qemu="no"
		qbt_host_deps="no"
		_set_default_values > /dev/null
		_installation_modules all > /dev/null
		im_rc=$?
		assert_pass_eq "canonical module order with all enabled" "${im_rc}" "glibc zlib iconv icu_host_deps icu openssl boost libtorrent qtbase_host_deps qtbase qttools_host_deps qttools qbittorrent" "${qbt_modules_install_processed[*]}"
		assert_dir_exists "_installation_modules creates logs dir" "${qbt_install_dir}/logs"
		assert_dir_exists "_installation_modules creates PKG_CONFIG_PATH dir" "${PKG_CONFIG_PATH}"
		assert_dir_exists "_installation_modules creates completed dir" "${qbt_install_dir}/completed"
		assert_match "_installation_modules sets python_short_version" "${im_rc}" "${python_short_version}" '^[0-9]+\.[0-9]+$'
		save_counts
	)
	load_counts

	# Substring "qt" must NOT match "qtbase"
	(
		qbt_modules_test=""
		_installation_modules qt > /dev/null
		assert_eq "substring module 'qt' rejected as fail" "fail" "${qbt_modules_test}"
		save_counts
	)
	load_counts

	# Deleted module (icu when skipped) fails validation
	(
		qbt_modules_test=""
		_installation_modules icu > /dev/null
		assert_eq "deleted module 'icu' rejected when qbt_skip_icu=yes" "fail" "${qbt_modules_test}"
		save_counts
	)
	load_counts

	# Mixed valid + invalid fails validation
	(
		qbt_modules_test=""
		_installation_modules zlib nonexistent > /dev/null
		assert_eq "mixed valid + invalid sets qbt_modules_test=fail" "fail" "${qbt_modules_test}"
		save_counts
	)
	load_counts

	# Mixed "zlib all" expands to all sorted modules (no literal "all")
	(
		qbt_modules_test=""
		_installation_modules zlib all > /dev/null
		im_rc=$?
		assert_eq "mixed 'zlib all' passes validation" "" "${qbt_modules_test}"
		assert_not_contains "mixed 'zlib all' does not leave literal 'all' in processed list" "${im_rc}" " ${qbt_modules_install_processed[*]} " " all "
		assert_contains "mixed 'zlib all' includes qbittorrent" "${im_rc}" " ${qbt_modules_install_processed[*]} " " qbittorrent "
		save_counts
	)
	load_counts

	# Single/explicit module selection preserves order, sets skip_modules & qbt_activated_modules
	(
		qbt_modules_test=""
		_installation_modules zlib openssl > /dev/null
		im_rc=$?
		assert_pass_eq "explicit modules preserved in order" "${im_rc}" "zlib openssl" "${qbt_modules_install_processed[*]}"
		assert_eq "skip_modules marked no for zlib" "no" "${skip_modules[zlib]}"
		assert_eq "skip_modules marked no for openssl" "no" "${skip_modules[openssl]}"
		assert_eq "qbt_activated_modules marks zlib=yes" "yes" "${qbt_activated_modules[zlib]}"
		assert_contains "qbt_modules_selected_compare contains full list" "${im_rc}" " ${qbt_modules_selected_compare[*]} " " qbittorrent "
		save_counts
	)
	load_counts

	# No arguments leaves qbt_modules_test empty and populates sorted list including 'all'
	(
		qbt_modules_test=""
		_installation_modules > /dev/null
		im_rc=$?
		assert_eq "no-arg _installation_modules does not set fail" "" "${qbt_modules_test}"
		assert_contains "no-arg _installation_modules keeps 'all' in list" "${im_rc}" " ${qbt_modules_install_processed[*]} " " all "
		save_counts
	)
	load_counts

	save_counts
)
load_counts

printf '\n=== 8. Multi-Arch Configuration (_multi_arch) Tests ===\n'
(
	# 8a. Exhaustive 15-arch matrix for Alpine & Debian/Ubuntu (triplets, cross_arch, bitness, openssl, boost, qtbase)
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_cross_target="alpine"
		qbt_qt_version="6.8"
		while IFS='|' read -r arch exp_host exp_carch exp_bits exp_ssl exp_boost exp_qt; do
			qbt_cross_name="${arch}"
			_multi_arch info_bootstrap > /dev/null
			ma_rc=$?
			actual="${qbt_cross_host}|${cross_arch}|${bitness}|${qbt_cross_openssl}|${qbt_cross_boost}|${qbt_cross_qtbase}"
			assert_pass_eq "alpine ${arch} mapping" "${ma_rc}" "${exp_host}|${exp_carch}|${exp_bits}|${exp_ssl}|${exp_boost}|${exp_qt}" "${actual}"
		done << 'EOF'
armel|arm-linux-musleabi|armel|32|linux-armv4|gcc-arm|linux-arm-gnueabi-g++
armhf|arm-linux-musleabihf|armhf|32|linux-armv4|gcc-arm|linux-arm-gnueabi-g++
armv7|armv7l-linux-musleabihf|armv7|32|linux-armv4|gcc-arm|linux-arm-gnueabi-g++
aarch64|aarch64-linux-musl|aarch64|64|linux-aarch64|gcc-arm|linux-aarch64-gnu-g++
x86_64|x86_64-linux-musl|x86_64|64|linux-x86_64||linux-g++-64
x86|i686-linux-musl|x86|32|linux-x86||linux-g++-32
s390x|s390x-linux-musl|s390x|64|linux64-s390x|gcc-s390x|linux-g++-64
powerpc|powerpc-linux-musl|powerpc|32|linux-ppc|gcc-ppc|linux-g++-32
ppc64el|powerpc64le-linux-musl|ppc64el|64|linux-ppc64le|gcc-ppc64el|linux-g++-64
mips|mips-linux-musl|mips|32|linux-mips32|gcc-mips|linux-g++-32
mipsel|mipsel-linux-musl|mipsel|32|linux-mips32|gcc-mipsel|linux-g++-32
mips64|mips64-linux-musl|mips64|64|linux64-mips64|gcc-mips64|linux-g++-64
mips64el|mips64el-linux-musl|mips64el|64|linux64-mips64|gcc-mips64el|linux-g++-64
riscv64|riscv64-linux-musl|riscv64|64|linux64-riscv64|gcc-riscv64|linux-g++-64
loongarch64|loongarch64-linux-musl|loongarch64|64|linux64-loongarch64|gcc-loongarch64|linux-g++-64
EOF
		save_counts
	)
	load_counts

	(
		load_lib "debian" "trixie" "13" "amd64"
		qbt_cross_target="debian"
		while IFS='|' read -r arch exp_host exp_carch exp_bits; do
			qbt_cross_name="${arch}"
			_multi_arch info_bootstrap > /dev/null
			ma_rc=$?
			assert_pass_eq "debian ${arch} mapping" "${ma_rc}" "${exp_host}|${exp_carch}|${exp_bits}" "${qbt_cross_host}|${cross_arch}|${bitness}"
		done << 'EOF'
armel|arm-linux-gnueabi|armel|32
armhf|arm-linux-gnueabihf|armhf|32
armv7|arm-linux-gnueabihf|armhf|32
aarch64|aarch64-linux-gnu|arm64|64
x86_64|x86_64-linux-gnu|amd64|64
x86|i686-linux-gnu|i386|32
s390x|s390x-linux-gnu|s390x|64
powerpc|powerpc-linux-gnu|powerpc|32
ppc64el|powerpc64le-linux-gnu|ppc64el|64
mips|mips-linux-gnu|mips|32
mipsel|mipsel-linux-gnu|mipsel|32
mips64|mips64-linux-gnuabi64|mips64|64
mips64el|mips64el-linux-gnuabi64|mips64el|64
riscv64|riscv64-linux-gnu|riscv64|64
EOF
		save_counts
	)
	load_counts

	# 8b. CMake vs QMake toolchain arrays + LTO + host_deps + ICU cross-build flag
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
		ma_rc=$?
		assert_pass_eq "multi_glibc sets --host" "${ma_rc}" "--host=riscv64-linux-gnu" "${multi_glibc[*]}"
		assert_eq "multi_iconv sets --host" "--host=riscv64-linux-gnu" "${multi_iconv[*]}"
		assert_eq "multi_icu includes -with-cross-build when host_deps=yes" "--host=riscv64-linux-gnu -with-cross-build=${qbt_host_deps_path}" "${multi_icu[*]}"
		assert_eq "multi_openssl uses ./Configure linux64-riscv64" "./Configure linux64-riscv64" "${multi_openssl[*]}"
		assert_contains "cmake toolchain uses cross gcc-ar for LTO" "${ma_rc}" "${multi_qtbase[*]}" "-D CMAKE_AR=/usr/bin/riscv64-linux-gnu-gcc-ar"
		assert_contains "cmake toolchain includes QT_HOST_PATH in qtbase" "${ma_rc}" "${multi_qtbase[*]}" "-D QT_HOST_PATH=${qbt_host_deps_path}"
		assert_contains "cmake toolchain includes QT_HOST_PATH in qttools" "${ma_rc}" "${multi_qttools[*]}" "-D QT_HOST_PATH=${qbt_host_deps_path}"
		assert_contains "cmake toolchain includes QT_HOST_PATH in qbittorrent" "${ma_rc}" "${multi_qbittorrent[*]}" "-D QT_HOST_PATH=${qbt_host_deps_path}"

		qbt_use_lto="no"
		qbt_host_deps="no"
		qbt_with_qemu="yes"
		qbt_use_host_deps="no"
		_multi_arch > /dev/null
		ma_rc=$?
		assert_contains "cmake non-LTO toolchain uses cross ar" "${ma_rc}" "${multi_qtbase[*]}" "-D CMAKE_AR=/usr/bin/riscv64-linux-gnu-ar"
		assert_not_contains "cmake without host_deps omits QT_HOST_PATH" "${ma_rc}" "${multi_qtbase[*]}" "QT_HOST_PATH"

		# qmake mode
		qbt_build_tool="qmake"
		_multi_arch > /dev/null
		ma_rc=$?
		assert_pass_eq "qmake multi_qtbase sets -xplatform" "${ma_rc}" "-xplatform linux-g++-64" "${multi_qtbase[*]}"
		assert_eq "qmake multi_libtorrent sets toolset=gcc-riscv64" "toolset=gcc-riscv64" "${multi_libtorrent[*]}"
		assert_eq "qmake multi_qbittorrent sets --host" "--host=riscv64-linux-gnu" "${multi_qbittorrent[*]}"

		# x86_64 qmake defaults empty qbt_cross_boost to toolset=gcc
		qbt_cross_name="x86_64"
		_multi_arch > /dev/null
		ma_rc=$?
		assert_pass_eq "qmake x86_64 empty boost cross falls back to toolset=gcc" "${ma_rc}" "toolset=gcc" "${multi_libtorrent[*]}"
		save_counts
	)
	load_counts

	# 8c. Alpine toolchain download URL, extraction, symlinks, automatic skip_toolchain_extract reset, bootstrap re-extraction, QBT_MCM_DOCKER=YES
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_install_dir="${test_root}/alp_tc_build"
		qbt_mcm_dir="${qbt_install_dir}"
		qbt_cross_tool_dir="${qbt_install_dir}/bin"
		qbt_cross_target="alpine"
		qbt_cross_name="aarch64"
		qbt_mcm_url="userdocs/qbt-musl-cross-make"
		qbt_mcm_tag=""
		qbt_build_tool="cmake"
		qbt_use_lto="no"
		mkdir -p -- "${qbt_install_dir}"

		# Create a fake toolchain tarball
		tc_stage="${test_root}/tc_stage/aarch64-linux-musl-cross"
		mkdir -p -- "${tc_stage}/bin" "${tc_stage}/aarch64-linux-musl/lib"
		printf '#!/bin/sh\nexit 0\n' > "${tc_stage}/bin/aarch64-linux-musl-gcc"
		printf '#!/bin/sh\nexit 0\n' > "${tc_stage}/bin/aarch64-linux-musl-g++"
		chmod +x -- "${tc_stage}/bin/aarch64-linux-musl-gcc" "${tc_stage}/bin/aarch64-linux-musl-g++"
		: > "${tc_stage}/aarch64-linux-musl/lib/libatomic.a"
		tar -czf "${test_root}/fake_tc.tar.gz" -C "${test_root}/tc_stage" "aarch64-linux-musl-cross"

		last_tc_url=""
		_curl() {
			local out="" url="" i=1
			while ((i <= $#)); do
				if [[ ${!i} == "-o" ]]; then
					((i++))
					out="${!i}"
				elif [[ ${!i} == https://* ]]; then
					url="${!i}"
				fi
				((i++))
			done
			last_tc_url="${url}"
			cp -f -- "${test_root}/fake_tc.tar.gz" "${out}"
			return 0
		}

		_multi_arch > /dev/null
		ma_rc=$?
		assert_pass_eq "alpine toolchain latest URL" "${ma_rc}" "https://github.com/userdocs/qbt-musl-cross-make/releases/latest/download/x86_64-aarch64-linux-musl.tar.xz" "${last_tc_url}"
		assert_eq "alpine toolchain symlink gcc -> aarch64-linux-musl-gcc" "aarch64-linux-musl-gcc" "$(readlink "${qbt_install_dir}/bin/gcc")"
		assert_eq "alpine toolchain writes .active-toolchain-info" "aarch64-linux-musl.tar.gz" "$(< "${qbt_install_dir}/.active-toolchain-info")"
		assert_eq "alpine toolchain fixes multiarch static links" "libatomic.a" "$(readlink "${qbt_install_dir}/aarch64-linux-musl/lib/libatomic.so")"

		# Second run with active toolchain skips re-extract
		_multi_arch > "${test_root}/tc_second.out"
		ma_rc=$?
		assert_contains "alpine second run reuses extracted toolchain" "${ma_rc}" "$(< "${test_root}/tc_second.out")" "Extracted"
		assert_eq "skip_toolchain_extract set to yes on second run" "yes" "${skip_toolchain_extract}"

		# Pinned qbt_mcm_tag + aarch64 host + bootstrap forces BOTH re-download AND re-extraction WITHOUT caller resetting skip_toolchain_extract
		printf 'updated\n' > "${tc_stage}/aarch64-linux-musl/lib/libupdated.a"
		tar -czf "${test_root}/fake_tc.tar.gz" -C "${test_root}/tc_stage" "aarch64-linux-musl-cross"
		os_arch="aarch64"
		qbt_mcm_tag="2614"
		_multi_arch bootstrap > /dev/null
		ma_rc=$?
		assert_pass_eq "alpine pinned tag + aarch64 host URL" "${ma_rc}" "https://github.com/userdocs/qbt-musl-cross-make/releases/download/2614/aarch64-aarch64-linux-musl.tar.xz" "${last_tc_url}"
		assert_eq "bootstrap resets skip_toolchain_extract to no" "no" "${skip_toolchain_extract}"
		assert_file_exists "bootstrap re-extracts updated toolchain archive" "${qbt_install_dir}/aarch64-linux-musl/lib/libupdated.a"

		# QBT_MCM_DOCKER=YES skips download completely
		last_tc_url=""
		QBT_MCM_DOCKER="YES"
		_multi_arch > /dev/null
		assert_eq "QBT_MCM_DOCKER=YES skips toolchain download" "" "${last_tc_url}"
		save_counts
	)
	load_counts

	# 8d. Negative/rejection cases (including invalid qbt_mcm_url and qbt_mcm_tag)
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_install_dir="${test_root}/bad_mcm_repo"
		qbt_cross_target="alpine"
		qbt_cross_name="aarch64"
		qbt_mcm_url="userdocs/.."
		_multi_arch > /dev/null 2>&1
	)
	assert_exit "alpine _multi_arch rejects traversal qbt_mcm_url" 1 "$?"

	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_install_dir="${test_root}/bad_mcm_tag"
		qbt_cross_target="alpine"
		qbt_cross_name="aarch64"
		qbt_mcm_url="userdocs/qbt-musl-cross-make"
		qbt_mcm_tag="../evil"
		_multi_arch > /dev/null 2>&1
	)
	assert_exit "alpine _multi_arch rejects unsafe qbt_mcm_tag" 1 "$?"

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

	(
		load_lib "alpine" "alpine" "3.21" "riscv64"
		qbt_install_dir="${test_root}/bad_host_arch"
		qbt_cross_target="alpine"
		qbt_cross_name="aarch64"
		_multi_arch > /dev/null 2>&1
	)
	assert_exit "alpine cross from unsupported riscv64 host exits 1" 1 "$?"

	(
		load_lib "fedora" "fedora" "41" "x86_64"
		qbt_cross_name="aarch64"
		_multi_arch > /dev/null 2>&1
	)
	assert_exit "unsupported OS in _multi_arch exits 1" 1 "$?"

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="default"
		_multi_arch
		assert_pass_eq "default cross_name sets multi_openssl to ./config" "$?" "./config" "${multi_openssl[*]}"
		save_counts
	)
	load_counts

	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_cross_name="sparc99"
		_multi_arch > /dev/null 2>&1
	)
	assert_exit "invalid cross_name exits 1" 1 "$?"

	save_counts
)
load_counts

printf '\n=== 9. Git Wrapper & Tag Validation (_git) Tests ===\n'
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

	_curl() { return 0; }
	_git_git() {
		local -a rewritten=()
		local a
		for a in "${@}"; do
			if [[ ${a} == "https://example.invalid/repo.git" || ${a} == "git://example.invalid/repo.git" ]]; then
				rewritten+=("${git_repo}")
			else
				rewritten+=("${a}")
			fi
		done
		command git "${rewritten[@]}"
	}

	g_out="$(_git "https://example.invalid/repo.git" -t "v1.2.20")"
	assert_pass_eq "_git -t accepts exact tag" "$?" "v1.2.20" "${g_out}"
	g_out="$(_git "https://example.invalid/repo.git" -t "master")"
	assert_pass_eq "_git -t accepts exact branch" "$?" "master" "${g_out}"
	g_out="$(_git "git://example.invalid/repo.git" -t "v1.2.20")"
	assert_pass_eq "_git -t accepts git:// scheme URL" "$?" "v1.2.20" "${g_out}"

	for bad_ref in \
		"" \
		"-h-qt" \
		"*" \
		"v1.2.2?" \
		"v1.*" \
		"[v]1.2.20" \
		"master extra" \
		$'v1.2.20\n' \
		"v1.0..v2.0" \
		"HEAD@{0}" \
		"/master" \
		"master/" \
		"master.lock" \
		"v1~1" \
		"v1^0" \
		"refs:tags" \
		"20" \
		"v9.9.9"; do
		g_out="$(_git "https://example.invalid/repo.git" -t "${bad_ref}")"
		assert_pass_eq "_git -t rejects ref '${bad_ref//$'\n'/\\n}'" "$?" "error_tag" "${g_out}"
	done

	out_ls="$(_git ls-remote "https://example.invalid/repo.git")"
	assert_contains "_git passthrough command succeeds and returns refs" "$?" "${out_ls}" "refs/tags/v1.2.20"

	(_git status > /dev/null 2>&1)
	assert_exit "_git exits 1 when no URL in args" 1 "$?"

	(
		_curl() { return 1; }
		_git ls-remote "https://example.invalid/repo.git" > /dev/null 2>&1
	)
	assert_exit "_git exits 1 when URL reachability fails" 1 "$?"

	(
		_git_git() { return 1; }
		_git clone "https://example.invalid/repo.git" > /dev/null 2>&1
	)
	assert_exit "_git exits 1 when underlying git command fails" 1 "$?"

	save_counts
)
load_counts

printf '\n=== 10. Module URL & Version Resolution (_set_module_urls) Tests ===\n'
(
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
  "qt5": "5.15.16",
  "qt6": "6.8.2",
  "qbittorrent": "5.1.0"
}'

	# 10a. Workflow JSON mode with jq + workflow archive URLs + iconv URL derivation + non-object JSON array rejection
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
		smu_rc=$?
		assert_pass_eq "workflow JSON maps glibc 2.44" "${smu_rc}" "2.44" "${app_version[glibc]}"
		assert_eq "workflow JSON maps qt6 from qt_version 6.8" "6.8.2" "${app_version[qtbase]}"
		assert_eq "workflow JSON maps qttools from qt6" "6.8.2" "${app_version[qttools]}"
		assert_eq "workflow JSON maps libtorrent_1_2" "1.2.20" "${app_version[libtorrent]}"
		assert_eq "iconv archive URL derived from app_version" "https://ftpmirror.gnu.org/gnu/libiconv/libiconv-1.19.tar.gz" "${source_archive_url[iconv]}"
		assert_eq "icu archive URL converts hyphen to underscore" "https://github.com/unicode-org/icu/releases/download/release-76-1/icu4c-76_1-sources.tgz" "${source_archive_url[icu]}"
		assert_eq "qt6 source URL uses official_releases" "https://download.qt.io/official_releases/qt/6.8/6.8.2/submodules/qtbase-everywhere-src-6.8.2.tar.xz" "${source_archive_url[qtbase]}"
		assert_eq "workflow archive URL for glibc" "https://github.com/userdocs/qbt-workflow-files/releases/latest/download/glibc.2.44.tar.xz" "${qbt_workflow_archive_url[glibc]}"
		assert_eq "workflow archive URL for qt6base" "https://github.com/userdocs/qbt-workflow-files/releases/latest/download/qt6base.tar.xz" "${qbt_workflow_archive_url[qtbase]}"
		assert_eq "workflow archive URL for libtorrent" "https://github.com/userdocs/qbt-workflow-files/releases/latest/download/libtorrent.1.2.20.tar.xz" "${qbt_workflow_archive_url[libtorrent]}"
		assert_eq "workflow archive URL for zlib" "https://github.com/userdocs/qbt-workflow-files/releases/latest/download/zlib.tar.xz" "${qbt_workflow_archive_url[zlib]}"
		assert_not_contains "does not scrape ftpmirror.gnu.org/gnu/libiconv/ on startup" "${smu_rc}" "$(< "${curl_hits}")" "ftpmirror.gnu.org/gnu/libiconv/"

		# Non-object JSON array must NOT bypass jq validation via sed fallback
		qbt_workflow_versions=()
		_curl() {
			if [[ ${*} == *"dependency-version.json"* ]]; then
				printf '[{"zlib": "9.9.9"}]'
				return 0
			fi
			return 1
		}
		_set_module_urls
		assert_eq "jq rejects non-object JSON array without falling back to sed" "" "${qbt_workflow_versions[zlib]:-}"
		save_counts
	)
	load_counts

	# 10b. Sed JSON fallback (no jq) + zlib-ng tagged URL + Alpine omits glibc URLs
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_workflow_files="yes"
		qbt_zlib_type="zlib-ng"
		qbt_qt_version="5"
		qbt_libtorrent_version="2.1"
		no_jq_bin="${test_root}/no_jq_bin"
		mkdir -p -- "${no_jq_bin}"
		for cmd_name in sed awk sort head grep tr rm mkdir cp mv cat; do
			cmd_path="$(command -v "${cmd_name}" || true)"
			[[ -n ${cmd_path} ]] && ln -fsn -- "${cmd_path}" "${no_jq_bin}/${cmd_name}"
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
		smu_rc=$?
		assert_pass_eq "sed JSON fallback resolves zlib-ng tag" "${smu_rc}" "2.2.4" "${github_tag[zlib]}"
		assert_eq "zlib-ng empty curl falls back to tag version" "2.2.4" "${app_version[zlib]}"
		assert_eq "zlib-ng tagged URL uses refs/tags" "https://github.com/zlib-ng/zlib-ng/archive/refs/tags/2.2.4.tar.gz" "${source_archive_url[zlib]}"
		assert_eq "zlib-ng workflow archive URL uses zlib-ng.tar.xz" "https://github.com/userdocs/qbt-workflow-files/releases/latest/download/zlib-ng.tar.xz" "${qbt_workflow_archive_url[zlib]}"
		assert_eq "qt5 source URL uses archive/qt and opensource-src" "https://download.qt.io/archive/qt/5.15/5.15.16/submodules/qtbase-everywhere-opensource-src-5.15.16.tar.xz" "${source_archive_url[qtbase]}"
		assert_eq "qt5 workflow archive URL uses qt5base.tar.xz" "https://github.com/userdocs/qbt-workflow-files/releases/latest/download/qt5base.tar.xz" "${qbt_workflow_archive_url[qtbase]}"
		assert_eq "alpine does not populate github_url[glibc]" "" "${github_url[glibc]:-}"
		save_counts
	)
	load_counts

	# 10c. Direct git tag discovery: regex filtering, boundary matching, zlib-ng develop, lts-lgpl strip, prerelease fallback, awk injection resistance
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_workflow_files="no"
		qbt_zlib_type="zlib-ng"
		qbt_qt_version="6.1"
		qbt_libtorrent_version="1.2"
		_curl() {
			if [[ ${*} == *"zlib.h.in"* ]]; then
				printf '#define ZLIB_VERSION "1.3.1.zlib-ng"\n'
				return 0
			fi
			return 1
		}
		_git_git() {
			case "${*}" in
				*glibc.git*)
					printf 'aaa\trefs/tags/glibc-2.43\nbbb\trefs/tags/glibc-2.44\nccc\trefs/tags/glibc-2.44-fedora-1\nddd\trefs/tags/glibc-2.45-cvs\n'
					;;
				*libtorrent.git*)
					printf 'aaa\trefs/tags/v1.2.20\nbbb\trefs/tags/v1.20.0\nccc\trefs/tags/v1.2.19\n'
					;;
				*qtbase.git* | *qttools.git*)
					printf 'aaa\trefs/tags/v6.1.3-lts-lgpl\nbbb\trefs/tags/v6.10.0\nccc\trefs/tags/v6.1.4-beta1\n'
					;;
				*libiconv.git*)
					printf 'aaa\trefs/tags/v1.19\nbbb\trefs/tags/v1.20-rc1\n'
					;;
				*icu.git*)
					printf 'aaa\trefs/tags/release-76-1\nbbb\trefs/tags/release-77-1-rc\n'
					;;
				*double-conversion.git*)
					printf 'aaa\trefs/tags/v3.3.1\nbbb\trefs/tags/v3.4.0-beta1\n'
					;;
				*openssl.git*)
					printf 'aaa\trefs/tags/openssl-3.5.9\nbbb\trefs/tags/openssl-3.6.0-alpha1\n'
					;;
				*boost.git*)
					printf 'aaa\trefs/tags/boost-1.88.0\nbbb\trefs/tags/boost-1.89.0.beta1\nccc\trefs/tags/boost-1.90.0-bgl\n'
					;;
				*qBittorrent.git*)
					printf 'aaa\trefs/tags/release-5.1.0\nbbb\trefs/tags/release-5.2.0rc1\n'
					;;
				*) ;;
			esac
		}
		_set_module_urls
		smu_rc=$?
		assert_pass_eq "glibc filter picks glibc-2.44 (skips fedora/cvs)" "${smu_rc}" "glibc-2.44" "${github_tag[glibc]}"
		assert_eq "zlib-ng non-workflow uses develop tag" "develop" "${github_tag[zlib]}"
		assert_eq "zlib-ng parses ZLIB_VERSION from zlib.h.in" "1.3.1" "${app_version[zlib]}"
		assert_eq "zlib-ng develop URL uses refs/heads/develop" "https://github.com/zlib-ng/zlib-ng/archive/refs/heads/develop.tar.gz" "${source_archive_url[zlib]}"
		assert_eq "icu filter skips rc tag" "release-76-1" "${github_tag[icu]}"
		assert_eq "openssl filter skips alpha tag" "openssl-3.5.9" "${github_tag[openssl]}"
		assert_eq "boost filter skips beta and -bgl tags" "boost-1.88.0" "${github_tag[boost]}"
		assert_eq "qbittorrent filter skips rc tag" "release-5.1.0" "${github_tag[qbittorrent]}"
		assert_eq "libtorrent 1.2 matches v1.2.20 (not v1.20.0)" "v1.2.20" "${github_tag[libtorrent]}"
		assert_eq "qtbase 6.1 matches v6.1.3-lts-lgpl (not v6.10.0 or beta)" "v6.1.3-lts-lgpl" "${github_tag[qtbase]}"
		assert_eq "qtbase app_version strips -lts-lgpl" "6.1.3" "${app_version[qtbase]}"

		# Libtorrent prerelease fallback when only prerelease tags exist (e.g. v2.1.0-rc1)
		qbt_libtorrent_version="2.1"
		_git_git() {
			case "${*}" in
				*libtorrent.git*) printf 'aaa\trefs/tags/v2.1.0-rc1\n' ;;
				*) ;;
			esac
		}
		_set_module_urls
		assert_pass_eq "libtorrent falls back to prerelease tag when no final tag exists" "$?" "v2.1.0-rc1" "${github_tag[libtorrent]}"

		# Awk injection resistance via qbt_libtorrent_version
		pwn_file="${test_root}/awk_pwned"
		qbt_libtorrent_version="1.2/{system(\"touch ${pwn_file}\")}/"
		_set_module_urls
		assert_file_missing "awk prefix lookup immune to code injection" "${pwn_file}"
		save_counts
	)
	load_counts

	save_counts
)
load_counts

printf '\n=== 11. Patching System (_apply_patches) Tests ===\n'
(
	# 11a. bootstrap creates dirs and excludes *_host_deps from count
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/p11a_build"
		mkdir -p -- "${qbt_install_dir}"
		qbt_modules_install=(["all"]="true" ["install"]="true" ["zlib"]="true" ["icu_host_deps"]="true" ["icu"]="true")
		qbt_modules_order=("all" "install" "zlib" "icu_host_deps" "icu")
		qbt_modules_delete=()
		app_version=([zlib]="1.3.2" [icu]="76-1")
		bs_out="$(_apply_patches bootstrap)"
		bs_rc=$?
		assert_contains "_apply_patches bootstrap counts only modules with app_version (2)" "${bs_rc}" "${bs_out}" "Patch directories created for 2 modules"
		assert_dir_exists "_apply_patches bootstrap creates zlib/1.3.2/source" "${qbt_install_dir}/patches/zlib/1.3.2/source"
		assert_dir_exists "_apply_patches bootstrap creates icu/76-1/source" "${qbt_install_dir}/patches/icu/76-1/source"
		save_counts
	)
	load_counts

	# 11b. source/ directory method has priority over patch file + strips _host_deps + copies dotfiles
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/p11b_build"
		src_target="${test_root}/p11b_icu_src"
		mkdir -p -- "${qbt_install_dir}/patches/icu/76-1/source" "${src_target}"
		app_version[icu]="76-1"
		printf 'patched-file\n' > "${qbt_install_dir}/patches/icu/76-1/source/override.txt"
		printf 'dotfile\n' > "${qbt_install_dir}/patches/icu/76-1/source/.hidden"
		printf 'should-not-be-applied\n' > "${qbt_install_dir}/patches/icu/76-1/patch"
		qbt_dl_folder_path="${src_target}"
		app_name="icu_host_deps"
		out_src="$(_apply_patches)"
		rc_src=$?
		assert_contains "_apply_patches prefers source directory method over patch" "${rc_src}" "${out_src}" "source directory method"
		assert_eq "_apply_patches strips _host_deps and copies source/ files" "patched-file" "$(< "${src_target}/override.txt")"
		assert_eq "_apply_patches copies dotfiles from source/" "dotfile" "$(< "${src_target}/.hidden")"
		save_counts
	)
	load_counts

	# 11c. local patch + CRLF url (comments/blank/scheme/dedup/prefix-collision) + missing trailing newline + idempotency
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/p11c_build"
		zlib_src="${test_root}/p11c_zlib_src"
		mkdir -p -- "${qbt_install_dir}/patches/zlib/1.3.2" "${zlib_src}"
		app_version[zlib]="1.3.2"
		printf 'lineA\nlineB\nlineC\n' > "${zlib_src}/hello.txt"
		# Deliberately omit trailing newline on base patch
		printf '%s' $'--- a/hello.txt\n+++ b/hello.txt\n@@ -1,3 +1,3 @@\n-lineA\n+lineA_patched\n lineB\n lineC' > "${qbt_install_dir}/patches/zlib/1.3.2/patch"
		# Write CRLF url file with blank lines, unsafe schemes, duplicate content, AND prefix-colliding URLs (commit/12345 vs commit/123)
		printf '%s' $'# comment line\r\n   \r\nfile:///etc/passwd\r\nftp://example.invalid/bad.patch\r\nhttps://example.invalid/dup.patch\r\nhttps://example.invalid/commit/12345\r\nhttps://example.invalid/commit/123\r\n' > "${qbt_install_dir}/patches/zlib/1.3.2/url"
		_curl() {
			local out="" url="" i=1
			while ((i <= $#)); do
				if [[ ${!i} == "-o" ]]; then
					((i++))
					out="${!i}"
				elif [[ ${!i} == https://* ]]; then
					url="${!i}"
				fi
				((i++))
			done
			case "${url}" in
				"https://example.invalid/dup.patch")
					printf '%s\n' $'--- a/hello.txt\n+++ b/hello.txt\n@@ -1,3 +1,3 @@\n-lineA\n+lineA_patched\n lineB\n lineC' > "${out}"
					;;
				"https://example.invalid/commit/12345")
					# Omit trailing newline here too
					printf '%s' $'--- a/hello.txt\n+++ b/hello.txt\n@@ -1,3 +1,3 @@\n lineA_patched\n-lineB\n+lineB_patched\n lineC' > "${out}"
					;;
				"https://example.invalid/commit/123")
					printf '%s' $'--- a/hello.txt\n+++ b/hello.txt\n@@ -1,3 +1,3 @@\n lineA_patched\n lineB_patched\n-lineC\n+lineC_patched' > "${out}"
					;;
				*) return 1 ;;
			esac
			return 0
		}
		qbt_dl_folder_path="${zlib_src}"
		app_name="zlib"
		patch_out="$(_apply_patches)"
		patch_rc=$?
		assert_contains "_apply_patches rejects unsafe file:// URL" "${patch_rc}" "${patch_out}" "Skipping unsafe patch URL: file:///etc/passwd"
		assert_contains "_apply_patches rejects unsafe ftp:// URL" "${patch_rc}" "${patch_out}" "Skipping unsafe patch URL: ftp://example.invalid/bad.patch"
		assert_not_contains "_apply_patches CRLF blank lines do not trigger unsafe URL warning" "${patch_rc}" "${patch_out}" $'Skipping unsafe patch URL: \r'
		assert_eq "_apply_patches applies CRLF url + prefix-colliding URLs + missing-newline diffs" $'lineA_patched\nlineB_patched\nlineC_patched' "$(< "${zlib_src}/hello.txt")"

		# Idempotency check on fresh copy
		zlib_src2="${test_root}/p11c_zlib_src2"
		mkdir -p -- "${zlib_src2}"
		printf 'lineA\nlineB\nlineC\n' > "${zlib_src2}/hello.txt"
		qbt_dl_folder_path="${zlib_src2}"
		_apply_patches > /dev/null
		rc2=$?
		marker_count="$(grep -c '^# Merged from URL: https://example.invalid/commit/123$' "${qbt_install_dir}/patches/zlib/1.3.2/patch")"
		assert_pass_eq "_apply_patches merge is idempotent (commit/123 merged once)" "${rc2}" "1" "${marker_count}"
		assert_eq "_apply_patches re-applied cleanly to fresh source" $'lineA_patched\nlineB_patched\nlineC_patched' "$(< "${zlib_src2}/hello.txt")"
		save_counts
	)
	load_counts

	# 11d. git apply method + failing/reversed non-git patch leaves zero partial edits or .rej/.orig files and never hangs
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/p11d_build"
		git_src="${test_root}/p11d_git_src"
		git init -q "${git_src}"
		git -C "${git_src}" config user.email "t@e"
		git -C "${git_src}" config user.name "T"
		printf 'orig\n' > "${git_src}/a.txt"
		git -C "${git_src}" add a.txt
		git -C "${git_src}" commit -qm "init"
		mkdir -p -- "${qbt_install_dir}/patches/openssl/3.5.9"
		app_version[openssl]="3.5.9"
		cat > "${qbt_install_dir}/patches/openssl/3.5.9/patch" << 'EOF'
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-orig
+gitpatched
EOF
		qbt_dl_folder_path="${git_src}"
		app_name="openssl"
		git_patch_out="$(_apply_patches)"
		git_patch_rc=$?
		assert_contains "_apply_patches uses git apply on git repo" "${git_patch_rc}" "${git_patch_out}" "using git"
		assert_eq "_apply_patches git apply updated file" "gitpatched" "$(< "${git_src}/a.txt")"

		# Multi-file patch where hunk 1 matches f1.txt and hunk 2 conflicts on f2.txt:
		# --dry-run must prevent partial mutation of f1.txt AND leave zero .rej/.orig files!
		bad_src="${test_root}/p11d_bad_src"
		mkdir -p -- "${bad_src}" "${qbt_install_dir}/patches/iconv/1.19"
		printf 'orig1\n' > "${bad_src}/f1.txt"
		printf 'already_modified_or_conflicting\n' > "${bad_src}/f2.txt"
		app_version[iconv]="1.19"
		cat > "${qbt_install_dir}/patches/iconv/1.19/patch" << 'EOF'
--- a/f1.txt
+++ b/f1.txt
@@ -1 +1 @@
-orig1
+mutated1
--- a/f2.txt
+++ b/f2.txt
@@ -1 +1 @@
-expected2
+mutated2
EOF
		qbt_dl_folder_path="${bad_src}"
		app_name="iconv"
		before_pwd="${PWD}"
		_apply_patches > /dev/null 2>&1
		assert_exit "_apply_patches returns 1 on conflicting multi-file patch" 1 "$?"
		assert_eq "_apply_patches restores PWD after failed patch" "${before_pwd}" "${PWD}"
		assert_eq "_apply_patches leaves f1.txt untouched on failed multi-file patch" "orig1" "$(< "${bad_src}/f1.txt")"
		assert_file_missing "_apply_patches leaves no f2.txt.rej file" "${bad_src}/f2.txt.rej"
		assert_file_missing "_apply_patches leaves no f2.txt.orig file" "${bad_src}/f2.txt.orig"
		save_counts
	)
	load_counts

	# 11e. Remote patches via GitHub API JSON (with jq AND grep fallback + multi-repo collision + owner/.. traversal repo rejection)
	for mode in jq grep_fallback; do
		(
			load_lib "ubuntu" "resolute" "26.04" "amd64"
			qbt_install_dir="${test_root}/p11e_${mode}_build"
			mkdir -p -- "${qbt_install_dir}"
			if [[ ${mode} == "grep_fallback" ]]; then
				no_jq_p="${test_root}/no_jq_patch_${mode}"
				mkdir -p -- "${no_jq_p}"
				for c in sed awk sort head grep tr rm mkdir cp mv cat find patch ls cmp mktemp tail; do
					cp_bin="$(command -v "${c}" || true)"
					[[ -n ${cp_bin} ]] && ln -fsn -- "${cp_bin}" "${no_jq_p}/${c}"
				done
				PATH="${no_jq_p}"
			fi
			rem_src="${test_root}/rem_src_${mode}"
			mkdir -p -- "${rem_src}"
			printf 'one\ntwo\n' > "${rem_src}/f.txt"
			app_version[boost]="1.88.0"
			qbt_dl_folder_path="${rem_src}"
			qbt_patches_url="owner1/repo1 owner/.. bad/repo/extra owner2/repo2"
			app_name="boost"
			_git_git() { printf 'ref: refs/heads/main\tHEAD\n'; }
			_curl() {
				local out="" url="" want_code=false i=1
				while ((i <= $#)); do
					if [[ ${!i} == "-o" ]]; then
						((i++))
						out="${!i}"
					elif [[ ${!i} == "-w" ]]; then
						((i++))
						want_code=true
					elif [[ ${!i} == https://* ]]; then
						url="${!i}"
					fi
					((i++))
				done
				case "${url}" in
					*"api.github.com/repos/owner1/repo1/contents/patches/boost/1.88.0")
						cat > "${out}" << 'JSON'
[
  {"name": "../evil.patch", "type": "file", "download_url": "https://raw.githubusercontent.com/owner1/repo1/main/evil"},
  {"name": "-flag.patch", "type": "file", "download_url": "https://raw.githubusercontent.com/owner1/repo1/main/evil2"},
  {"name": "patch", "type": "file", "download_url": "https://raw.githubusercontent.com/owner1/repo1/main/p1"}
]
JSON
						[[ ${want_code} == true ]] && printf '200'
						;;
					*"api.github.com/repos/owner2/repo2/contents/patches/boost/1.88.0")
						cat > "${out}" << 'JSON'
[
  {"name": "patch", "type": "file", "download_url": "https://raw.githubusercontent.com/owner2/repo2/main/p2"}
]
JSON
						[[ ${want_code} == true ]] && printf '200'
						;;
					*"owner1/repo1/main/p1")
						cat > "${out}" << 'DIFF'
--- a/f.txt
+++ b/f.txt
@@ -1,2 +1,2 @@
-one
+ONE
 two
DIFF
						;;
					*"owner2/repo2/main/p2")
						cat > "${out}" << 'DIFF'
--- a/f.txt
+++ b/f.txt
@@ -1,2 +1,2 @@
 ONE
-two
+TWO
DIFF
						;;
					*)
						[[ ${want_code} == true ]] && printf '404'
						return 1
						;;
				esac
				return 0
			}
			rem_out="$(_apply_patches)"
			rem_rc=$?
			assert_contains "remote patches (${mode}) rejects unsafe ../evil.patch" "${rem_rc}" "${rem_out}" "Skipping unsafe remote filename: ../evil.patch"
			assert_contains "remote patches (${mode}) rejects leading-dash -flag.patch" "${rem_rc}" "${rem_out}" "Skipping unsafe remote filename: -flag.patch"
			assert_contains "remote patches (${mode}) rejects traversal owner/.. repo" "${rem_rc}" "${rem_out}" "Skipping invalid patch repo format: owner/.."
			assert_contains "remote patches (${mode}) skips invalid repo format" "${rem_rc}" "${rem_out}" "Skipping invalid patch repo format: bad/repo/extra"
			assert_eq "remote patches (${mode}) merges multi-repo colliding patches" $'ONE\nTWO' "$(< "${rem_src}/f.txt")"
			save_counts
		)
		load_counts
	done

	# 11f. Isolated Libtorrent Jamfile tests (branch injection, empty remote, valid remote, local Jamfile, master Jamfile, multi-repo Jamfile preservation)
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/p11f_build"
		qbt_libtorrent_version="1.2"
		qbt_libtorrent_master_jamfile="no"
		app_version[libtorrent]="1.2.20"
		app_name="libtorrent"

		# Subtest 1: Invalid branch name rejected & preserves source Jamfile
		lt_s1="${test_root}/p11f_s1"
		mkdir -p -- "${lt_s1}"
		printf 'ORIGINAL_JAMFILE\n' > "${lt_s1}/Jamfile"
		qbt_dl_folder_path="${lt_s1}"
		qbt_patches_url="validowner/validrepo"
		_git_git() { printf 'ref: refs/heads/bad;branch\tHEAD\n'; }
		_curl() { return 1; }
		bad_br_out="$(_apply_patches)"
		bad_br_rc=$?
		assert_contains "remote patches rejects invalid branch name" "${bad_br_rc}" "${bad_br_out}" "Invalid branch name detected"
		assert_eq "invalid branch preserves original Jamfile" "ORIGINAL_JAMFILE" "$(< "${lt_s1}/Jamfile")"

		# Subtest 2: Empty remote Jamfile preserves original Jamfile
		rm -rf -- "${qbt_install_dir}/patches"
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
		assert_pass_eq "empty remote Jamfile preserves original source Jamfile" "$?" "ORIGINAL_JAMFILE" "$(< "${lt_s1}/Jamfile")"

		# Subtest 3: Non-empty remote Jamfile replaces source Jamfile
		rm -rf -- "${qbt_install_dir}/patches"
		_curl() {
			local out="" url="" i=1
			while ((i <= $#)); do
				if [[ ${!i} == "-o" ]]; then
					((i++))
					out="${!i}"
				elif [[ ${!i} == https://* ]]; then
					url="${!i}"
				fi
				((i++))
			done
			if [[ ${url} == *"/Jamfile" ]]; then
				printf 'REMOTE_JAMFILE\n' > "${out}"
				return 0
			fi
			printf '404'
			return 0
		}
		_apply_patches > /dev/null
		assert_pass_eq "non-empty remote Jamfile replaces source Jamfile" "$?" "REMOTE_JAMFILE" "$(< "${lt_s1}/Jamfile")"

		# Subtest 4: Multi-repo fallback preserves Repo 1 Jamfile when Repo 2 returns 0-byte HTTP 200
		lt_s4="${test_root}/p11f_s4"
		mkdir -p -- "${lt_s4}"
		printf 'ORIG\n' > "${lt_s4}/Jamfile"
		rm -rf -- "${qbt_install_dir}/patches"
		qbt_dl_folder_path="${lt_s4}"
		qbt_patches_url="owner1/repo1 owner2/repo2"
		_curl() {
			local out="" url="" want_code=false i=1
			while ((i <= $#)); do
				if [[ ${!i} == "-o" ]]; then
					((i++))
					out="${!i}"
				elif [[ ${!i} == "-w" ]]; then
					((i++))
					want_code=true
				elif [[ ${!i} == https://* ]]; then
					url="${!i}"
				fi
				((i++))
			done
			if [[ ${url} == *"api.github.com"* ]]; then
				[[ ${want_code} == true ]] && printf '403'
				return 0
			elif [[ ${url} == *"owner1/repo1"*"/Jamfile" ]]; then
				printf 'REPO1_JAMFILE\n' > "${out}"
				return 0
			elif [[ ${url} == *"owner2/repo2"*"/Jamfile" ]]; then
				: > "${out}"
				return 0
			fi
			return 1
		}
		_apply_patches > /dev/null
		assert_pass_eq "multi-repo fallback preserves Repo 1 Jamfile when Repo 2 returns 0 bytes" "$?" "REPO1_JAMFILE" "$(< "${lt_s4}/Jamfile")"

		# Subtest 5: Local patch_dir/Jamfile overrides source Jamfile
		lt_s5="${test_root}/p11f_s5"
		mkdir -p -- "${lt_s5}" "${qbt_install_dir}/patches/libtorrent/1.2.20"
		rm -f -- "${qbt_install_dir}/patches/libtorrent/1.2.20"/*
		printf 'ORIG\n' > "${lt_s5}/Jamfile"
		printf 'LOCAL_JAMFILE\n' > "${qbt_install_dir}/patches/libtorrent/1.2.20/Jamfile"
		qbt_dl_folder_path="${lt_s5}"
		_apply_patches > /dev/null
		assert_pass_eq "local patch_dir/Jamfile copied over source Jamfile" "$?" "LOCAL_JAMFILE" "$(< "${lt_s5}/Jamfile")"

		# Subtest 6: Master Jamfile downloads from arvidn/libtorrent/RC_1_2/Jamfile (and exits 1 on failure or 0-byte HTTP 200)
		lt_s6="${test_root}/p11f_s6"
		mkdir -p -- "${lt_s6}"
		printf 'ORIG\n' > "${lt_s6}/Jamfile"
		qbt_dl_folder_path="${lt_s6}"
		qbt_libtorrent_master_jamfile="yes"
		_curl() {
			local out="" url="" i=1
			while ((i <= $#)); do
				if [[ ${!i} == "-o" ]]; then
					((i++))
					out="${!i}"
				elif [[ ${!i} == https://* ]]; then
					url="${!i}"
				fi
				((i++))
			done
			if [[ ${url} == "https://raw.githubusercontent.com/arvidn/libtorrent/RC_1_2/Jamfile" ]]; then
				printf 'MASTER_RC_1_2_JAMFILE\n' > "${out}"
				return 0
			fi
			return 1
		}
		_apply_patches > /dev/null
		assert_pass_eq "master Jamfile fetches arvidn RC_1_2 Jamfile" "$?" "MASTER_RC_1_2_JAMFILE" "$(< "${lt_s6}/Jamfile")"

		(
			_curl() { return 1; }
			_apply_patches > /dev/null 2>&1
		)
		assert_exit "failed master Jamfile download exits 1" 1 "$?"

		printf 'KEEP_THIS_JAMFILE\n' > "${lt_s6}/Jamfile"
		(
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
				return 0
			}
			_apply_patches > /dev/null 2>&1
		)
		assert_exit "0-byte master Jamfile HTTP 200 download exits 1" 1 "$?"
		assert_eq "0-byte master Jamfile preserves existing source Jamfile" "KEEP_THIS_JAMFILE" "$(< "${lt_s6}/Jamfile")"
		save_counts
	)
	load_counts

	# 11g. 0-byte local url skipped, remote API recursive source/, prefix-overlapping patch filenames, API 403 fallback
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/p11g_build"
		empty_url_src="${test_root}/empty_url_src"
		mkdir -p -- "${empty_url_src}" "${qbt_install_dir}/patches/double_conversion/3.3.1"
		printf 'untouched\n' > "${empty_url_src}/dc.txt"
		printf 'https://example.invalid/empty.patch\n' > "${qbt_install_dir}/patches/double_conversion/3.3.1/url"
		app_version[double_conversion]="3.3.1"
		qbt_dl_folder_path="${empty_url_src}"
		app_name="double_conversion"
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
			return 0
		}
		_apply_patches > /dev/null
		assert_exit "0-byte url patch response skipped cleanly without failing patch -p1" 0 "$?"

		rem_src_dir="${test_root}/rem_src_dir"
		mkdir -p -- "${rem_src_dir}" "${qbt_install_dir}/patches/qtbase/6.8.2"
		app_version[qtbase]="6.8.2"
		qbt_dl_folder_path="${rem_src_dir}"
		qbt_patches_url="owner1/repo1"
		app_name="qtbase"
		: > "${qbt_install_dir}/patches/qtbase/6.8.2/patch"
		_git_git() { printf 'ref: refs/heads/main\tHEAD\n'; }
		_curl() {
			local out="" url="" want_code=false i=1
			while ((i <= $#)); do
				if [[ ${!i} == "-o" ]]; then
					((i++))
					out="${!i}"
				elif [[ ${!i} == "-w" ]]; then
					((i++))
					want_code=true
				elif [[ ${!i} == https://* ]]; then
					url="${!i}"
				fi
				((i++))
			done
			case "${url}" in
				*"contents/patches/qtbase/6.8.2")
					printf '[{"name":"source","type":"dir","download_url":null}]\n' > "${out}"
					[[ ${want_code} == true ]] && printf '200'
					;;
				*"contents/patches/qtbase/6.8.2/source")
					printf '[{"name":"custom.h","type":"file","download_url":"https://raw.githubusercontent.com/owner1/repo1/main/custom.h"}]\n' > "${out}"
					[[ ${want_code} == true ]] && printf '200'
					;;
				*"owner1/repo1/main/custom.h")
					printf '// remote header\n' > "${out}"
					;;
				*)
					[[ ${want_code} == true ]] && printf '404'
					return 1
					;;
			esac
			return 0
		}
		out_rdir="$(_apply_patches)"
		rc_rdir=$?
		assert_contains "0-byte local patch falls through to remote method" "${rc_rdir}" "${out_rdir}" "Using remote patches method"
		assert_eq "remote API downloads nested source/ dir recursively" "// remote header" "$(< "${rem_src_dir}/custom.h")"

		# Prefix-overlapping filenames: base patch already mentions '# Merged from: 01.patch.diff', standalone 01.patch must STILL be merged!
		p_only_src="${test_root}/p_only_src"
		mkdir -p -- "${p_only_src}" "${qbt_install_dir}/patches/qttools/6.8.2"
		printf 'line1\nline2\n' > "${p_only_src}/t.txt"
		cat > "${qbt_install_dir}/patches/qttools/6.8.2/patch" << 'DIFF'
# Merged from: 01.patch.diff
--- a/t.txt
+++ b/t.txt
@@ -1,2 +1,2 @@
-line1
+LINE1
 line2
DIFF
		cat > "${qbt_install_dir}/patches/qttools/6.8.2/01.patch" << 'DIFF'
--- a/t.txt
+++ b/t.txt
@@ -1,2 +1,2 @@
 LINE1
-line2
+LINE2
DIFF
		app_version[qttools]="6.8.2"
		qbt_dl_folder_path="${p_only_src}"
		app_name="qttools"
		_apply_patches > /dev/null
		rc_po=$?
		assert_pass_eq "prefix-overlapping 01.patch not skipped by 01.patch.diff marker" "${rc_po}" $'LINE1\nLINE2' "$(< "${p_only_src}/t.txt")"
		assert_contains "01.patch records exact # Merged from: 01.patch marker" "${rc_po}" "$(< "${qbt_install_dir}/patches/qttools/6.8.2/patch")" "# Merged from: 01.patch"

		# Remote API 403 rate-limit triggers fallback raw file probing
		fb_src="${test_root}/fb_src"
		mkdir -p -- "${fb_src}"
		printf 'old\n' > "${fb_src}/x.txt"
		rm -rf -- "${qbt_install_dir}/patches/glibc"
		app_version[glibc]="2.44"
		qbt_dl_folder_path="${fb_src}"
		app_name="glibc"
		_curl() {
			local out="" url="" want_code=false i=1
			while ((i <= $#)); do
				if [[ ${!i} == "-o" ]]; then
					((i++))
					out="${!i}"
				elif [[ ${!i} == "-w" ]]; then
					((i++))
					want_code=true
				elif [[ ${!i} == https://* ]]; then
					url="${!i}"
				fi
				((i++))
			done
			if [[ ${url} == *"api.github.com"* ]]; then
				printf 'rate limited' > "${out}"
				[[ ${want_code} == true ]] && printf '403'
				return 0
			elif [[ ${url} == *"/patches/glibc/2.44/01.patch" ]]; then
				cat > "${out}" << 'DIFF'
--- a/x.txt
+++ b/x.txt
@@ -1 +1 @@
-old
+new_via_fallback
DIFF
				return 0
			fi
			return 1
		}
		_apply_patches > /dev/null
		assert_pass_eq "remote API 403 falls back to raw filename probing" "$?" "new_via_fallback" "$(< "${fb_src}/x.txt")"
		save_counts
	)
	load_counts

	save_counts
)
load_counts

printf '\n=== 12. Download, Caching & Host Deps (_download, _cache_dirs, _download_file, _download_folder, _qbt_host_deps) Tests ===\n'
(
	# 12a. .qbt_env drift detection, bs mode sync, and symlink protection
	(
		load_lib
		script_parent_path="${test_root}/cache_env_test"
		qbt_cache_dir="${test_root}/cache_store"
		mkdir -p -- "${script_parent_path}" "${qbt_cache_dir}"
		printf 'qbt_qt_version="6"\n' > "${script_parent_path}/.qbt_env"

		qbt_cache_dir_options=""
		_cache_dirs_qbt_env_copy > /dev/null
		assert_pass_eq "initial cache copy writes .qbt_env" "$?" 'qbt_qt_version="6"' "$(< "${qbt_cache_dir}/.qbt_env")"

		printf 'qbt_qt_version="5"\n' > "${script_parent_path}/.qbt_env"
		drift_out="$(_cache_dirs_qbt_env)"
		assert_fail_contains "modified .qbt_env triggers drift warning (return 1) with SHA256" "$?" "${drift_out}" "SHA256:"
		assert_eq "non-bs run preserves cached .qbt_env" 'qbt_qt_version="6"' "$(< "${qbt_cache_dir}/.qbt_env")"

		qbt_cache_dir_options="bs"
		_cache_dirs_qbt_env > /dev/null
		assert_pass_eq "bs mode syncs .qbt_env and returns 0" "$?" 'qbt_qt_version="5"' "$(< "${qbt_cache_dir}/.qbt_env")"

		# Refuses to overwrite symlinked cached .qbt_env
		printf 'PROTECTED\n' > "${test_root}/protected_env_target"
		ln -fsn -- "${test_root}/protected_env_target" "${qbt_cache_dir}/.qbt_env"
		_cache_dirs_qbt_env_copy > /dev/null
		assert_exit "_cache_dirs_qbt_env_copy refuses symlinked cached .qbt_env" 1 "$?"
		assert_eq "_cache_dirs_qbt_env_copy preserved symlink target" "PROTECTED" "$(< "${test_root}/protected_env_target")"

		# _cache_dirs path normalization and source_default rules
		qbt_working_dir="${test_root}/cd_wd"
		qbt_cache_dir="rel_cache"
		app_name="zlib"
		qbt_workflow_files="yes"
		qbt_workflow_override[zlib]="no"
		qbt_cache_dir_options="bs"
		_cache_dirs
		assert_eq "_cache_dirs resolves relative cache dir" "${test_root}/cd_wd/rel_cache" "${qbt_cache_dir}"
		assert_eq "_cache_dirs workflow no-override forces file" "file" "${source_default[zlib]}"

		qbt_workflow_override[zlib]="yes"
		_cache_dirs
		assert_eq "_cache_dirs bs mode with override forces folder" "folder" "${source_default[zlib]}"
		save_counts
	)
	load_counts

	# 12b. _download dispatch + _download_file (normal, corrupt recovery in bs, corrupt fail in non-bs, curl fail, patch clean extract, _host_deps restore)
	(
		load_lib
		qbt_install_dir="${test_root}/dl_file_build"
		qbt_cache_dir="${test_root}/dl_file_cache"
		qbt_working_dir="${test_root}"
		mkdir -p -- "${qbt_install_dir}/logs" "${qbt_cache_dir}"
		mkdir -p -- "${test_root}/good_src/zlib-1.3.2"
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
			cp -f -- "${test_root}/good_zlib.tar.gz" "${out}"
			return 0
		}

		# Corrupt cached archive in bs mode recovers cleanly
		app_name="zlib"
		app_version[zlib]="1.3.2"
		source_type="source"
		qbt_cache_dir_options="bs"
		qbt_dl_dir="${qbt_cache_dir}"
		qbt_dl_file_path="${qbt_cache_dir}/zlib.tar.xz"
		qbt_dl_source_url="https://example.invalid/zlib.tar.xz"
		printf 'corrupt-bytes' > "${qbt_dl_file_path}"
		_download_file > /dev/null
		assert_pass_eq "_download_file in bs mode recovers from corrupt cached archive" "$?" "${qbt_install_dir}/zlib-1.3.2" "${qbt_dl_folder_path}"
		assert_dir_missing "_download_file in bs mode does not extract to install dir" "${qbt_install_dir}/zlib-1.3.2"

		# Non-bs mode extracts cached archive, creates sub_dir, logs URL, restores _host_deps
		qbt_cache_dir_options=""
		qbt_with_qemu="no"
		qbt_workflow_files="yes"
		qbt_workflow_override[zlib]="no"
		source_default[zlib]="file"
		qbt_workflow_archive_url[zlib]="https://example.invalid/wf/zlib.tar.xz"
		sub_dir="/sub"
		_download "zlib_host_deps" > /dev/null
		dl_rc=$?
		assert_pass_eq "_download restores _host_deps suffix when qbt_with_qemu=no" "${dl_rc}" "zlib_host_deps" "${app_name}"
		assert_dir_exists "_download_file extracts and creates sub_dir" "${qbt_install_dir}/zlib-1.3.2/sub"
		assert_eq "_download_file logs workflow archive URL" "https://example.invalid/wf/zlib.tar.xz" "$(< "${qbt_install_dir}/logs/zlib_workflow_archive_url.log")"
		_popd

		# Corrupt archive in non-bs mode exits 1
		(
			qbt_cache_dir_options=""
			app_name="zlib"
			qbt_dl_file_path="${test_root}/corrupt_nonbs.tar.xz"
			printf 'garbage' > "${qbt_dl_file_path}"
			_download_file > /dev/null 2>&1
		)
		assert_exit "_download_file exits 1 on corrupt archive in non-bs mode" 1 "$?"

		# Failed _curl download exits 1
		(
			qbt_cache_dir_options=""
			app_name="zlib"
			qbt_dl_file_path="${test_root}/missing_dl.tar.xz"
			_curl() { return 1; }
			_download_file > /dev/null 2>&1
		)
		assert_exit "_download_file exits 1 when _curl fails" 1 "$?"

		# Invalid app_name with .. exits 1
		(
			qbt_cache_dir_options=""
			app_name="../evil"
			qbt_dl_file_path="${qbt_cache_dir}/zlib.tar.xz"
			_download_file > /dev/null 2>&1
		)
		assert_exit "_download_file rejects unsafe app_name" 1 "$?"

		# Cached archive hit in non-bs mode does NOT call _curl again, and workflow_override=yes uses source URL
		(
			curl_called="no"
			_curl() {
				curl_called="yes"
				return 1
			}
			qbt_cache_dir_options=""
			qbt_workflow_files="yes"
			qbt_workflow_override[zlib]="yes"
			source_default[zlib]="file"
			source_archive_url[zlib]="https://example.invalid/direct/zlib.tar.gz"
			sub_dir=""
			_download "zlib" > "${test_root}/dl_hit.out"
			hit_rc=$?
			assert_contains "_download_file cached hit prints Extracting" "${hit_rc}" "$(< "${test_root}/dl_hit.out")" "Extracting"
			assert_eq "_download_file cached hit does not re-download via _curl" "no" "${curl_called}"
			assert_eq "_download workflow_override=yes logs source URL" "https://example.invalid/direct/zlib.tar.gz" "$(< "${qbt_install_dir}/logs/zlib_source_archive_url.log")"
			_popd
			save_counts
		)
		load_counts

		# _download creates missing qbt_install_dir automatically before _pushd
		(
			qbt_install_dir="${test_root}/auto_created_install_dir"
			qbt_cache_dir=""
			qbt_cache_dir_options=""
			qbt_workflow_files="no"
			source_default[zlib]="none"
			_download "zlib" > /dev/null
			assert_exit "_download succeeds on missing qbt_install_dir" 0 "$?"
			assert_dir_exists "_download creates missing qbt_install_dir before _pushd" "${qbt_install_dir}"
			_popd
			save_counts
		)
		load_counts
		save_counts
	)
	load_counts

	# 12c. _download_folder: local git clone, shallow branch multi-commit cache bs update (v1 -> v3), cache copy, clean re-clone on patches, nproc fallback, qttools submodules
	(
		load_lib
		qbt_working_dir="${test_root}"
		qbt_install_dir="${test_root}/dl_fold_build"
		qbt_cache_dir="${test_root}/dl_fold_cache"
		mkdir -p -- "${qbt_install_dir}/logs" "${qbt_cache_dir}"
		: > "${GIT_CONFIG_GLOBAL}"

		upstream_repo="${test_root}/upstream_qbt_repo"
		git init -q "${upstream_repo}"
		git -C "${upstream_repo}" config user.email "t@e"
		git -C "${upstream_repo}" config user.name "T"
		printf 'v1\n' > "${upstream_repo}/ver.txt"
		git -C "${upstream_repo}" add ver.txt
		git -C "${upstream_repo}" commit -qm "c1"
		git -C "${upstream_repo}" branch -M master
		git -C "${upstream_repo}" tag v1.3.2

		app_name="zlib"
		app_version[zlib]="1.3.2"
		github_tag[zlib]="master"
		github_url[zlib]="https://example.invalid/zlib.git"
		_curl() { return 0; }
		_git_git() {
			local -a args=()
			local a
			for a in "${@}"; do
				if [[ ${a} == "https://example.invalid/zlib.git" ]]; then
					args+=("file://${upstream_repo}")
				else
					args+=("${a}")
				fi
			done
			command git "${args[@]}"
		}

		# Cache bs initial shallow clone on branch master
		qbt_cache_dir_options="bs"
		qbt_dl_folder_path="${qbt_cache_dir}/zlib"
		_download_folder > /dev/null 2>&1
		assert_pass_eq "_download_folder bs clones initial v1 into cache dir" "$?" "v1" "$(< "${qbt_cache_dir}/zlib/ver.txt")"
		assert_eq "_download_folder logs github_url" "https://example.invalid/zlib.git" "$(< "${qbt_install_dir}/logs/zlib_github_url.log")"
		assert_eq "_download_folder does not mutate GIT_CONFIG_GLOBAL" "" "$(< "${GIT_CONFIG_GLOBAL}")"

		# Advance upstream master by 2 commits (non-fast-forward across shallow --depth 1 boundary!)
		printf 'v2\n' > "${upstream_repo}/ver.txt"
		git -C "${upstream_repo}" commit -am "c2" -q
		printf 'v3\n' > "${upstream_repo}/ver.txt"
		git -C "${upstream_repo}" commit -am "c3" -q

		qbt_dl_folder_path="${qbt_cache_dir}/zlib"
		upd_out="$(_download_folder 2> /dev/null)"
		upd_rc=$?
		assert_contains "_download_folder bs updates existing shallow branch repo" "${upd_rc}" "${upd_out}" "Updating directory"
		assert_eq "_download_folder bs updates working tree to latest commit v3" "v3" "$(< "${qbt_cache_dir}/zlib/ver.txt")"

		# Also verify tag update in bs mode
		github_tag[zlib]="v1.3.2"
		qbt_dl_folder_path="${qbt_cache_dir}/zlib"
		_download_folder > /dev/null 2>&1
		assert_pass_eq "_download_folder bs switches cached repo to tag v1.3.2" "$?" "v1" "$(< "${qbt_cache_dir}/zlib/ver.txt")"

		# Non-bs run copies from cache to install_dir (even when patches exist, cache dir preserved!)
		mkdir -p -- "${qbt_install_dir}/patches/zlib/1.3.2"
		printf 'dummy\n' > "${qbt_install_dir}/patches/zlib/1.3.2/patch"
		printf 'keep\n' > "${qbt_cache_dir}/zlib/cache_sentinel"
		qbt_cache_dir_options=""
		qbt_dl_folder_path="${qbt_cache_dir}/zlib"
		_download_folder > /dev/null 2>&1
		assert_exit "_download_folder cache copy exits 0" 0 "$?"
		assert_file_exists "_download_folder copies cached repo to install dir" "${qbt_install_dir}/zlib/ver.txt"
		assert_dir_exists "_download_folder preserves cache dir when patches exist" "${qbt_cache_dir}/zlib"
		assert_file_exists "_download_folder leaves cached repo contents untouched when patches exist" "${qbt_cache_dir}/zlib/cache_sentinel"
		_popd

		# Non-cache mode with patches forces clean clone + nproc failure falls back to single-threaded clone
		(
			qbt_cache_dir=""
			qbt_cache_dir_options=""
			qbt_dl_folder_path="${qbt_install_dir}/zlib"
			nproc() { return 1; }
			out_nc="$(_download_folder 2> /dev/null)"
			nc_rc=$?
			assert_contains "_download_folder non-cache with patches forces clean clone" "${nc_rc}" "${out_nc}" "Forcing clean clone due to patches"
			assert_contains "_download_folder falls back when nproc fails" "${nc_rc}" "${out_nc}" "single-threaded clone"
			save_counts
		)
		load_counts

		# Isolated qttools submodule update path (success and failure -> _error_tag)
		(
			qt_up_repo="${test_root}/upstream_qttools_repo"
			git init -q "${qt_up_repo}"
			git -C "${qt_up_repo}" config user.email "t@e"
			git -C "${qt_up_repo}" config user.name "T"
			printf 'qt\n' > "${qt_up_repo}/qt.txt"
			git -C "${qt_up_repo}" add qt.txt
			git -C "${qt_up_repo}" commit -qm "qt"
			git -C "${qt_up_repo}" tag v6.8.2

			qbt_cache_dir=""
			qbt_cache_dir_options=""
			app_name="qttools"
			app_version[qttools]="6.8.2"
			github_tag[qttools]="v6.8.2"
			github_url[qttools]="https://example.invalid/qttools.git"
			qbt_dl_folder_path="${qbt_install_dir}/qttools"
			submod_ran="no"
			_git_git() {
				if [[ ${1} == "submodule" ]]; then
					submod_ran="yes"
					return 0
				fi
				local -a args=()
				local a
				for a in "${@}"; do
					[[ ${a} == "https://example.invalid/qttools.git" ]] && args+=("file://${qt_up_repo}") || args+=("${a}")
				done
				command git "${args[@]}"
			}
			_download_folder > /dev/null 2>&1
			assert_pass_eq "_download_folder qttools invokes submodule update" "$?" "yes" "${submod_ran}"
			_popd

			rm -rf -- "${qbt_install_dir}/qttools"
			_git_git() {
				if [[ ${1} == "submodule" ]]; then return 1; fi
				local -a args=()
				local a
				for a in "${@}"; do
					[[ ${a} == "https://example.invalid/qttools.git" ]] && args+=("file://${qt_up_repo}") || args+=("${a}")
				done
				command git "${args[@]}"
			}
			(_download_folder > /dev/null 2>&1)
			assert_exit "_download_folder qttools exits 1 if submodule update fails" 1 "$?"
			save_counts
		)
		load_counts
		save_counts
	)
	load_counts

	# 12d. _qbt_host_deps URL/name resolution, repo validation & unsupported host arch rejection
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_working_dir="${test_root}"
		qbt_host_deps_repo="userdocs/qbt-host-deps"
		downloaded_name=""
		_download() { downloaded_name="${1}"; }

		qbt_host_deps="no"
		qbt_cross_name="aarch64"
		_qbt_host_deps
		assert_eq "_qbt_host_deps no-op when qbt_host_deps=no" "" "${downloaded_name}"

		qbt_host_deps="yes"
		qbt_cross_name="default"
		_qbt_host_deps
		assert_eq "_qbt_host_deps no-op when native default" "" "${downloaded_name}"

		qbt_cross_name="aarch64"
		qbt_skip_icu="yes"
		_qbt_host_deps
		assert_pass_eq "_qbt_host_deps amd64 skip_icu=yes name" "$?" "x86_64-host-deps" "${downloaded_name}"
		assert_eq "_qbt_host_deps amd64 skip_icu=yes URL" "https://github.com/userdocs/qbt-host-deps/releases/latest/download/x86_64-host-deps.tar.xz" "${source_archive_url["x86_64-host-deps"]}"

		os_arch="arm64"
		qbt_skip_icu="no"
		_qbt_host_deps
		assert_pass_eq "_qbt_host_deps arm64 skip_icu=no name" "$?" "aarch64-icu-host-deps" "${downloaded_name}"
		assert_eq "_qbt_host_deps arm64 skip_icu=no URL" "https://github.com/userdocs/qbt-host-deps/releases/latest/download/aarch64-icu-host-deps.tar.xz" "${source_archive_url["aarch64-icu-host-deps"]}"

		(
			os_arch="s390x"
			_qbt_host_deps > /dev/null 2>&1
		)
		assert_exit "_qbt_host_deps exits 1 on unsupported host arch s390x" 1 "$?"

		(
			qbt_host_deps_repo="userdocs/.."
			_qbt_host_deps > /dev/null 2>&1
		)
		assert_exit "_qbt_host_deps rejects traversal qbt_host_deps_repo" 1 "$?"
		save_counts
	)
	load_counts

	save_counts
)
load_counts

printf '\n=== 13. Static Link Fixes, Cleanup (_delete_function), & Install Tests ===\n'
(
	load_lib
	qbt_working_dir="${test_root}"
	qbt_install_dir="${test_root}/links_build"
	lib_dir="${qbt_install_dir}/lib"
	mkdir -p -- "${lib_dir}" "${qbt_install_dir}/logs" "${qbt_install_dir}/aarch64-linux-musl/lib"
	: > "${lib_dir}/libz.a"
	: > "${lib_dir}/libssl.a"
	ln -fsn -- "old_target.so" "${lib_dir}/libz.so"
	: > "${qbt_install_dir}/aarch64-linux-musl/lib/libfoo.a"
	app_name="zlib"
	_fix_static_links
	fsl_rc=$?
	assert_pass_eq "_fix_static_links replaces existing libz.so with libz.a" "${fsl_rc}" "libz.a" "$(readlink "${lib_dir}/libz.so")"
	assert_eq "_fix_static_links links libssl.so to libssl.a" "libssl.a" "$(readlink "${lib_dir}/libssl.so")"
	assert_contains "_fix_static_links logs symlink update" "${fsl_rc}" "$(< "${qbt_install_dir}/logs/zlib-fix-static-links.log")" "libz.so changed to point to libz.a"
	_fix_multiarch_static_links "aarch64-linux-musl"
	assert_pass_eq "_fix_multiarch_static_links points libfoo.so to libfoo.a" "$?" "libfoo.a" "$(readlink "${qbt_install_dir}/aarch64-linux-musl/lib/libfoo.so")"
	_fix_multiarch_static_links "nonexistent-triplet"
	assert_exit "_fix_multiarch_static_links no-op when dir missing" 0 "$?"

	# _delete_function removes archive dir + base_app_name.tar.xz for *_host_deps
	mkdir -p -- "${test_root}/del_src/icu-76" "${qbt_install_dir}/icu-76" "${qbt_install_dir}/icu"
	printf 'x\n' > "${test_root}/del_src/icu-76/f"
	tar -czf "${qbt_install_dir}/icu.tar.xz" -C "${test_root}/del_src" "icu-76"
	app_name="icu_host_deps"
	qbt_dl_file_path="${qbt_install_dir}/icu.tar.xz"
	qbt_skip_delete="no"
	_delete_function > /dev/null
	assert_exit "_delete_function exits 0" 0 "$?"
	assert_file_missing "_delete_function removes base_app_name.tar.xz" "${qbt_install_dir}/icu.tar.xz"
	assert_dir_missing "_delete_function removes extracted archive dir" "${qbt_install_dir}/icu-76"
	assert_dir_missing "_delete_function removes base app dir" "${qbt_install_dir}/icu"

	# _delete_function handles corrupt archive and unsafe app_name gracefully with warnings
	printf 'corrupt' > "${qbt_install_dir}/bad.tar.xz"
	app_name="../unsafe"
	qbt_dl_file_path="${qbt_install_dir}/bad.tar.xz"
	del_warn="$(_delete_function)"
	del_rc=$?
	assert_contains "_delete_function warns on corrupt archive" "${del_rc}" "${del_warn}" "Could not safely determine archive directory name"
	assert_contains "_delete_function refuses invalid app_name" "${del_rc}" "${del_warn}" "Invalid app_name for deletion"

	# _delete_function respects qbt_skip_delete=yes
	mkdir -p -- "${qbt_install_dir}/zlib"
	app_name="zlib"
	qbt_dl_file_path="${qbt_install_dir}/nonexistent.tar.xz"
	qbt_skip_delete="yes"
	_delete_function > /dev/null
	assert_exit "_delete_function skip exits 0" 0 "$?"
	assert_dir_exists "_delete_function preserves files when qbt_skip_delete=yes" "${qbt_install_dir}/zlib"

	# _install_qbittorrent tests (mock id to guarantee non-root regardless of runner)
	inst_home="${test_root}/inst_home"
	inst_build="${test_root}/inst_build"
	mock_id_dir="${test_root}/mock_id_user"
	mkdir -p -- "${inst_home}" "${inst_build}/completed" "${mock_id_dir}"
	printf '#!/bin/sh\nprintf "testuser\\n"\n' > "${mock_id_dir}/id"
	chmod +x -- "${mock_id_dir}/id"
	LOCAL_USER_HOME="${inst_home}"
	qbt_install_dir="${inst_build}"
	qbt_install_dir_short="${inst_build}"
	qbt_local_paths="/usr/bin"
	command_privilege=("printf" "PRIV_USED:")

	(PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install > /dev/null 2>&1)
	assert_exit "_install_qbittorrent exits 1 when binary missing" 1 "$?"

	printf '#!/bin/sh\nexit 0\n' > "${inst_build}/completed/qbittorrent-nox"
	chmod 0644 "${inst_build}/completed/qbittorrent-nox"

	out_local="$(PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install)"
	assert_contains "_install_qbittorrent local exits 0 and prints full path when not in PATH" "$?" "${out_local}" "${inst_home}/bin/qbittorrent-nox"
	if [[ -x "${inst_home}/bin/qbittorrent-nox" ]]; then
		pass "_install_qbittorrent local installs executable to LOCAL_USER_HOME/bin"
	else
		fail "_install_qbittorrent local" "binary missing or not executable"
	fi

	# When LOCAL_USER_HOME/bin IS in qbt_local_paths, shows bare qbittorrent-nox command
	out_in_path="$(qbt_local_paths="${inst_home}/bin:/usr/bin" PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install)"
	in_path_rc=$?
	assert_not_contains "_install_qbittorrent prints bare command when dir in PATH" "${in_path_rc}" "${out_in_path}" "${inst_home}/bin/qbittorrent-nox"
	assert_contains "_install_qbittorrent includes bare qbittorrent-nox command" "${in_path_rc}" "${out_in_path}" "qbittorrent-nox"

	# Root method uses command_privilege and targets /usr/local/bin
	out_root="$(_install_qbittorrent install root)"
	root_rc=$?
	assert_contains "_install_qbittorrent root uses command_privilege" "${root_rc}" "${out_root}" "PRIV_USED:"
	assert_contains "_install_qbittorrent root targets /usr/local/bin" "${root_rc}" "${out_root}" "cp -f -- ${inst_build}/completed/qbittorrent-nox /usr/local/bin"

	# Custom install inside LOCAL_USER_HOME using ~ expansion AND double-dot directory name (~/bin..local/) must succeed without privileges
	# shellcheck disable=SC2088
	out_user_custom="$(PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install custom "~/bin..local/")"
	uc_rc=$?
	assert_not_contains "_install_qbittorrent custom inside home avoids command_privilege" "${uc_rc}" "${out_user_custom}" "PRIV_USED:"
	assert_file_exists "_install_qbittorrent custom ~/bin..local installed binary" "${inst_home}/bin..local/qbittorrent-nox"

	# Custom install outside LOCAL_USER_HOME invokes command_privilege
	out_sys_custom="$(PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install custom "${test_root}/outside_home_bin")"
	assert_contains "_install_qbittorrent custom outside home uses command_privilege" "$?" "${out_sys_custom}" "PRIV_USED:"

	# Relative custom path avoids command_privilege even outside LOCAL_USER_HOME
	out_rel_custom="$(cd "${test_root}" && PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install custom "rel_bin")"
	assert_not_contains "_install_qbittorrent custom relative path avoids command_privilege" "$?" "${out_rel_custom}" "PRIV_USED:"
	assert_file_exists "_install_qbittorrent custom relative path installed binary" "${test_root}/rel_bin/qbittorrent-nox"

	# Nested non-existent custom path inside symlinked LOCAL_USER_HOME avoids command_privilege
	real_sym_home="${test_root}/real_sym_home"
	link_sym_home="${test_root}/link_sym_home"
	outside_sym_target="${test_root}/outside_sym_target"
	mkdir -p -- "${real_sym_home}" "${outside_sym_target}"
	ln -s -- "${real_sym_home}" "${link_sym_home}"
	ln -s -- "${outside_sym_target}" "${real_sym_home}/escape_to_system"
	# shellcheck disable=SC2088
	out_sym_nested="$(LOCAL_USER_HOME="${link_sym_home}" PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install custom "~/missing_parent/nested_bin")"
	assert_not_contains "_install_qbittorrent custom nested missing dir under symlinked home avoids command_privilege" "$?" "${out_sym_nested}" "PRIV_USED:"

	# Symlink inside home pointing outside home uses command_privilege when passed as an absolute path
	out_sym_escape="$(LOCAL_USER_HOME="${link_sym_home}" PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install custom "${link_sym_home}/escape_to_system")"
	assert_contains "_install_qbittorrent custom symlink pointing outside home uses command_privilege" "$?" "${out_sym_escape}" "PRIV_USED:"

	# Traversal and missing path rejected
	(PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install custom "${inst_home}/../escape" > /dev/null 2>&1)
	assert_exit "_install_qbittorrent custom rejects .. traversal" 1 "$?"
	(PATH="${mock_id_dir}:${PATH}" _install_qbittorrent install custom > /dev/null 2>&1)
	assert_exit "_install_qbittorrent custom exits 1 when path omitted" 1 "$?"

	save_counts
)
load_counts

printf '\n=== 14. Script Version Check & Release Info Tests ===\n'
(
	# 14a. _script_version checks (including non-semver / terminal-escape rejection)
	(
		load_lib
		script_full_path="${test_root}/ver_script.bash"
		script_url="https://example.invalid/qbt-nox-static.bash"
		printf 'script_version="2.2.6"\n' > "${script_full_path}"
		script_version="2.2.6"

		_curl() { return 0; }
		sv_out="$(_script_version)"
		assert_contains "_script_version handles empty remote content" "$?" "${sv_out}" "Could not fetch remote script"

		_curl() { printf 'not a script\n'; }
		sv_out="$(_script_version)"
		assert_contains "_script_version handles unparseable remote version" "$?" "${sv_out}" "Could not parse remote script version"

		# Rejects malformed / ANSI-escape-injected script_version line
		_curl() { printf 'script_version="9.9.9\\e[31mINJECTED"\n'; }
		sv_out="$(_script_version)"
		sv_rc=$?
		assert_contains "_script_version rejects escape-injected remote version" "${sv_rc}" "${sv_out}" "Could not parse remote script version"
		assert_not_contains "_script_version does not echo injected version" "${sv_rc}" "${sv_out}" "INJECTED"

		_curl() { printf 'script_version="2.2.7"\r\n'; }
		sv_out="$(_script_version)"
		assert_contains "_script_version detects update available even with CRLF" "$?" "${sv_out}" "Script update available"

		_curl() { printf 'script_version="2.2.5"\n'; }
		sv_out="$(_script_version)"
		assert_contains "_script_version detects dev version" "$?" "${sv_out}" "2.2.6-dev"

		_curl() { printf 'script_version="2.2.6"\n'; }
		sv_out="$(_script_version)"
		sv_rc=$?
		assert_not_contains "_script_version clean on exact match" "${sv_rc}" "${sv_out}" "differs from the remote"
		assert_contains "_script_version prints current version" "${sv_rc}" "${sv_out}" "2.2.6"

		_curl() { printf 'script_version="2.2.6"\n# extra\n'; }
		sv_out="$(_script_version)"
		assert_contains "_script_version warns on SHA256 mismatch" "$?" "${sv_out}" "differs from the remote version"
		save_counts
	)
	load_counts

	# 14b. _release_info fails via _error_tag when error_tag is present
	(
		load_lib
		github_tag[zlib]="error_tag"
		_release_info > /dev/null 2>&1
	)
	assert_exit "_release_info exits 1 if error_tag present" 1 "$?"

	# 14c. Isolated _release_info: remote revision 3 -> 4 (with jq), valid JSON, workflow text, zlib-ng
	(
		load_lib
		qbt_install_dir="${test_root}/rel_jq_build"
		qbt_revision_url="userdocs/qbittorrent-nox-static"
		qbt_libtorrent_version="1.2"
		qbt_zlib_type="zlib-ng"
		qbt_workflow_files="yes"
		qbt_cross_name="riscv64"
		qt_version_short_array=(6 8)
		github_tag=([qbittorrent]="release-5.1.0" [libtorrent]="v1.2.20")
		app_version=([qbittorrent]="5.1.0" [libtorrent]="1.2.20" [qtbase]="6.8.2" [boost]="1.88.0" [openssl]="3.5.9" [zlib]="2.2.4")
		_git_git() { return 0; }
		_curl() {
			case "${*}" in
				*releases/tags/*) printf '{"assets":[{"name":"dependency-version.json"}]}' ;;
				*dependency-version.json*) printf '{"revision":"3"}' ;;
				*) return 1 ;;
			esac
		}
		_release_info > /dev/null
		ri_rc=$?
		assert_pass_eq "_release_info writes tag.md" "${ri_rc}" "release-5.1.0_v1.2.20" "$(< "${qbt_install_dir}/release_info/tag.md")"
		assert_eq "_release_info writes title.md" "qbittorrent 5.1.0 libtorrent 1.2.20" "$(< "${qbt_install_dir}/release_info/title.md")"
		jq empty "${qbt_install_dir}/release_info/qt6-dependency-version.json" 2> /dev/null
		assert_exit "_release_info produces valid JSON" 0 "$?"
		assert_contains "_release_info increments remote revision (jq)" "${ri_rc}" "$(< "${qbt_install_dir}/release_info/qt6-dependency-version.json")" '"revision": "4"'
		assert_contains "_release_info writes zlib-ng row" "${ri_rc}" "$(< "${qbt_install_dir}/release_info/qt6-riscv64-release.md")" "zlib-ng"
		assert_contains "_release_info writes workflow source_text" "${ri_rc}" "$(< "${qbt_install_dir}/release_info/qt6-riscv64-release.md")" "qbt-workflow-files"
		save_counts
	)
	load_counts

	# 14d. _release_info sed fallback (without jq) increments revision 7 -> 8, direct source_text
	(
		load_lib
		qbt_install_dir="${test_root}/rel_sed_build"
		qbt_revision_url="userdocs/qbittorrent-nox-static"
		qbt_libtorrent_version="1.2"
		qbt_zlib_type="zlib"
		qbt_workflow_files="no"
		qbt_cross_name="riscv64"
		qt_version_short_array=(6 8)
		github_tag=([qbittorrent]="release-5.1.0" [libtorrent]="v1.2.20")
		app_version=([qbittorrent]="5.1.0" [libtorrent]="1.2.20" [qtbase]="6.8.2" [boost]="1.88.0" [openssl]="3.5.9" [zlib]="1.3.2")
		no_jq_rel="${test_root}/no_jq_rel"
		mkdir -p -- "${no_jq_rel}"
		for c in sed head grep rm mkdir cat; do
			cp_bin="$(command -v "${c}" || true)"
			[[ -n ${cp_bin} ]] && ln -fsn -- "${cp_bin}" "${no_jq_rel}/${c}"
		done
		PATH="${no_jq_rel}"
		_git_git() { return 0; }
		_curl() {
			case "${*}" in
				*releases/tags/*) printf '{"assets":[{"name":"dependency-version.json"}]}' ;;
				*dependency-version.json*) printf '{"revision":"7"}' ;;
				*) return 1 ;;
			esac
		}
		_release_info > /dev/null
		ri_rc=$?
		assert_contains "_release_info sed fallback increments revision to 8" "${ri_rc}" "$(< "${qbt_install_dir}/release_info/qt6-dependency-version.json")" '"revision": "8"'
		assert_contains "_release_info direct source_text" "${ri_rc}" "$(< "${qbt_install_dir}/release_info/qt6-riscv64-release.md")" "source files - direct"
		save_counts
	)
	load_counts

	# 14e. _release_info defaults revision to 0 when remote tag does not exist + verifies all 15 arch tuning rows + jq rejects array [{"revision":"99"}] + owner/.. repo rejected
	(
		load_lib
		qbt_install_dir="${test_root}/rel_arch_build"
		qbt_revision_url="userdocs/qbittorrent-nox-static"
		qbt_libtorrent_version="1.2"
		qbt_zlib_type="zlib"
		qbt_workflow_files="yes"
		qt_version_short_array=(6 8)
		github_tag=([qbittorrent]="release-5.1.0" [libtorrent]="v1.2.20")
		app_version=([qbittorrent]="5.1.0" [libtorrent]="1.2.20" [qtbase]="6.8.2" [boost]="1.88.0" [openssl]="3.5.9" [zlib]="1.3.2")
		_git_git() { return 1; }
		for arch_row in "armel:arm-linux-musleabi" "armhf:arm-linux-musleabihf" "armv7:armv7l-linux-musleabihf" "aarch64:aarch64-linux-musl" "x86_64:x86_64-linux-musl" "x86:i686-linux-musl" "s390x:s390x-linux-musl" "powerpc:powerpc-linux-musl" "ppc64el:powerpc64le-linux-musl" "mips:mips-linux-musl" "mipsel:mipsel-linux-musl" "mips64:mips64-linux-musl" "mips64el:mips64el-linux-musl" "riscv64:riscv64-linux-musl" "loongarch64:loongarch64-linux-musl"; do
			IFS=':' read -r arch_key triplet_col <<< "${arch_row}"
			qbt_cross_name="${arch_key}"
			_release_info > /dev/null
			ri_rc=$?
			assert_contains "_release_info renders ${arch_key} row" "${ri_rc}" "$(< "${qbt_install_dir}/release_info/qt6-${arch_key}-release.md")" "${triplet_col}"
		done
		assert_contains "_release_info defaults revision to 0 on new tag" 0 "$(< "${qbt_install_dir}/release_info/qt6-dependency-version.json")" '"revision": "0"'

		# Non-object JSON array containing "revision":"99" must be rejected by jq (NOT parsed by sed!) and emit zero stderr
		_git_git() { return 0; }
		_curl() {
			case "${*}" in
				*releases/tags/*) printf '{"assets":[{"name":"dependency-version.json"}]}' ;;
				*dependency-version.json*) printf '{"revision":"11"}' ;;
				*) return 1 ;;
			esac
		}
		_release_info > /dev/null
		_curl() {
			case "${*}" in
				*releases/tags/*) printf '{"assets":[{"name":"dependency-version.json"}]}' ;;
				*dependency-version.json*) printf '[{"revision":"99"}]' ;;
				*) return 1 ;;
			esac
		}
		_release_info > /dev/null 2> "${test_root}/rel_nonobj.err"
		ri_rc=$?
		assert_pass_eq "_release_info non-object JSON emits zero jq stderr" "${ri_rc}" "" "$(< "${test_root}/rel_nonobj.err")"
		assert_contains "_release_info non-object array with revision field stays 0 (no sed bypass or state leak)" "${ri_rc}" "$(< "${qbt_install_dir}/release_info/qt6-dependency-version.json")" '"revision": "0"'

		# Malformed & traversal qbt_revision_url skipped without invoking git
		for bad_rev_repo in "bad/repo/extra" "owner/.." "../repo"; do
			rel_git_called="no"
			_git_git() {
				rel_git_called="yes"
				return 0
			}
			qbt_revision_url="${bad_rev_repo}"
			_release_info > /dev/null
			assert_pass_eq "_release_info skips '${bad_rev_repo}'" "$?" "no" "${rel_git_called}"
		done
		save_counts
	)
	load_counts

	save_counts
)
load_counts

printf '\n=== 15. Dependency Checker (_check_dependencies) Tests ===\n'
(
	setup_dep_mocks() {
		local mdir="${1}" id_out="${2}" sudo_rc="${3}" pkg_rc="${4}" sim_rc="${5}" log="${6}"
		mkdir -p -- "${mdir}"
		: > "${log}"
		printf '#!/bin/bash\nprintf "%%s\\n" "%s"\n' "${id_out}" > "${mdir}/id"
		cat > "${mdir}/sudo" <<- EOF
			#!/bin/bash
			if [[ \${1} == "-n" ]]; then exit ${sudo_rc}; fi
			printf 'sudo %s\n' "\$*" >> "${log}"
			[[ \${1} == "-E" ]] && shift
			exec "\$@"
		EOF
		cat > "${mdir}/dpkg" <<- EOF
			#!/bin/bash
			printf 'dpkg %s\n' "\$*" >> "${log}"
			if [[ -f "${mdir}/installed_all" ]]; then exit 0; fi
			exit ${pkg_rc}
		EOF
		cat > "${mdir}/apt" <<- EOF
			#!/bin/bash
			printf 'apt %s\n' "\$*" >> "${log}"
			exit ${sim_rc}
		EOF
		cat > "${mdir}/apt-get" <<- EOF
			#!/bin/bash
			printf 'apt-get %s\n' "\$*" >> "${log}"
			if [[ \${1} == "install" ]]; then touch "${mdir}/installed_all"; fi
			exit 0
		EOF
		cat > "${mdir}/apk" <<- EOF
			#!/bin/bash
			printf 'apk %s\n' "\$*" >> "${log}"
			if [[ \${1} == "info" ]]; then
				[[ -f "${mdir}/installed_all" ]] && exit 0
				exit ${pkg_rc}
			fi
			if [[ \${*} == *"--simulate"* ]]; then exit ${sim_rc}; fi
			if [[ \${1} == "add" ]]; then touch "${mdir}/installed_all"; fi
			exit 0
		EOF
		chmod +x -- "${mdir}/id" "${mdir}/sudo" "${mdir}/dpkg" "${mdir}/apt" "${mdir}/apt-get" "${mdir}/apk"
	}

	# 15a. Root user + all deps installed -> passes and filters dep action args
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values
		mdir="${test_root}/dep_root_ok"
		dlog="${test_root}/dep_root_ok.log"
		setup_dep_mocks "${mdir}" "root" 1 0 0 "${dlog}"
		PATH="${mdir}:${PATH}"
		_check_dependencies debug update zlib -h > "${test_root}/dep_root.out"
		dep_rc=$?
		assert_contains "_check_dependencies passes and prints All checks passed" "${dep_rc}" "$(< "${test_root}/dep_root.out")" "All checks passed"
		assert_eq "_check_dependencies root sets empty command_privilege" "" "${command_privilege[*]}"
		assert_eq "_check_dependencies filters action args" "zlib -h" "${filtered_check_dependency_args[*]}"
		assert_contains "_check_dependencies explicit update invokes apt-get update" "${dep_rc}" "$(< "${dlog}")" "apt-get update"
		save_counts
	)
	load_counts

	# 15a2. Missing test_tools exits 1; install_core fails if core deps remain missing
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values
		mdir="${test_root}/dep_no_curl"
		dlog="${test_root}/dep_no_curl.log"
		setup_dep_mocks "${mdir}" "root" 1 0 0 "${dlog}"
		for c in bash git sort; do
			cp_bin="$(command -v "${c}" || true)"
			[[ -n ${cp_bin} ]] && ln -fsn -- "${cp_bin}" "${mdir}/${c}"
		done
		out_nt="$(PATH="${mdir}" _check_dependencies -h 2>&1)"
		assert_fail_contains "_check_dependencies exits 1 and reports missing test_tools" "$?" "${out_nt}" "Missing required"

		mdir2="${test_root}/dep_still_missing"
		dlog2="${test_root}/dep_still_missing.log"
		setup_dep_mocks "${mdir2}" "root" 1 1 0 "${dlog2}"
		printf '#!/bin/bash\nexit 0\n' > "${mdir2}/apt-get"
		chmod +x -- "${mdir2}/apt-get"
		(PATH="${mdir2}:${PATH}" _check_dependencies install_core > /dev/null 2>&1)
		assert_exit "_check_dependencies install_core exits 1 when deps still missing after install" 1 "$?"
		save_counts
	)
	load_counts

	# 15b. Non-root without sudo + missing deps -> exits 1 with apt-get hint (Debian) & apk hint (Alpine)
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values
		mdir="${test_root}/dep_nopriv_deb"
		dlog="${test_root}/dep_nopriv_deb.log"
		setup_dep_mocks "${mdir}" "bob" 1 1 0 "${dlog}"
		PATH="${mdir}:${PATH}"
		out="$(_check_dependencies zlib 2>&1)"
		assert_fail_contains "_check_dependencies non-root no-sudo missing deps exits 1 with apt-get hint" "$?" "${out}" "apt-get install -y"
		save_counts
	)
	load_counts

	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		_set_default_values
		mdir="${test_root}/dep_nopriv_alp"
		dlog="${test_root}/dep_nopriv_alp.log"
		setup_dep_mocks "${mdir}" "bob" 1 1 0 "${dlog}"
		PATH="${mdir}:${PATH}"
		out="$(_check_dependencies zlib 2>&1)"
		assert_fail_contains "_check_dependencies non-root no-sudo missing deps exits 1 with apk add hint" "$?" "${out}" "apk add"
		save_counts
	)
	load_counts

	# 15b2. Non-root without sudo + all deps installed -> continues cleanly
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values
		mdir="${test_root}/dep_nopriv_ok"
		dlog="${test_root}/dep_nopriv_ok.log"
		setup_dep_mocks "${mdir}" "bob" 1 0 0 "${dlog}"
		PATH="${mdir}:${PATH}"
		out="$(_check_dependencies zlib 2>&1)"
		ok_rc=$?
		assert_contains "_check_dependencies non-root no-sudo with all deps present prints All checks passed" "${ok_rc}" "${out}" "All checks passed"
		assert_not_contains "_check_dependencies non-root no-sudo with all deps present does not warn about privileges" "${ok_rc}" "${out}" "No root or sudo privileges detected"
		out_priv_ic="$(_check_dependencies install_core 2>&1)"
		assert_fail_not_contains "_check_dependencies non-root install_core exits 1 and omits empty apt-get hint" "$?" "${out_priv_ic}" "apt-get install -y"
		save_counts
	)
	load_counts

	# 15c. Sudo user + missing deps + bootstrap_deps with failed simulation triggers update + install via sudo -E
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values
		mdir="${test_root}/dep_sudo_bs"
		dlog="${test_root}/dep_sudo_bs.log"
		setup_dep_mocks "${mdir}" "bob" 0 1 1 "${dlog}"
		PATH="${mdir}:${PATH}"
		_check_dependencies bootstrap_deps > /dev/null
		bs_rc=$?
		log_txt="$(< "${dlog}")"
		assert_contains "bootstrap_deps uses sudo -E" "${bs_rc}" "${log_txt}" "sudo -E"
		assert_contains "bootstrap_deps runs apt-get update when simulation fails" "${bs_rc}" "${log_txt}" "apt-get update"
		assert_contains "bootstrap_deps runs apt-get install -y" "${bs_rc}" "${log_txt}" "apt-get install -y"
		save_counts
	)
	load_counts

	# 15d. Privileged user + missing core deps: allowed for -h, blocked when passing a module name; legacy_mode auto-installs
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		_set_default_values
		mdir="${test_root}/dep_priv_missing"
		dlog="${test_root}/dep_priv_missing.log"
		setup_dep_mocks "${mdir}" "root" 1 1 0 "${dlog}"
		PATH="${mdir}:${PATH}"
		(_check_dependencies -h > /dev/null)
		assert_exit "_check_dependencies allows -h when privileged even if core deps missing" 0 "$?"
		(_check_dependencies zlib > /dev/null 2>&1)
		assert_exit "_check_dependencies blocks module build when core deps missing" 1 "$?"

		qbt_legacy_mode="yes"
		_check_dependencies zlib > /dev/null
		assert_contains "_check_dependencies qbt_legacy_mode=yes auto-installs missing core deps" "$?" "$(< "${dlog}")" "apt-get install -y"
		save_counts
	)
	load_counts

	# 15e. Alpine bootstrap_deps runs apk update + apk add
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		_set_default_values
		mdir="${test_root}/dep_alp_bs"
		dlog="${test_root}/dep_alp_bs.log"
		setup_dep_mocks "${mdir}" "root" 1 1 1 "${dlog}"
		PATH="${mdir}:${PATH}"
		_check_dependencies bootstrap_deps > /dev/null
		alp_rc=$?
		log_txt="$(< "${dlog}")"
		assert_contains "alpine bootstrap_deps runs apk update on sim failure" "${alp_rc}" "${log_txt}" "apk update"
		assert_contains "alpine bootstrap_deps runs apk add" "${alp_rc}" "${log_txt}" "apk add -u --no-cache"
		save_counts
	)
	load_counts

	save_counts
)
load_counts

printf '\n=== 16. Mocked Module Build Configuration & Command Tests (No Compilation) ===\n'
(
	# 16a. _glibc_bootstrap & _glibc
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/m_glibc"
		qbt_dl_folder_path="${test_root}/m_glibc/src"
		mkdir -p -- "${qbt_install_dir}/logs" "${qbt_dl_folder_path}/BUILD"
		mbin="${test_root}/m_glibc_bin"
		mlog="${test_root}/m_glibc.log"
		: > "${mlog}"
		make_mock_cmd "${mbin}" "make" "${mlog}" 0
		make_mock_cmd "${qbt_dl_folder_path}" "configure" "${mlog}" 0
		PATH="${mbin}:${PATH}"
		app_name="glibc"
		multi_glibc=("--host=riscv64-linux-gnu")
		_glibc_bootstrap
		assert_eq "_glibc_bootstrap sets sub_dir=/BUILD" "/BUILD" "${sub_dir}"
		(
			cd "${qbt_dl_folder_path}/BUILD" || exit 1
			_glibc > /dev/null
		)
		m_rc=$?
		log_txt="$(< "${mlog}")"
		assert_contains "_glibc configure passes --host and --enable-static-nss" "${m_rc}" "${log_txt}" "configure --host=riscv64-linux-gnu --prefix=${qbt_install_dir} --enable-cet --enable-static-nss --disable-nscd"
		assert_contains "_glibc installs C.UTF-8 locale" "${m_rc}" "${log_txt}" "make localedata/install-locales SUPPORTED-LOCALES=C.UTF-8/UTF-8"
		save_counts
	)
	load_counts

	# 16b. _zlib (zlib, zlib-ng + cmake, zlib-ng + qmake)
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/m_zlib"
		wdir="${test_root}/m_zlib_src"
		mbin="${test_root}/m_zlib_bin"
		mlog="${test_root}/m_zlib.log"
		mkdir -p -- "${qbt_install_dir}/logs" "${qbt_install_dir}/completed" "${wdir}"
		make_mock_cmd "${mbin}" "make" "${mlog}" 0
		make_mock_cmd "${mbin}" "cmake" "${mlog}" 0
		make_mock_cmd "${mbin}" "dot" "${mlog}" 0
		make_mock_cmd "${wdir}" "configure" "${mlog}" 0
		PATH="${mbin}:${PATH}"
		app_name="zlib"
		app_version[zlib]="1.3.2"
		qbt_cmake_build_type="Release"
		qbt_cmake_debug="OFF"
		qbt_standard="20"

		: > "${mlog}"
		qbt_zlib_type="zlib"
		(cd "${wdir}" && _zlib > /dev/null)
		assert_contains "_zlib classic configures with --static" "$?" "$(< "${mlog}")" "configure --prefix=${qbt_install_dir} --static"

		: > "${mlog}"
		qbt_zlib_type="zlib-ng"
		qbt_build_tool="cmake"
		(cd "${wdir}" && _zlib > /dev/null)
		m_rc=$?
		log_txt="$(< "${mlog}")"
		assert_contains "_zlib zlib-ng cmake sets BUILD_SHARED_LIBS=OFF and ZLIB_COMPAT=ON" "${m_rc}" "${log_txt}" "-D BUILD_SHARED_LIBS=OFF -D ZLIB_COMPAT=ON -D WITH_GTEST=OFF"
		assert_contains "_zlib zlib-ng cmake generates graph PNG via dot" "${m_rc}" "${log_txt}" "dot -Tpng -o ${qbt_install_dir}/completed/zlib-graph.png"

		: > "${mlog}"
		qbt_build_tool="qmake"
		(cd "${wdir}" && _zlib > /dev/null)
		assert_contains "_zlib zlib-ng qmake configures with --static --zlib-compat" "$?" "$(< "${mlog}")" "configure --prefix=${qbt_install_dir} --static --zlib-compat"
		save_counts
	)
	load_counts

	# 16c. _iconv (autogen/gitsub when configure missing vs skipped when present)
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/m_iconv"
		wdir="${test_root}/m_iconv_src"
		mbin="${test_root}/m_iconv_bin"
		mlog="${test_root}/m_iconv.log"
		mkdir -p -- "${qbt_install_dir}/logs" "${wdir}"
		make_mock_cmd "${mbin}" "make" "${mlog}" 0
		make_mock_cmd "${wdir}" "gitsub.sh" "${mlog}" 0
		make_mock_cmd "${wdir}" "autogen.sh" "${mlog}" 0 "cat > configure << 'S'
#!/bin/bash
printf 'configure %s\n' \"\$*\" >> \"${mlog}\"
S
chmod +x configure"
		PATH="${mbin}:${PATH}"
		app_name="iconv"
		multi_iconv=("--host=aarch64-linux-gnu")
		: > "${mlog}"
		(cd "${wdir}" && _iconv > /dev/null)
		m_rc=$?
		log_txt="$(< "${mlog}")"
		assert_contains "_iconv runs gitsub.sh pull when configure missing" "${m_rc}" "${log_txt}" "gitsub.sh pull --depth 1"
		assert_contains "_iconv runs autogen.sh when configure missing" "${m_rc}" "${log_txt}" "autogen.sh"
		assert_contains "_iconv configures with --disable-shared --enable-static" "${m_rc}" "${log_txt}" "configure --host=aarch64-linux-gnu --prefix=${qbt_install_dir} --disable-shared --enable-static"

		: > "${mlog}"
		qbt_cache_dir=""
		(cd "${wdir}" && _iconv > /dev/null)
		assert_not_contains "_iconv skips autogen.sh when configure exists" "$?" "$(< "${mlog}")" "autogen.sh"
		save_counts
	)
	load_counts

	# 16d. _set_icu_sub_dir, _icu_host_deps_bootstrap, _icu_host_deps, _icu_bootstrap, _icu
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/m_icu"
		qbt_host_deps_path="${qbt_install_dir}/host_deps"
		qbt_cache_dir="${test_root}/m_icu_cache"
		mkdir -p -- "${qbt_install_dir}/logs" "${qbt_cache_dir}/icu" "${qbt_install_dir}/icu/icu4c/source"
		mbin="${test_root}/m_icu_bin"
		mlog="${test_root}/m_icu.log"
		: > "${mlog}"
		make_mock_cmd "${mbin}" "make" "${mlog}" 0
		make_mock_cmd "${qbt_install_dir}/icu/icu4c/source" "runConfigureICU" "${mlog}" 0
		make_mock_cmd "${qbt_install_dir}/icu/icu4c/source" "configure" "${mlog}" 0
		PATH="${mbin}:${PATH}"

		qbt_workflow_files="no"
		app_name="icu_host_deps"
		_icu_host_deps_bootstrap
		assert_eq "_set_icu_sub_dir uses /icu4c/source for cached non-workflow icu_host_deps" "/icu4c/source" "${sub_dir}"
		_icu_host_deps > /dev/null
		assert_contains "_icu_host_deps invokes runConfigureICU Linux static" "$?" "$(< "${mlog}")" "runConfigureICU Linux --disable-shared --enable-static --disable-samples --disable-tests --with-data-packaging=static"

		: > "${mlog}"
		app_name="icu"
		multi_icu=("--host=aarch64-linux-gnu" "-with-cross-build=${qbt_host_deps_path}")
		(cd "${qbt_install_dir}/icu/icu4c/source" && _icu > /dev/null)
		assert_contains "_icu passes multi_icu and static flags" "$?" "$(< "${mlog}")" "configure --host=aarch64-linux-gnu -with-cross-build=${qbt_host_deps_path} --prefix=${qbt_install_dir} --disable-shared --enable-static"

		qbt_workflow_files="yes"
		_icu_bootstrap
		assert_eq "_set_icu_sub_dir uses /source for workflow files" "/source" "${sub_dir}"
		save_counts
	)
	load_counts

	# 16e. _openssl
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/m_ssl"
		lib_dir="${qbt_install_dir}/lib"
		wdir="${test_root}/m_ssl_src"
		mbin="${test_root}/m_ssl_bin"
		mlog="${test_root}/m_ssl.log"
		mkdir -p -- "${qbt_install_dir}/logs" "${wdir}"
		make_mock_cmd "${mbin}" "make" "${mlog}" 0
		make_mock_cmd "${wdir}" "Configure" "${mlog}" 0
		PATH="${mbin}:${PATH}"
		app_name="openssl"
		multi_openssl=("./Configure" "linux-aarch64")
		qbt_openssl_build_type="--release"
		: > "${mlog}"
		(cd "${wdir}" && _openssl > /dev/null)
		m_rc=$?
		log_txt="$(< "${mlog}")"
		assert_contains "_openssl passes target, libdir, openssldir, no-shared, no-weak-ssl-ciphers" "${m_rc}" "${log_txt}" "Configure linux-aarch64 --prefix=${qbt_install_dir} --libdir=lib --openssldir=/etc/ssl --release threads no-shared no-dso"
		assert_contains "_openssl runs make install_sw (not make install)" "${m_rc}" "${log_txt}" "make install_sw"
		save_counts
	)
	load_counts

	# 16f. _boost_bootstrap & _boost (cmake skip b2, folder b2 + static patch + symlink, missing build.sh error)
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/m_boost"
		mkdir -p -- "${qbt_install_dir}/logs" "${qbt_install_dir}/boost-1.88.0/boost"
		app_name="boost"

		source_default[boost]="file"
		boost_url_status="403"
		qbt_workflow_files="yes"
		_boost_bootstrap
		assert_eq "_boost_bootstrap keeps file when qbt_workflow_files=yes" "file" "${source_default[boost]}"
		qbt_workflow_files="no"
		_boost_bootstrap > /dev/null
		assert_eq "_boost_bootstrap falls back to folder on 403 when workflow_files=no" "folder" "${source_default[boost]}"

		source_default[boost]="file"
		qbt_build_tool="cmake"
		qbt_dl_folder_path="${qbt_install_dir}/boost-1.88.0"
		_pushd "${qbt_dl_folder_path}"
		out_b="$(_boost)"
		assert_contains "_boost skips b2 for cmake + file" "$?" "${out_b}" "Skipping b2"
		assert_dir_exists "_boost moves extracted dir to install_dir/boost" "${qbt_install_dir}/boost/boost"
		_popd

		b_log="${test_root}/m_boost.log"
		: > "${b_log}"
		mkdir -p -- "${qbt_install_dir}/boost/tools/build/src/engine"
		printf 'gcc -o b2 main.c\n' > "${qbt_install_dir}/boost/tools/build/src/engine/build.sh"
		make_mock_cmd "${qbt_install_dir}/boost" "bootstrap.sh" "${b_log}" 0 "cat > \"${qbt_install_dir}/boost/b2\" << 'B2'
#!/bin/bash
printf 'b2 %s\n' \"\$*\" >> \"${b_log}\"
B2
chmod +x \"${qbt_install_dir}/boost/b2\""
		source_default[boost]="folder"
		qbt_with_qemu="yes"
		_boost > /dev/null
		b_rc=$?
		assert_contains "_boost patches build.sh with -static --static -o b2" "${b_rc}" "$(< "${qbt_install_dir}/boost/tools/build/src/engine/build.sh")" "-static --static -o b2"
		assert_eq "_boost links boost/include -> boost/boost" "${qbt_install_dir}/boost/boost" "$(readlink "${qbt_install_dir}/boost/include")"
		assert_contains "_boost folder mode runs b2 headers" "${b_rc}" "$(< "${b_log}")" "b2 headers"

		rm -f -- "${qbt_install_dir}/boost/b2" "${qbt_install_dir}/boost/tools/build/src/engine/build.sh"
		(_boost > /dev/null 2>&1)
		assert_exit "_boost exits 1 when build.sh missing" 1 "$?"
		save_counts
	)
	load_counts

	# 16g. _libtorrent (cmake with/without libiconv.a, b2 1.2 + 2.0 + 32-bit armv7 libatomic + pkg-config generation)
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/m_lt"
		lib_dir="${qbt_install_dir}/lib"
		PKG_CONFIG_PATH="${lib_dir}/pkgconfig"
		wdir="${test_root}/m_lt_src"
		mbin="${test_root}/m_lt_bin"
		mlog="${test_root}/m_lt.log"
		mkdir -p -- "${qbt_install_dir}/logs" "${qbt_install_dir}/completed" "${qbt_install_dir}/boost" "${PKG_CONFIG_PATH}" "${wdir}/include/libtorrent"
		make_mock_cmd "${mbin}" "cmake" "${mlog}" 0
		make_mock_cmd "${mbin}" "dot" "${mlog}" 0
		make_mock_cmd "${mbin}" "strings" "${mlog}" 0 "printf 'libtorrent/1.2.20.0\n'"
		make_mock_cmd "${qbt_install_dir}/boost" "b2" "${mlog}" 0
		PATH="${mbin}:${PATH}"
		app_name="libtorrent"
		app_version[libtorrent]="1.2.20"
		qbt_cmake_build_type="Release"
		qbt_cmake_debug="OFF"
		qbt_standard="20"
		multi_libtorrent=()
		printf '#define LIBTORRENT_VERSION "1.2.20.0"\n' > "${wdir}/include/libtorrent/version.hpp"

		: > "${mlog}"
		qbt_build_tool="cmake"
		(cd "${wdir}" && _libtorrent > /dev/null)
		m_rc=$?
		assert_not_contains "_libtorrent cmake omits Iconv_LIBRARY when libiconv.a absent" "${m_rc}" "$(< "${mlog}")" "Iconv_LIBRARY"
		assert_contains "_libtorrent cmake sets Boost_NO_BOOST_CMAKE and BUILD_SHARED_LIBS=OFF" "${m_rc}" "$(< "${mlog}")" "-D Boost_NO_BOOST_CMAKE=TRUE -D BUILD_SHARED_LIBS=OFF -D deprecated-functions=OFF"

		: > "${lib_dir}/libiconv.a"
		: > "${mlog}"
		(cd "${wdir}" && _libtorrent > /dev/null)
		assert_contains "_libtorrent cmake passes Iconv_LIBRARY when libiconv.a exists" "$?" "$(< "${mlog}")" "-D Iconv_LIBRARY=${lib_dir}/libiconv.a"

		: > "${mlog}"
		qbt_build_tool="qmake"
		qbt_cross_name="armv7"
		bitness="32"
		qbt_libtorrent_debug="debug-symbols=on"
		(cd "${wdir}" && _libtorrent > /dev/null)
		m_rc=$?
		log_txt="$(< "${mlog}")"
		assert_contains "_libtorrent b2 1.2 passes iconv=on and address-model=32" "${m_rc}" "${log_txt}" "iconv=on address-model=32 debug-symbols=on"
		pc_txt="$(< "${PKG_CONFIG_PATH}/libtorrent-rasterbar.pc")"
		assert_contains "_libtorrent b2 1.2 pkg-config includes -l:libiconv.a and -l:libatomic.a" "${m_rc}" "${pc_txt}" "-l:libtorrent-rasterbar.a -l:libatomic.a -l:libiconv.a"
		assert_contains "_libtorrent b2 1.2 pkg-config sets TORRENT_USE_ICONV=1" "${m_rc}" "${pc_txt}" "-DTORRENT_USE_ICONV=1"

		printf 'constexpr char const* version_str = "2.0.11.0";\n' > "${wdir}/include/libtorrent/version.hpp"
		make_mock_cmd "${mbin}" "strings" "${mlog}" 0 ""
		: > "${mlog}"
		qbt_cross_name="aarch64"
		bitness="64"
		qbt_libtorrent_debug=""
		(cd "${wdir}" && _libtorrent > /dev/null)
		m_rc=$?
		assert_not_contains "_libtorrent b2 2.0 omits iconv=on" "${m_rc}" "$(< "${mlog}")" "iconv=on"
		pc2_txt="$(< "${PKG_CONFIG_PATH}/libtorrent-rasterbar.pc")"
		assert_contains "_libtorrent b2 2.0 pkg-config falls back to version.hpp Version" "${m_rc}" "${pc2_txt}" "Version: 2.0.11.0"
		assert_contains "_libtorrent b2 2.0 pkg-config includes -l:libtry_signal.a" "${m_rc}" "${pc2_txt}" "-l:libtry_signal.a"
		assert_not_contains "_libtorrent b2 2.0 aarch64 omits -l:libatomic.a" "${m_rc}" "${pc2_txt}" "libatomic"
		save_counts
	)
	load_counts

	# 16h. _double_conversion, _qtbase_host_deps, _qtbase (cmake Qt6, qmake Qt5 cross + idempotency, invalid combo), _qttools_host_deps, _qttools
	(
		load_lib "ubuntu" "resolute" "26.04" "amd64"
		qbt_install_dir="${test_root}/m_qt"
		qbt_host_deps_path="${qbt_install_dir}/host_deps"
		include_dir="${qbt_install_dir}/include"
		lib_dir="${qbt_install_dir}/lib"
		wdir="${test_root}/m_qt_src"
		mbin="${test_root}/m_qt_bin"
		mlog="${test_root}/m_qt.log"
		mkdir -p -- "${qbt_install_dir}/logs" "${qbt_install_dir}/completed" "${qbt_install_dir}/bin" "${wdir}/mkspecs/linux-g++-32" "${wdir}/mkspecs/linux-g++" "${wdir}/mkspecs/common" "${wdir}/src/corelib/global"
		make_mock_cmd "${mbin}" "cmake" "${mlog}" 0
		make_mock_cmd "${mbin}" "make" "${mlog}" 0
		make_mock_cmd "${mbin}" "dot" "${mlog}" 0
		make_mock_cmd "${wdir}" "configure" "${mlog}" 0
		make_mock_cmd "${qbt_install_dir}/bin" "qmake" "${mlog}" 0
		PATH="${mbin}:${PATH}"
		qbt_cmake_build_type="Release"
		qbt_cmake_debug="OFF"
		qbt_standard="20"

		app_name="double_conversion"
		app_version[double_conversion]="3.3.1"
		qbt_build_tool="cmake"
		qbt_qt_version="6"
		multi_double_conversion=()
		: > "${mlog}"
		_double_conversion > /dev/null
		assert_contains "_double_conversion cmake sets BUILD_SHARED_LIBS=OFF" "$?" "$(< "${mlog}")" "-D CMAKE_INSTALL_LIBDIR=lib -D BUILD_SHARED_LIBS=OFF"

		: > "${mlog}"
		qbt_build_tool="qmake"
		_double_conversion > /dev/null
		assert_pass_eq "_double_conversion is no-op for qmake" "$?" "" "$(< "${mlog}")"

		qbt_build_tool="cmake"
		qbt_qt_version="6"
		app_name="qtbase_host_deps"
		: > "${mlog}"
		_qtbase_host_deps > /dev/null
		assert_contains "_qtbase_host_deps installs to qbt_host_deps_path" "$?" "$(< "${mlog}")" "-D CMAKE_INSTALL_PREFIX=${qbt_host_deps_path}"

		app_name="qtbase"
		app_version[qtbase]="6.8.2"
		multi_qtbase=("-D QT_HOST_PATH=${qbt_host_deps_path}")
		: > "${mlog}"
		_qtbase > /dev/null
		assert_contains "_qtbase cmake Qt6 enables static & openssl_linked & system_zlib" "$?" "$(< "${mlog}")" "-D QT_FEATURE_static=on -D QT_FEATURE_shared=off -D QT_FEATURE_gui=off -D QT_FEATURE_openssl_linked=on -D QT_FEATURE_dbus=off -D QT_FEATURE_system_zlib=on"

		printf 'load(qt_config)\n' > "${wdir}/mkspecs/linux-g++/qmake.conf"
		printf '#  include <utility>\n' > "${wdir}/src/corelib/global/qglobal.h"
		: > "${wdir}/mkspecs/common/linux.conf"
		qbt_build_tool="qmake"
		qbt_qt_version="5.15"
		qbt_cross_name="x86"
		qbt_cross_host="i686-linux-gnu"
		qbt_cross_tool_dir="/usr/bin"
		qbt_cross_qtbase="linux-g++-32"
		bitness="32"
		qbt_skip_icu="no"
		qbt_strip_qmake="strip"
		AR="/usr/bin/i686-linux-gnu-ar"
		NM="/usr/bin/i686-linux-gnu-nm"
		CFLAGS="-O3" CXXFLAGS="-O3" LDFLAGS="-static"
		multi_qtbase=("-xplatform" "linux-g++-32")
		: > "${mlog}"
		(cd "${wdir}" && _qtbase > /dev/null)
		m_rc=$?
		assert_contains "_qtbase qmake x86 writes -m32 into qmake.conf" "${m_rc}" "$(< "${wdir}/mkspecs/linux-g++-32/qmake.conf")" "QMAKE_CFLAGS            = -m32"
		assert_contains "_qtbase qmake injects -static --static in linux-g++/qmake.conf" "${m_rc}" "$(< "${wdir}/mkspecs/linux-g++/qmake.conf")" "QMAKE_LFLAGS = -static --static"
		assert_contains "_qtbase qmake patches #  include <limits> into qglobal.h" "${m_rc}" "$(< "${wdir}/src/corelib/global/qglobal.h")" "#  include <limits>"
		assert_contains "_qtbase qmake passes -icu -no-iconv when qbt_skip_icu=no" "${m_rc}" "$(< "${mlog}")" "-icu -no-iconv"

		# Re-run _qtbase on same tree (-n mode): patches must be idempotent (count == 1)
		(cd "${wdir}" && _qtbase > /dev/null)
		m_rc2=$?
		assert_pass_eq "_qtbase qglobal.h limits patch is idempotent" "${m_rc2}" "1" "$(grep -c '#  include <limits>' "${wdir}/src/corelib/global/qglobal.h")"
		assert_pass_eq "_qtbase linux-g++/qmake.conf static patch is idempotent" "${m_rc2}" "1" "$(grep -c 'QMAKE_LFLAGS = -static --static' "${wdir}/mkspecs/linux-g++/qmake.conf")"

		(
			qbt_build_tool="qmake"
			qbt_qt_version="6"
			_qtbase > /dev/null 2>&1
		)
		assert_exit "_qtbase exits 1 on invalid qmake + Qt 6 combo" 1 "$?"

		qbt_build_tool="cmake"
		qbt_qt_version="6"
		app_name="qttools_host_deps"
		: > "${mlog}"
		_qttools_host_deps > /dev/null
		assert_contains "_qttools_host_deps installs to qbt_host_deps_path" "$?" "$(< "${mlog}")" "-D CMAKE_PREFIX_PATH=${qbt_host_deps_path}"

		app_name="qttools"
		app_version[qttools]="6.8.2"
		multi_qttools=()
		: > "${mlog}"
		_qttools > /dev/null
		assert_contains "_qttools cmake Qt6 installs to qbt_install_dir" "$?" "$(< "${mlog}")" "-D CMAKE_INSTALL_PREFIX=${qbt_install_dir}"

		qbt_build_tool="qmake"
		qbt_qt_version="5.15"
		qbt_crt_dir="-B${lib_dir}"
		: > "${mlog}"
		_qttools > /dev/null
		assert_contains "_qttools qmake Qt5 passes qbt_crt_dir in QMAKE_LFLAGS" "$?" "$(< "${mlog}")" "QMAKE_LFLAGS=-B${lib_dir} -static"

		(
			qbt_build_tool="qmake"
			qbt_qt_version="6"
			_qttools > /dev/null 2>&1
		)
		assert_exit "_qttools exits 1 on invalid qmake + Qt 6 combo" 1 "$?"
		save_counts
	)
	load_counts

	# 16i. _qbittorrent (cmake Alpine STACKTRACE=OFF vs Ubuntu STACKTRACE=ON, Iconv_LIBRARY, binary copy, missing binary error, qmake mode)
	(
		load_lib "alpine" "alpine" "3.21" "x86_64"
		qbt_install_dir="${test_root}/m_qbt"
		lib_dir="${qbt_install_dir}/lib"
		wdir="${test_root}/m_qbt_src"
		mbin="${test_root}/m_qbt_bin"
		mlog="${test_root}/m_qbt.log"
		mkdir -p -- "${qbt_install_dir}/logs" "${qbt_install_dir}/completed" "${qbt_install_dir}/bin" "${lib_dir}" "${wdir}"
		make_mock_cmd "${mbin}" "cmake" "${mlog}" 0 "[[ \${1} == '--install' ]] && printf 'BIN\n' > \"${qbt_install_dir}/bin/qbittorrent-nox\""
		make_mock_cmd "${mbin}" "make" "${mlog}" 0 "[[ \${1} == 'install' ]] && printf 'BIN\n' > \"${qbt_install_dir}/bin/qbittorrent-nox\""
		make_mock_cmd "${mbin}" "dot" "${mlog}" 0
		make_mock_cmd "${wdir}" "bootstrap.sh" "${mlog}" 0
		make_mock_cmd "${wdir}" "configure" "${mlog}" 0
		PATH="${mbin}:${PATH}"
		app_name="qbittorrent"
		app_version[qbittorrent]="5.1.0"
		qbt_build_tool="cmake"
		qbt_cmake_build_type="Release"
		qbt_cmake_debug="OFF"
		qbt_use_qt6="ON"
		multi_qbittorrent=()

		: > "${mlog}"
		_qbittorrent > /dev/null
		assert_contains "_qbittorrent Alpine cmake sets STACKTRACE=OFF and GUI=OFF" "$?" "$(< "${mlog}")" "-D QT6=ON -D STACKTRACE=OFF"
		assert_file_exists "_qbittorrent copies binary to completed/qbittorrent-nox" "${qbt_install_dir}/completed/qbittorrent-nox"

		os_id="ubuntu"
		: > "${lib_dir}/libiconv.a"
		: > "${mlog}"
		_qbittorrent > /dev/null
		m_rc=$?
		assert_contains "_qbittorrent Ubuntu cmake sets STACKTRACE=ON" "${m_rc}" "$(< "${mlog}")" "-D STACKTRACE=ON"
		assert_contains "_qbittorrent cmake passes Iconv_LIBRARY when libiconv.a exists" "${m_rc}" "$(< "${mlog}")" "-D Iconv_LIBRARY=${lib_dir}/libiconv.a"

		qbt_build_tool="qmake"
		qbt_qbittorrent_debug="--enable-debug"
		: > "${mlog}"
		(cd "${wdir}" && _qbittorrent > /dev/null)
		m_rc=$?
		log_txt="$(< "${mlog}")"
		assert_contains "_qbittorrent qmake runs bootstrap.sh" "${m_rc}" "${log_txt}" "bootstrap.sh"
		assert_contains "_qbittorrent qmake passes --enable-debug --disable-gui" "${m_rc}" "${log_txt}" "--enable-debug --disable-gui"

		rm -f -- "${qbt_install_dir}/bin/qbittorrent-nox"
		make_mock_cmd "${mbin}" "cmake" "${mlog}" 0
		qbt_build_tool="cmake"
		(_qbittorrent > /dev/null 2>&1)
		assert_exit "_qbittorrent exits 1 when bin/qbittorrent-nox missing after install" 1 "$?"
		save_counts
	)
	load_counts

	save_counts
)
load_counts

printf '\n=== 17. End-to-End CLI Tests (OS Matrix, All Help Flags, Option Loops 1 & 2, Env & Main Loop) ===\n'
(
	# 17a. Supported vs unsupported OS matrix (single invocation asserting exit status and output)
	for bad_os in "ubuntu:noble:24.04" "debian:bookworm:12" "alpine:alpine:3.17" "fedora:fedora:41"; do
		IFS=':' read -r oid ocn over <<< "${bad_os}"
		cdir="${test_root}/cli_os_${oid}_${over}"
		make_cli_copy "${cdir}" "${oid}" "${ocn}" "${over}" "no"
		out="$("${cdir}/qbt-nox-static.bash" -h 2>&1)"
		assert_fail_contains "unsupported OS ${oid}/${ocn}/${over} exits 1 with message" "$?" "${out}" "This is not a supported OS"
	done

	for good_os in "debian:trixie:13" "ubuntu:resolute:26.04" "alpine:alpine:3.18" "alpine:alpine:3.21"; do
		IFS=':' read -r oid ocn over <<< "${good_os}"
		cdir="${test_root}/cli_good_${oid}_${over}"
		make_cli_copy "${cdir}" "${oid}" "${ocn}" "${over}" "yes"
		out="$("${cdir}/qbt-nox-static.bash" -h)"
		assert_contains "supported OS ${oid}/${ocn}/${over} passes OS check and -h exits 0" "$?" "${out}" "Here are a list of available options"
	done

	# 17b. Option Loop 1 tests (no network stubs needed)
	cli_dir="${test_root}/cli_live"
	make_cli_copy "${cli_dir}" "ubuntu" "resolute" "26.04" "no"

	# ctest non-TTY exits 1
	out="$("${cli_dir}/qbt-nox-static.bash" ctest < /dev/null 2>&1)"
	assert_fail_contains "ctest exits 1 and reports no color support when stdout is not a TTY" "$?" "${out}" "does not support color"

	# -bs-e creates clean .qbt_env in script_parent_path with zero ANSI codes and valid bash syntax, even when multi-line qbt_* var is exported
	(
		mkdir -p -- "${test_root}/other_cwd"
		cd "${test_root}/other_cwd" || exit 1
		qbt_patches_url=$'line1\nINJECTED_LINE' "${cli_dir}/qbt-nox-static.bash" -bs-e > /dev/null
	)
	bse_rc=$?
	assert_exit "-bs-e exits 0" 0 "${bse_rc}"
	assert_file_exists "-bs-e writes .qbt_env to script_parent_path" "${cli_dir}/.qbt_env"
	assert_file_missing "-bs-e does not write .qbt_env to cwd" "${test_root}/other_cwd/.qbt_env"
	assert_not_contains "-bs-e strips all ANSI escape sequences" "${bse_rc}" "$(< "${cli_dir}/.qbt_env")" $'\e'
	assert_not_contains "-bs-e immune to multi-line env var injection" "${bse_rc}" "$(< "${cli_dir}/.qbt_env")" "INJECTED_LINE"
	bash -n "${cli_dir}/.qbt_env"
	assert_exit "-bs-e produces syntactically valid bash file" 0 "$?"
	rm -f -- "${cli_dir}/.qbt_env"

	# Symlinked .qbt_env refused on startup, on -bs-e, and directly via _write_qbt_env_template without clobbering target
	printf 'DO_NOT_TOUCH\n' > "${test_root}/sym_env_target"
	ln -s -- "${test_root}/sym_env_target" "${cli_dir}/.qbt_env"
	sym_start_out="$("${cli_dir}/qbt-nox-static.bash" -h 2>&1)"
	assert_fail_contains "startup refuses symlinked .qbt_env" "$?" "${sym_start_out}" "Refusing to source unsafe .qbt_env"
	sym_bse_out="$("${cli_dir}/qbt-nox-static.bash" -bs-e 2>&1)"
	assert_fail_contains "-bs-e refuses symlinked .qbt_env" "$?" "${sym_bse_out}" "Refusing to source unsafe .qbt_env"
	sym_helper_out="$(
		load_lib
		script_parent_path="${cli_dir}"
		_write_qbt_env_template "empty" 2>&1
	)"
	assert_fail_contains "_write_qbt_env_template refuses symlinked .qbt_env" "$?" "${sym_helper_out}" "Refusing to overwrite unsafe .qbt_env"
	assert_eq "symlinked .qbt_env target left intact" "DO_NOT_TOUCH" "$(< "${test_root}/sym_env_target")"
	rm -f -- "${cli_dir}/.qbt_env"

	# -cd <dir> rm refuses unsafe paths including regular files, trailing slashes, /., symlinks to protected dirs, and ancestors
	safe_home_parent="${test_root}/cli_home_parent"
	safe_home="${safe_home_parent}/cli_home"
	mkdir -p -- "${safe_home}/legit_cache" "${safe_home}/cache..v2" "${safe_home}/sub_pwd"
	printf 'regular\n' > "${safe_home}/not_a_dir.txt"
	ln -s -- "${safe_home}" "${test_root}/sym_to_home"
	for unsafe_path in "/" "///" "." "./" ".." "${safe_home}" "${safe_home}//" "${safe_home}/." "${cli_dir}" "${cli_dir}/." "${safe_home_parent}" "${test_root}" "${test_root}/sym_to_home" "${safe_home}/not_a_dir.txt"; do
		(cd "${safe_home}/sub_pwd" && HOME="${safe_home}" "${cli_dir}/qbt-nox-static.bash" -cd "${unsafe_path}" rm > /dev/null 2>&1)
		assert_exit "-cd '${unsafe_path}' rm refused with exit 1" 1 "$?"
	done
	assert_dir_exists "unsafe -cd rm left HOME parent intact" "${safe_home_parent}"
	assert_dir_exists "unsafe -cd rm left HOME intact" "${safe_home}"
	assert_dir_exists "unsafe -cd rm left script dir intact" "${cli_dir}"
	assert_file_exists "unsafe -cd rm left regular file intact" "${safe_home}/not_a_dir.txt"

	HOME="${safe_home}" "${cli_dir}/qbt-nox-static.bash" -cd "${safe_home}/legit_cache" rm > /dev/null
	assert_exit "-cd safe_dir rm exits 0" 0 "$?"
	assert_dir_missing "-cd safe_dir rm removed target cache directory" "${safe_home}/legit_cache"

	HOME="${safe_home}" "${cli_dir}/qbt-nox-static.bash" -cd "${safe_home}/cache..v2" rm > /dev/null
	assert_exit "-cd cache..v2 rm allows double-dot directory name" 0 "$?"
	assert_dir_missing "-cd cache..v2 rm removed cache..v2" "${safe_home}/cache..v2"

	# Value-taking option-loop-1 flags reject missing or -* values
	for loop1_flag in -b --build-directory -cd --cache-directory -p --proxy; do
		"${cli_dir}/qbt-nox-static.bash" "${loop1_flag}" -d > /dev/null 2>&1
		assert_exit "${loop1_flag} rejects leading-dash value" 1 "$?"
		"${cli_dir}/qbt-nox-static.bash" "${loop1_flag}" > /dev/null 2>&1
		assert_exit "${loop1_flag} rejects missing value" 1 "$?"
	done
	"${cli_dir}/qbt-nox-static.bash" -ma bogusarch > /dev/null 2>&1
	assert_exit "-ma rejects invalid architecture" 1 "$?"
	"${cli_dir}/qbt-nox-static.bash" --multi-arch > /dev/null 2>&1
	assert_exit "--multi-arch rejects missing architecture" 1 "$?"

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
	mkdir -p -- "${inst_cli_build}/completed"
	HOME="${safe_home}" "${cli_dir}/qbt-nox-static.bash" -b "${inst_cli_build}" install > /dev/null 2>&1
	assert_exit "offline install exits 1 when binary missing" 1 "$?"
	printf '#!/bin/sh\nexit 0\n' > "${inst_cli_build}/completed/qbittorrent-nox"
	HOME="${safe_home}" "${cli_dir}/qbt-nox-static.bash" -b "${inst_cli_build}" install custom "${safe_home}/cli_bin" > /dev/null
	assert_exit "offline install custom exits 0 when binary exists" 0 "$?"
	assert_file_exists "offline install short-circuit installed executable" "${safe_home}/cli_bin/qbittorrent-nox"

	# 17c. Option Loop 2 — ALL help flags & aliases exit 0 and emit output
	cli_off="${test_root}/cli_offline"
	make_cli_copy "${cli_off}" "ubuntu" "resolute" "26.04" "yes"

	for hflag in \
		-h --help \
		-h-b --help-build-directory \
		-h-bs-e --help-bootstrap-env \
		-h-bs-ef --help-bootstrap-env-full \
		-h-bs-p --help-bootstrap-patches \
		-h-bs-r --help-bootstrap-release \
		-h-bs-c --help-bootstrap-cmake \
		-h-bs-ma --help-bootstrap-multi-arch \
		-h-bs-a --help-bootstrap-all \
		-h-bt --help-boost-tag \
		-h-c --help-cmake \
		-h-cd --help-cache-directory \
		-h-d --help-debug \
		-h-n --help-no-delete \
		-h-i --help-icu \
		-h-m --help-master \
		-h-ma --help-multiarch --help-multi-arch \
		-h-lm --help-libtorrent-master \
		-h-lt --help-libtorrent-tag \
		-h-o --help-optimise \
		-h-ot --help-openssl-tag \
		-h-p --help-proxy \
		-h-pr --help-patch-repo \
		-h-q --help-qmake \
		-h-qm --help-qbittorrent-master \
		-h-qt --help-qbittorrent-tag \
		-h-qtt --help-qt-tag \
		-h-s --help-strip \
		-h-si --help-static-ish --help-staticish \
		-h-sdu --help-script-debug-urls \
		-h-wf --help-workflow; do
		hout="$("${cli_off}/qbt-nox-static.bash" "${hflag}")"
		hrc=$?
		if [[ ${hrc} -eq 0 && -n ${hout} ]]; then
			pass "help flag ${hflag} exits 0 with output"
		else
			fail "help flag ${hflag}" "rc=${hrc}, len=${#hout}"
		fi
	done

	out_hp="$("${cli_off}/qbt-nox-static.bash" -p "http://proxy.invalid:8080" -h-p)"
	assert_contains "-p <url> -h-p shows curl proxy command" "$?" "${out_hp}" "--proxy-insecure -x http://proxy.invalid:8080"

	"${cli_off}/qbt-nox-static.bash" -bs-c > /dev/null
	assert_exit "-bs-c handled cleanly (exits 0)" 0 "$?"

	out_zero="$("${cli_off}/qbt-nox-static.bash")"
	assert_contains "zero positional args exits 0 and lists supported modules" "$?" "${out_zero}" "Below is a list of supported modules"

	out_sdu="$("${cli_off}/qbt-nox-static.bash" -sdu)"
	assert_contains "-sdu exits 0 and prints github_tag debug dump" "$?" "${out_sdu}" "github_tag"

	"${cli_off}/qbt-nox-static.bash" --nonexistent-flag > /dev/null 2>&1
	assert_exit "unsupported flag exits 1" 1 "$?"

	for flag in -ot --openssl-tag -bt --boost-tag -lt --libtorrent-tag -pr --patch-repo -qt --qbittorrent-tag -qtt --qt-tag; do
		"${cli_off}/qbt-nox-static.bash" "${flag}" -h > /dev/null 2>&1
		assert_exit "${flag} rejects leading-dash argument" 1 "$?"
		"${cli_off}/qbt-nox-static.bash" "${flag}" > /dev/null 2>&1
		assert_exit "${flag} rejects missing argument" 1 "$?"
	done

	"${cli_off}/qbt-nox-static.bash" -pr "owner/repo/extra" > /dev/null 2>&1
	assert_exit "-pr rejects malformed repo path" 1 "$?"

	"${cli_off}/qbt-nox-static.bash" -ot lts > /dev/null 2>&1
	assert_exit "-ot lts fails via error_tag when lookup returns empty" 1 "$?"

	# Invalid tags in Option Loop 2 skip archive HEAD probes, preserve version vars, AND abort before -bs-p creates error_tag dirs!
	err_probe_cli="${test_root}/cli_err_probe"
	err_probe_log="${test_root}/cli_err_probe.log"
	: > "${err_probe_log}"
	make_cli_copy "${err_probe_cli}" "ubuntu" "resolute" "26.04" "yes"
	sed -i "s|^\t_curl() { return 1; }|\t_curl() { printf '%s\\\\n' \"\$*\" >> \"${err_probe_log}\"; return 0; }; _git() { printf 'error_tag\\\\n'; }|" "${err_probe_cli}/qbt-nox-static.bash"
	err_bs_dir="${test_root}/cli_err_bs_dir"
	"${err_probe_cli}/qbt-nox-static.bash" -b "${err_bs_dir}" -ot bad -bt bad -lt bad -qt bad -qtt bad -bs-p > /dev/null 2>&1
	assert_exit "invalid tags on -ot/-bt/-lt/-qt/-qtt -bs-p exit 1 via _error_tag" 1 "$?"
	assert_eq "invalid tags skip all _curl archive HEAD probes" "" "$(< "${err_probe_log}")"
	assert_dir_missing "invalid -lt bad -bs-p does NOT create patches/libtorrent/error_tag directory" "${err_bs_dir}/patches/libtorrent/error_tag"
	out_err_hlm="$("${err_probe_cli}/qbt-nox-static.bash" -lt bad -h-lm 2> /dev/null)"
	err_hlm_rc=$?
	assert_not_contains "invalid -lt does not clobber qbt_libtorrent_version with error_tag" "${err_hlm_rc}" "${out_err_hlm}" "error_tag"
	assert_contains "-lt bad -h-lm still renders RC_2_1 help" "${err_hlm_rc}" "${out_err_hlm}" "RC_2_1"

	"${cli_off}/qbt-nox-static.bash" -bs-ma > /dev/null 2>&1
	assert_exit "-bs-ma rejects default arch" 1 "$?"

	# 17d. Option Loop 2 tag flags (-ot, -bt, -lt, -qt, -qtt, -m, -lm, -qm, -pr, non-numeric branches, long flags, env auto-injection)
	cli_tags="${test_root}/cli_tags"
	make_cli_copy "${cli_tags}" "ubuntu" "resolute" "26.04" "yes"
	awk '
		/^[[:space:]]*_curl\(\) \{ return 1; \}/ {
			print "\t_curl() { return 0; }"
			print "\t_git() { if [[ ${2} == \"-t\" ]]; then printf \"%s\\n\" \"${3}\"; else return 0; fi; }"
			next
		}
		/^[[:space:]]*_git_git\(\) \{ return 1; \}/ {
			print "\t_git_git() { printf \"aaa\\trefs/tags/openssl-3.5.12\\n\"; }"
			next
		}
		{ print }
	' "${cli_tags}/qbt-nox-static.bash" > "${cli_tags}/qbt-nox-static.bash.tmp"
	mv -f -- "${cli_tags}/qbt-nox-static.bash.tmp" "${cli_tags}/qbt-nox-static.bash"
	chmod +x -- "${cli_tags}/qbt-nox-static.bash"

	out_tags="$("${cli_tags}/qbt-nox-static.bash" -ot lts -bt boost-1.89.0 -lt RC_1_2 -qt master -pr validowner/validrepo -n -d -i -wf -sdu)"
	tags_rc=$?
	assert_contains "-ot lts resolves latest 3.5.x tag" "${tags_rc}" "${out_tags}" "openssl-3.5.12"
	assert_contains "-bt sets boost-1.89.0" "${tags_rc}" "${out_tags}" "boost-1.89.0"
	assert_contains "-lt RC_1_2 sets RC_1_2" "${tags_rc}" "${out_tags}" "RC_1_2"
	assert_contains "-qt master sets refs/heads/master.tar.gz" "${tags_rc}" "${out_tags}" "refs/heads/master.tar.gz"

	# Non-numeric branches on -qtt dev and -lt master preserve major/minor version selectors
	out_branch_tags="$("${cli_tags}/qbt-nox-static.bash" -qtt dev -lt master)"
	bt_rc=$?
	assert_contains "-qtt dev preserves qbt_qt_version=6" "${bt_rc}" "${out_branch_tags}" 'qbt_qt_version="'$'\e''[92m6'
	assert_contains "-lt master preserves qbt_libtorrent_version=2.1" "${bt_rc}" "${out_branch_tags}" 'qbt_libtorrent_version="'$'\e''[92m2.1'

	out_long="$("${cli_tags}/qbt-nox-static.bash" --cmake --debug --icu --no-delete --strip --workflow --optimise --static-ish --libtorrent-tag libtorrent_1_2_20 --qbittorrent-tag release-5.1.0 --patch-repo "owner1/repo1 owner2/repo2" --script-debug-urls)"
	long_rc=$?
	assert_contains "--libtorrent-tag libtorrent_1_2_20 normalizes version to 1.2.20" "${long_rc}" "${out_long}" "libtorrent-rasterbar-1.2.20.tar.gz"
	assert_contains "--qbittorrent-tag release-5.1.0 sets refs/tags URL" "${long_rc}" "${out_long}" "refs/tags/release-5.1.0.tar.gz"

	# -pr rejects malformed or traversal repo even when _curl returns 0
	"${cli_tags}/qbt-nox-static.bash" -pr "owner1/repo1 bad/repo/extra" -sdu > /dev/null 2>&1
	assert_exit "-pr rejects malformed second repo in space-separated list" 1 "$?"
	"${cli_tags}/qbt-nox-static.bash" -pr "userdocs/.." -sdu > /dev/null 2>&1
	assert_exit "-pr rejects owner/.. traversal repo even when HTTP HEAD succeeds" 1 "$?"
	"${cli_tags}/qbt-nox-static.bash" -pr "../.." -sdu > /dev/null 2>&1
	assert_exit "-pr rejects ../.. traversal repo" 1 "$?"

	out_ih="$("${cli_tags}/qbt-nox-static.bash" install -h)"
	assert_contains "install -h falls through to help instead of installing" "$?" "${out_ih}" "Here are a list of available options"

	"${cli_tags}/qbt-nox-static.bash" -b "${test_root}/cli_ma_bs" -ma aarch64 -bs-ma > /dev/null
	assert_exit "-ma aarch64 -bs-ma exits 0 on Ubuntu" 0 "$?"

	out_lt_us="$("${cli_tags}/qbt-nox-static.bash" -lt libtorrent-1_2_20 -sdu)"
	assert_contains "-lt libtorrent-1_2_20 normalizes app_version to 1.2.20" "$?" "${out_lt_us}" "libtorrent-rasterbar-1.2.20.tar.gz"

	out_lt12_mods="$("${cli_tags}/qbt-nox-static.bash" -lt v1.2.20)"
	assert_contains "-lt v1.2.20 includes iconv in supported modules" "$?" "${out_lt12_mods}" "iconv"
	out_lt20_mods="$("${cli_tags}/qbt-nox-static.bash" -lt v2.0.11)"
	assert_not_contains "-lt v2.0.11 removes iconv from supported modules" "$?" "${out_lt20_mods}" " iconv "

	out_m="$("${cli_tags}/qbt-nox-static.bash" --master -sdu)"
	m_rc=$?
	assert_contains "--master sets libtorrent RC_2_1" "${m_rc}" "${out_m}" "RC_2_1"
	assert_contains "--master sets qbittorrent master" "${m_rc}" "${out_m}" "refs/heads/master.tar.gz"

	out_lm="$("${cli_tags}/qbt-nox-static.bash" --libtorrent-master -sdu)"
	assert_contains "--libtorrent-master sets libtorrent RC_2_1" "$?" "${out_lm}" "RC_2_1"
	out_qm="$("${cli_tags}/qbt-nox-static.bash" --qbittorrent-master -sdu)"
	assert_contains "--qbittorrent-master sets qbittorrent master" "$?" "${out_qm}" "refs/heads/master.tar.gz"

	"${cli_tags}/qbt-nox-static.bash" -c -qtt v5.15.16-lts-lgpl -sdu > /dev/null 2>&1
	assert_exit "-c -qtt v5.15.16-lts-lgpl rejected as mismatched combo" 1 "$?"
	"${cli_tags}/qbt-nox-static.bash" -q -qtt v6.8.2 -sdu > /dev/null 2>&1
	assert_exit "-q -qtt v6.8.2 rejected as mismatched combo" 1 "$?"
	out_qtt6="$("${cli_tags}/qbt-nox-static.bash" -c -qtt v6.8.2 -sdu)"
	assert_contains "-c -qtt v6.8.2 exits 0 and sets official_releases URL" "$?" "${out_qtt6}" "official_releases/qt/6.8/6.8.2"

	out_env_inj="$(qbt_openssl_tag="openssl-3.5.8" qbt_boost_tag="boost-1.87.0" qbt_libtorrent_tag="v2.0.10" qbt_qbittorrent_tag="release-5.0.4" "${cli_tags}/qbt-nox-static.bash" -sdu)"
	ei_rc=$?
	assert_contains "env qbt_openssl_tag injected" "${ei_rc}" "${out_env_inj}" "openssl-3.5.8"
	assert_contains "env qbt_boost_tag injected" "${ei_rc}" "${out_env_inj}" "boost-1.87.0"
	assert_contains "env qbt_libtorrent_tag injected" "${ei_rc}" "${out_env_inj}" "v2.0.10"
	assert_contains "env qbt_qbittorrent_tag injected" "${ei_rc}" "${out_env_inj}" "release-5.0.4"

	# 17e. .qbt_env CRLF support, symlink protection on -bs-ef, & CLI precedence
	cli_off_qt5="${test_root}/cli_offline_qt5"
	make_cli_copy "${cli_off_qt5}" "ubuntu" "resolute" "26.04" "yes"
	sed -i 's|release-5.1.0|release-4.5.2|g; s|app_version\[qbittorrent\]="5.1.0"|app_version[qbittorrent]="4.5.2"|g' "${cli_off_qt5}/qbt-nox-static.bash"
	# Write CRLF .qbt_env to verify CR stripping on startup
	printf 'qbt_qt_version="6"\r\nqbt_build_tool="cmake"\r\nqbt_zlib_type="zlib-ng"\r\n' > "${cli_off_qt5}/.qbt_env"
	"${cli_off_qt5}/qbt-nox-static.bash" -q -bs-ef > /dev/null
	bsef_rc=$?
	assert_contains "CRLF .qbt_env sourced without CR and -q overrides to qmake" "${bsef_rc}" "$(< "${cli_off_qt5}/.qbt_env")" 'qbt_build_tool="qmake"'
	assert_contains "-q overrides .qbt_env qt6 to qt5 in -bs-ef" "${bsef_rc}" "$(< "${cli_off_qt5}/.qbt_env")" 'qbt_qt_version="5"'
	assert_contains "CRLF .qbt_env preserved qbt_zlib_type=zlib-ng without CR" "${bsef_rc}" "$(< "${cli_off_qt5}/.qbt_env")" 'qbt_zlib_type="zlib-ng"'
	rm -f -- "${cli_off_qt5}/.qbt_env"

	# -bs-ef refuses symlinked .qbt_env if created mid-run or present
	printf 'qbt_qt_version="6"\n' > "${cli_off}/.qbt_env"
	"${cli_off}/qbt-nox-static.bash" -q -bs-ef > /dev/null 2>&1
	assert_exit "-q overrides .qbt_env qt6 and rejects incompatible qbt 5.1.0" 1 "$?"
	rm -f -- "${cli_off}/.qbt_env"

	# 17f. Invalid module, -- end-of-options, -bs-p/-bs-r/-bs-a, main loop boost guard & -cd bs skip
	"${cli_off}/qbt-nox-static.bash" not_a_module > /dev/null 2>&1
	assert_exit "invalid module exits 1" 1 "$?"
	"${cli_off}/qbt-nox-static.bash" -- -not-a-flag > /dev/null 2>&1
	assert_exit "-- passes positional arg to module validation and exits 1" 1 "$?"

	bs_build="${test_root}/cli_bs_build"
	"${cli_off}/qbt-nox-static.bash" -b "${bs_build}" -bs-p -bs-r > /dev/null
	assert_exit "-b <dir> -bs-p -bs-r exits 0" 0 "$?"
	assert_dir_exists "-bs-p creates patch dir in custom -b dir" "${bs_build}/patches/qbittorrent/5.1.0/source"
	assert_file_exists "-bs-r creates tag.md in custom -b dir" "${bs_build}/release_info/tag.md"

	bsa_build="${test_root}/cli_bsa_build"
	"${cli_off}/qbt-nox-static.bash" -b "${bsa_build}" -bs-a > /dev/null
	assert_exit "-b <dir> -bs-a exits 0" 0 "$?"
	assert_dir_exists "-bs-a creates patches in custom -b dir" "${bsa_build}/patches/zlib/1.3.2/source"
	assert_file_exists "-bs-a creates release_info in custom -b dir" "${bsa_build}/release_info/title.md"

	boost_guard_build="${test_root}/cli_boost_guard"
	out_bg="$("${cli_off}/qbt-nox-static.bash" -b "${boost_guard_build}" libtorrent 2>&1)"
	assert_fail_contains "main loop libtorrent without boost dir exits 1 with warning" "$?" "${out_bg}" "depends on the boost module"

	out_bg2="$("${cli_off}/qbt-nox-static.bash" -b "${boost_guard_build}" qbittorrent 2>&1)"
	assert_fail_contains "main loop qbittorrent without boost dir exits 1 with warning" "$?" "${out_bg2}" "depends on the boost module"

	cli_cd_bs="${test_root}/cli_cd_bs"
	make_cli_copy "${cli_cd_bs}" "ubuntu" "resolute" "26.04" "yes"
	awk '
		/^_download\(\) \{/ {
			print "_download() { mkdir -p -- \"${qbt_cache_dir}\"; : > \"${qbt_cache_dir}/${app_name}.cached\"; }"
			skip = 1; next
		}
		skip && /^\}$/ { skip = 0; next }
		!skip { print }
	' "${cli_cd_bs}/qbt-nox-static.bash" > "${cli_cd_bs}/qbt-nox-static.bash.tmp"
	mv -f -- "${cli_cd_bs}/qbt-nox-static.bash.tmp" "${cli_cd_bs}/qbt-nox-static.bash"
	chmod +x -- "${cli_cd_bs}/qbt-nox-static.bash"

	cd_bs_dir="${test_root}/cli_cd_bs_cache"
	"${cli_cd_bs}/qbt-nox-static.bash" -b "${test_root}/cli_cd_bs_build" -cd "${cd_bs_dir}" bs zlib libtorrent > /dev/null
	assert_exit "-cd <dir> bs runs download and skips module build & boost check" 0 "$?"
	assert_file_exists "-cd bs cached zlib" "${cd_bs_dir}/zlib.cached"
	assert_file_exists "-cd bs cached libtorrent" "${cd_bs_dir}/libtorrent.cached"

	save_counts
)
load_counts

printf '\n=== 18. Script Integrity, Sourcing Safety & Contract Regression Tests ===\n'
(
	# 18a. Syntax, line endings, security hygiene, and double-sourcing safety under bash -ec
	bash -n "${target_script}"
	assert_exit "qbt-nox-static.bash passes bash -n syntax check" 0 "$?"
	bash -n "${script_path}"
	assert_exit "tests/unit_tests.bash passes bash -n syntax check" 0 "$?"

	src_check_dir="${test_root}/src_safety_wd"
	mkdir -p -- "${src_check_dir}"
	src_out="$(
		cd "${src_check_dir}" || exit 1
		bash -ec '
			orig_pwd="${PWD}"
			IFS=":"
			export LC_ALL="C"
			source "$1"
			source "$1"
			[[ ${PWD} == "${orig_pwd}" ]] || { printf "PWD_MUTATED\n" >&2; exit 1; }
			[[ ${IFS} == ":" ]] || { printf "IFS_MUTATED\n" >&2; exit 1; }
			[[ ${LC_ALL} == "C" ]] || { printf "LC_ALL_MUTATED\n" >&2; exit 1; }
		' _ "${target_script}" 2>&1
	)"
	assert_pass_eq "double-sourcing under bash -ec succeeds with empty stderr and preserves PWD/IFS/LC_ALL" "$?" "" "${src_out}"

	if ! grep -q $'\r' "${target_script}" && ! grep -q $'\r' "${script_path}"; then
		pass "qbt-nox-static.bash and unit_tests.bash have LF-only line endings"
	else
		fail "line endings" "CR characters detected"
	fi

	if ! grep -Eq '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*a' "${target_script}"; then
		pass "qbt-nox-static.bash does not use global set -a"
	else
		fail "global set -a" "forbidden set -a detected in qbt-nox-static.bash"
	fi

	if ! grep -Eq '^[[:space:]]*readonly([[:space:]]|$)' "${target_script}"; then
		pass "qbt-nox-static.bash has no top-level bare readonly declarations"
	else
		fail "top-level readonly" "bare readonly found in qbt-nox-static.bash"
	fi

	if ! grep -Eq '^[[:space:]]*eval[[:space:]]' "${target_script}"; then
		pass "qbt-nox-static.bash contains no eval calls"
	else
		fail "eval check" "eval statement found in qbt-nox-static.bash"
	fi

	if ! grep -nE '(^|[;&|({[:space:]])echo([[:space:]]|$)' "${target_script}" | grep -qv '^[0-9]*:[[:space:]]*#'; then
		pass "qbt-nox-static.bash contains no standalone echo commands"
	else
		fail "echo check" "forbidden echo command found in qbt-nox-static.bash"
	fi

	# shellcheck disable=SC2016
	if ! grep -Fq '${color_end}${color_end}' "${target_script}"; then
		pass "qbt-nox-static.bash has no duplicate consecutive color_end tags"
	else
		fail "duplicate color_end" "found duplicate color_end sequence"
	fi

	# 18b. 100% parity between -h env help and _print_env
	help_env_vars="$(awk '/-h \| --help\)/,/-h-b \|/' "${target_script}" | grep -oE 'export qbt_[a-zA-Z0-9_]+=' | sed 's/^export //; s/=$//' | sort -u)"
	print_env_vars="$(awk '/^_print_env\(\) \{/,/^\}/' "${target_script}" | grep -oE 'qbt_[a-zA-Z0-9_]+=' | sed 's/=$//' | sort -u)"
	assert_eq "-h env documentation matches _print_env variables 1:1" "${print_env_vars}" "${help_env_vars}"

	# 18c. Every flag advertised in -h has a matching case handler in Option Loop 1 or Option Loop 2
	help_flags="$(awk '/-h \| --help\)/,/-h-b \|/' "${target_script}" | sed -E 's/\$\{[^}]+\}//g' | grep -oE '(^|[[:space:]])--?[a-z][a-z0-9-]*([[:space:]]|$)' | tr -d ' \t' | sort -u)"
	handled_flags="$(
		{
			awk '/^# This is first help section/,/^[[:space:]]*set -- "\$\{params1\[@\]\}"/' "${target_script}"
			awk '/^[[:space:]]*qbt_bs_env_full=false/,/^[[:space:]]*set -- "\$\{params2\[@\]\}"/' "${target_script}"
		} | grep -E $'^\t{2,3}[^#]*\\)$' | sed 's/)$//' | tr '|' '\n' | tr -d ' \t' | grep -E '^-' | sort -u
	)"
	missing_flag_handlers=""
	while IFS= read -r hf; do
		[[ -z ${hf} ]] && continue
		if ! grep -Fxq -- "${hf}" <<< "${handled_flags}"; then
			missing_flag_handlers+="${hf} "
		fi
	done <<< "${help_flags}"
	assert_eq "every flag advertised in -h has a case handler" "" "${missing_flag_handlers}"

	# 18d. Every module in qbt_modules_order (except all/install) has a defined _<module>() function
	# and every non-host_deps module has URL/tag/version/archive entries in _set_module_urls
	defined_funcs="$(grep -oE '^[a-zA-Z0-9_]+\(\)' "${target_script}" | sed 's/()$//' | sort -u)"
	ordered_mods="$(grep -oE 'qbt_modules_order\+?=\("[^"]+"\)' "${target_script}" | grep -v '^[[:space:]]*#' | sed -E 's/.*"([^"]+)".*/\1/')"
	urls_block="$(awk '/^_set_module_urls\(\) \{/,/^\}/' "${target_script}")"
	missing_mod_funcs=""
	missing_mod_urls=""
	while IFS= read -r mod_name; do
		[[ -z ${mod_name} || ${mod_name} == "all" || ${mod_name} == "install" ]] && continue
		if ! grep -Fxq -- "_${mod_name}" <<< "${defined_funcs}"; then
			missing_mod_funcs+="_${mod_name} "
		fi
		if [[ ${mod_name} != *_host_deps ]]; then
			for arr_name in github_url github_tag app_version qbt_workflow_archive_url source_default; do
				grep -Fq "${arr_name}[${mod_name}]=" <<< "${urls_block}" || missing_mod_urls+="${arr_name}[${mod_name}] "
			done
		fi
	done <<< "${ordered_mods}"
	assert_eq "every module in qbt_modules_order has a _<module>() function" "" "${missing_mod_funcs}"
	assert_eq "every module has full URL/tag/version/default declarations in _set_module_urls" "" "${missing_mod_urls}"

	# 18e. No raw curl/git invocations bypassing wrappers, no unquoted rm -rf
	raw_curl="$(grep -nE '^[[:space:]]*curl[[:space:]]' "${target_script}" || true)"
	raw_git="$(grep -nE '^[[:space:]]*git[[:space:]]' "${target_script}" || true)"
	unquoted_rm="$(grep -nE 'rm[[:space:]]+-rf[[:space:]]+[^"-]' "${target_script}" || true)"
	assert_eq "no raw curl invocations bypassing _curl wrapper" "" "${raw_curl}"
	assert_eq "no raw git invocations bypassing _git/_git_git wrappers" "" "${raw_git}"
	assert_eq "no unquoted rm -rf arguments" "" "${unquoted_rm}"

	# 18f. Every arch in multi_arch_options (except default) has both a _multi_arch case and a _release_info row
	ma_block="$(awk '/^_multi_arch\(\) \{/,/^\}/' "${target_script}")"
	ri_block="$(awk '/^_release_info\(\) \{/,/^\}/' "${target_script}")"
	defined_arches="$(grep -oE '^multi_arch_options\["[^"]+"\]=' "${target_script}" | sed -E 's/.*"([^"]+)".*/\1/')"
	missing_ma=""
	missing_ri=""
	while IFS= read -r arch_name; do
		[[ -z ${arch_name} || ${arch_name} == "default" ]] && continue
		grep -Fq $'\t\t\t\t'"${arch_name})" <<< "${ma_block}" || missing_ma+="${arch_name} "
		grep -Fq "== ${arch_name} ]]" <<< "${ri_block}" || missing_ri+="${arch_name} "
	done <<< "${defined_arches}"
	assert_eq "every multi_arch_options arch has a _multi_arch case" "" "${missing_ma}"
	assert_eq "every multi_arch_options arch has a _release_info tuning row" "" "${missing_ri}"

	# 18g. script_version follows semantic versioning X.Y.Z
	sv="$(grep -m1 '^script_version=' "${target_script}")"
	sv_rc=$?
	sv="${sv#*=\"}"
	sv="${sv%\"*}"
	assert_match "script_version is valid X.Y.Z semver" "${sv_rc}" "${sv}" '^[0-9]+\.[0-9]+\.[0-9]+$'

	save_counts
)
load_counts

printf '\n========================================\n'
printf 'Unit Test Summary: %d passed, %d failed\n' "${passed}" "${failed}"
printf '========================================\n'

if ((failed > 0)); then
	exit 1
fi
exit 0
