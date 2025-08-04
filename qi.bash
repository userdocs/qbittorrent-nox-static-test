#!/bin/bash
# Quick installer for qbittorrent-nox-static
# This script is focused on being a simple installer that verifies installation and binaries

# Error handling function to test commands and exit with helpful explanations
handle_error() {
	local exit_code="$1"
	local command="$2"
	local context="$3"

	if [[ $exit_code -ne 0 ]]; then
		print_failure "Command failed: $command"
		print_error "Context: $context"
		print_error "Exit code: $exit_code"
		print_error "This error occurred during the installation process."
		print_error "Please check your system configuration and try again."
		exit "$exit_code"
	fi
}

# Check supported distributions
check_supported_distro() {
	# Source os-release and check ID
	if [[ -f /etc/os-release ]]; then
		# shellcheck source=/etc/os-release
		source /etc/os-release
		# Support Alpine or Debian-based distributions
		if [[ ${ID:-} =~ ^(alpine|debian)$ ]] || [[ ${ID_LIKE:-} == *debian* ]]; then
			return 0 # Supported distribution
		else
			print_error "Unsupported distribution: ${ID:-unknown}. This installer only supports Alpine or Debian-based distributions"
			exit 1
		fi
	else
		print_error "Cannot determine distribution. /etc/os-release not found"
		print_error "This installer only supports Alpine or Debian-based distributions"
		exit 1
	fi
}

# Output functions for user feedback
# Handle [INFO] (blue) [WARNING] (yellow) [ERROR] (red) [SUCCESS] (Green) [FAILURE] (magenta)
print_output() {
	local type="$1"
	local message="$2"

	case "$type" in
		INFO)
			printf '%b[INFO]    %b %s\n' '\033[0;34m' '\033[0m' "$message"
			;;
		WARNING)
			printf '%b[WARNING] %b %s\n' '\033[1;33m' '\033[0m' "$message"
			;;
		ERROR)
			printf '%b[ERROR]   %b %s\n' '\033[0;31m' '\033[0m' "$message"
			;;
		SUCCESS)
			printf '%b[SUCCESS] %b %s\n' '\033[0;32m' '\033[0m' "$message"
			;;
		FAILURE)
			printf '%b[FAILURE] %b %s\n' '\033[0;35m' '\033[0m' "$message"
			;;
		*)
			printf '%s\n' "$message"
			;;
	esac
}

# Convenience wrappers for common output types
print_info() { print_output "INFO" "$1"; }
print_warning() { print_output "WARNING" "$1"; }
print_error() { print_output "ERROR" "$1"; }
print_success() { print_output "SUCCESS" "$1"; }
print_failure() { print_output "FAILURE" "$1"; }

# Detect architecture and map to binary name
detect_arch() {
	local arch_output=""

	# Try different architecture detection methods
	# Prioritize distribution-specific tools for better accuracy
	if command -v apk > /dev/null 2>&1; then
		# Alpine Linux
		arch_output="$(apk --print-arch 2> /dev/null)" || {
			print_error "Failed to detect architecture using apk"
			exit 1
		}
	elif command -v dpkg > /dev/null 2>&1; then
		# Debian-based systems
		arch_output="$(dpkg --print-architecture 2> /dev/null)" || {
			print_error "Failed to detect architecture using dpkg"
			exit 1
		}
	elif command -v arch > /dev/null 2>&1; then
		# Fallback to arch command
		arch_output="$(arch)" || {
			print_error "Failed to detect architecture using arch command"
			exit 1
		}
	else
		print_error "No architecture detection tool found (apk/dpkg/arch)"
		print_error "Please install the appropriate package manager or set FORCE_ARCH environment variable"
		exit 1
	fi

	case "$arch_output" in
		# x86_64 = amd64, x86_64
		x86_64 | amd64) printf '%s' "x86_64" ;;
		# x86 = x86, i386, i686
		x86 | i386 | i686) printf '%s' "x86" ;;
		# aarch64 = arm64, aarch64
		aarch64 | arm64) printf '%s' "aarch64" ;;
		# armv7 = armv7* (and armhf on Debian/Ubuntu)
		armv7*) printf '%s' "armv7" ;;
		# armhf = armhf (on Alpine = armv6), armv6*, armel
		armhf)
			# Alpine uses apk, Debian/Ubuntu use dpkg
			if command -v apk > /dev/null 2>&1; then
				printf '%s' "armhf" # Alpine: armhf stays as armhf (armv6 binary)
			else
				printf '%s' "armv7" # Debian/Ubuntu: armhf maps to armv7 binary
			fi
			;;
		armv6* | armel) printf '%s' "armhf" ;;
		# riscv64 = riscv64
		riscv64) printf '%s' "riscv64" ;;
		*)
			print_error "Unsupported architecture: $arch_output"
			print_error "Supported architectures: x86_64, x86, aarch64, armv7, armhf, riscv64"
			print_error "You can override with FORCE_ARCH environment variable"
			exit 1
			;;
	esac
}

# Check for wget or curl, default to curl if present
check_download_tools() {
	if command -v curl > /dev/null 2>&1; then
		printf '%s' "curl"
	elif command -v wget > /dev/null 2>&1; then
		printf '%s' "wget"
	else
		print_error "No download tool found. Please install curl or wget"
		print_error "On Alpine: apk add curl"
		print_error "On Debian/Ubuntu: apt-get install curl"
		exit 1
	fi
}

# Check if gh CLI is available
check_gh_cli() {
	if command -v gh > /dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

# Create download function based on architecture checks
create_download_url() {
	local arch="$1"
	local release_tag="$2"
	printf '%s' "https://github.com/userdocs/qbittorrent-nox-static/releases/download/${release_tag}/${arch}-qbittorrent-nox"
}

# Create SHA256 checksum of downloaded file
create_sha256() {
	local file_path="$1"

	if [[ ! -f $file_path ]]; then
		print_error "File not found for checksum: $file_path"
		return 1
	fi

	if command -v sha256sum > /dev/null 2>&1; then
		sha256sum "$file_path" | cut -d' ' -f1
	elif command -v shasum > /dev/null 2>&1; then
		shasum -a 256 "$file_path" | cut -d' ' -f1
	else
		print_warning "No SHA256 tool found (sha256sum/shasum) - skipping checksum"
		return 1
	fi
}

# Comprehensive SHA256 verification function
# Tries GitHub CLI first, then API, then shows local SHA as fallback
verify_binary_integrity() {
	local install_path="$1"
	local release_tag="$2"
	local arch="$3"
	local repo="userdocs/qbittorrent-nox-static"

	# Calculate local file SHA256
	local local_sha
	if ! local_sha=$(create_sha256 "$install_path"); then
		print_warning "Could not calculate local SHA256 - skipping verification"
		return 1
	fi

	print_info "SHA256: $local_sha"

	# Try GitHub CLI attestation verification first (most secure)
	if check_gh_cli; then
		print_info "Verifying with GitHub CLI attestations..."
		if gh attestation verify "$install_path" --repo "$repo" 2> /dev/null; then
			print_success "✓ GitHub CLI attestation verification passed"
			return 0
		else
			print_warning "⚠ GitHub CLI attestation verification failed or not available"
			print_info "Falling back to GitHub API verification..."
		fi
	else
		if [[ -n ${GITHUB_ACTIONS:-} ]]; then
			print_info "GitHub Actions detected but gh CLI not found"
			print_info "Note: GitHub CLI may need to be explicitly installed in your workflow"
			print_info "Note: GH_TOKEN environment variable is also required for attestation verification"
		else
			print_info "GitHub CLI not found - trying GitHub API verification..."
		fi
	fi

	# Try GitHub API verification as fallback
	local api_url="https://api.github.com/repos/${repo}/releases/tags/${release_tag}"
	local tool
	tool=$(check_download_tools)

	print_info "Verifying SHA256 against GitHub API..."

	# Fetch release assets from GitHub API
	local api_response
	case "$tool" in
		wget)
			api_response=$(wget -qO- "$api_url" 2> /dev/null) || {
				print_warning "Failed to fetch release information from GitHub API"
				print_info "Local SHA256 verification completed"
				return 1
			}
			;;
		curl)
			api_response=$(curl -sL "$api_url" 2> /dev/null) || {
				print_warning "Failed to fetch release information from GitHub API"
				print_info "Local SHA256 verification completed"
				return 1
			}
			;;
	esac

	if [[ -z $api_response ]]; then
		print_warning "Empty response from GitHub API"
		print_info "Local SHA256 verification completed"
		return 1
	fi

	# Extract SHA256 digests from API response
	local api_digests
	if command -v jq > /dev/null 2>&1; then
		# Use jq if available (preferred method) - extract just the hash value
		api_digests=$(printf '%s' "$api_response" | jq -r '.assets[].digest.sha256 // empty' 2> /dev/null | sed 's/^sha256://')
	else
		# Fall back to sed if jq is not available - extract just the hash value
		api_digests=$(printf '%s' "$api_response" | sed -rn 's|(.*)sha256:([^"]*)".*|\2|p' 2> /dev/null)
	fi

	if [[ -z $api_digests ]]; then
		print_warning "No SHA256 digests found in GitHub API response"
		print_info "This may be normal for older releases or if digests are not published"
		print_info "Local SHA256 verification completed"
		return 1
	fi

	# Check if local SHA256 matches any of the API digests
	local match_found=false
	while IFS= read -r api_digest; do
		if [[ -n $api_digest ]] && [[ $local_sha == "$api_digest" ]]; then
			match_found=true
			break
		fi
	done <<< "$api_digests"

	if [[ $match_found == "true" ]]; then
		print_success "✓ GitHub API SHA256 verification passed"
		return 0
	else
		print_warning "⚠ GitHub API SHA256 verification failed"
		print_warning "Local SHA256:  $local_sha"
		print_warning "API Digests:"
		while IFS= read -r api_digest; do
			if [[ -n $api_digest ]]; then
				print_warning "  $api_digest"
			fi
		done <<< "$api_digests"
		print_warning "This may indicate a corrupted download or outdated API data"
		print_info "Local SHA256 verification completed"
		return 1
	fi
}
# Get release tag from API
get_release_tag() {
	local api="https://github.com/userdocs/qbittorrent-nox-static/releases/latest/download/dependency-version.json"
	local ver="${LIBTORRENT_VERSION:-v2}"
	local tool
	tool=$(check_download_tools)

	# Fetch API response
	local response
	case "$tool" in
		wget)
			response=$(wget -qO- "$api" 2> /dev/null) || {
				handle_error $? "wget -qO- $api" "Failed to fetch release information from API"
			}
			;;
		curl)
			response=$(curl -sL "$api" 2> /dev/null) || {
				handle_error $? "curl -sL $api" "Failed to fetch release information from API"
			}
			;;
	esac

	if [[ -z $response ]]; then
		print_error "Failed to fetch release information - empty response"
		print_error "API endpoint: $api"
		exit 1
	fi

	# Parse release tag
	local qbt_ver libt_ver
	qbt_ver=$(printf '%s' "$response" | sed -rn 's|(.*)"qbittorrent": "(.*)",|\2|p')

	case "$ver" in
		v1)
			libt_ver=$(printf '%s' "$response" | sed -rn 's|(.*)"libtorrent_1_2": "(.*)",|\2|p')
			;;
		v2)
			libt_ver=$(printf '%s' "$response" | sed -rn 's|(.*)"libtorrent_2_0": "(.*)",|\2|p')
			;;
		*)
			print_error "Invalid LibTorrent version: $ver"
			print_error "Valid options: v1, v2"
			exit 1
			;;
	esac

	if [[ -z $qbt_ver ]] || [[ -z $libt_ver ]]; then
		print_error "Failed to parse version information from API response"
		print_error "qBittorrent version: ${qbt_ver:-not found}"
		print_error "LibTorrent version: ${libt_ver:-not found}"
		exit 1
	fi

	printf '%s' "release-${qbt_ver}_v${libt_ver}"
}

# Download file
download() {
	local url="$1"
	local output="$2"
	local tool
	tool=$(check_download_tools)

	print_info "Downloading: $url"
	case "$tool" in
		wget)
			wget -qO "$output" "$url" || {
				handle_error $? "wget -qO $output $url" "Failed to download binary"
			}
			;;
		curl)
			curl -sL -o "$output" "$url" || {
				handle_error $? "curl -sL -o $output $url" "Failed to download binary"
			}
			;;
	esac

	# Verify download was successful
	if [[ ! -f $output ]] || [[ ! -s $output ]]; then
		print_failure "Download failed or file is empty: $output"
		print_error "URL: $url"
		print_error "Please check your internet connection and try again"
		exit 1
	fi
}
# Main installation
main() {
	# Check if running on supported distribution
	check_supported_distro

	print_info "qBittorrent-nox Static Binary Installer"
	print_info "========================================"

	local arch="${FORCE_ARCH:-$(detect_arch)}"
	local libtorrent_ver="${LIBTORRENT_VERSION:-v2}"
	local install_path="$HOME/bin/qbittorrent-nox"

	print_info "Architecture: $arch"
	print_info "Download tool: $(check_download_tools)"
	print_info "LibTorrent version: $libtorrent_ver"
	print_info "Attestation verification: $(check_gh_cli && printf '%s' "enabled" || printf '%s' "disabled (gh cli not found)")"

	# Get release and download
	local release_tag
	release_tag=$(get_release_tag)
	local url
	url=$(create_download_url "$arch" "$release_tag")

	# Create install directory
	mkdir -p "$HOME/bin" || {
		handle_error $? "mkdir -p $HOME/bin" "Failed to create installation directory"
	}

	# Download and install binary
	download "$url" "$install_path"
	chmod 755 "$install_path" || {
		handle_error $? "chmod 755 $install_path" "Failed to set executable permissions"
	}

	print_success "Installation complete: $install_path"

	# Verify binary integrity (SHA256 + attestations)
	verify_binary_integrity "$install_path" "$release_tag" "$arch"

	# Test binary
	if "$install_path" --version > /dev/null 2>&1; then
		local version_info
		version_info=$("$install_path" --version | head -1)
		print_success "Binary test passed"
		print_info "Version: $version_info"
	else
		print_warning "Binary test failed - the binary may not be compatible with your system"
		print_warning "You may need to install additional dependencies"
	fi

	# PATH check
	if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
		print_warning '$HOME/bin is not in your PATH'
		print_info 'Add to ~/.bashrc: export PATH="$HOME/bin:$PATH"'
		print_info 'Then run: source ~/.bashrc'
	fi

	print_success "Installation completed successfully!"
	print_info "Run with: qbittorrent-nox"
}

# Simple argument parsing
case "${1:-}" in
	--help | -h)
		cat << EOF
Usage: $0 [OPTIONS]

Options:
  --libtorrent VER     LibTorrent version (v1, v2) [default: v2]
  --help               Show this help

Environment Variables:
  LIBTORRENT_VERSION   LibTorrent version (v1, v2) [default: v2]
  FORCE_ARCH           Force architecture (x86_64, x86, aarch64, armv7, armhf, riscv64)

Examples:
  $0                   # Install with LibTorrent v2
  $0 --libtorrent v1   # Install with LibTorrent v1
  FORCE_ARCH=armv7 $0  # Force armv7 architecture
EOF
		exit 0
		;;
	--libtorrent)
		case "${2:-}" in
			v1 | v2)
				LIBTORRENT_VERSION="$2"
				;;
			*)
				print_error "Invalid libtorrent version. Use: v1 or v2"
				exit 1
				;;
		esac
		;;
	"")
		# No arguments, proceed with defaults
		;;
	*)
		print_error "Unknown option: $1. Use --help for usage"
		exit 1
		;;
esac

main
