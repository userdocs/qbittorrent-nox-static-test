### v2.2.6 - 22/11/2026

Behaviour changes worth knowing about before upgrading: `-cd <dir> rm` now refuses unsafe paths and exits `0` on success; value-taking flags reject a following flag as their value; `-bs-e` / `-bs-ef` write `.qbt_env` next to the script and `-bs-e` lists every variable with an empty value; `qbt_qt_version=5` without an explicit cmake request now builds Qt 5 with qmake; `-o` with a cross target is an error in either flag order; `-p` also proxies non-GitHub git hosts; an unprivileged user without sudo can now run the script once the dependencies are installed.

| #   | Severity | Finding | Status |
| --- | -------- | ------- | ------ |
| 1 | Critical | `_custom_flags` never passed `-B${lib_dir}` on Debian/Ubuntu static builds, so GCC linked the system `crt1.o` / `crti.o` against the custom `${lib_dir}/libc.a` built by the `glibc` module. Startup objects and libc from different glibc versions do not link on glibc 2.44+ (`_dl_relocate_static_pie_ifunc` / `_DYNAMIC`). `-B${lib_dir}` is now added to `CFLAGS`, `CXXFLAGS` and `LDFLAGS` (and the Qt 5 `qttools` `QMAKE_LFLAGS`) for static Debian/Ubuntu builds of every module except `glibc` and `*_host_deps`. CI: the 24-job Debian/Ubuntu build matrix failed before the Debian fixes in this release (this entry and the next) and passed 24/24 after them | Fixed |
| 2 | Critical | `_custom_flags` also applied `-fno-plt` when building `glibc` itself. GCC 15 on RISC-V then emits unrelocated `R_RISCV_GOT_HI20` calls in `_dl_start`, `dl-reloc-static-pie.o`, `dl-support.o` and `libc-start.o` (GNU glibc bug #33261), so the freshly built `ld.so` / `localedef` segfaulted (`C.UTF-8...Segmentation fault` at the `localedef` step of every riscv64 Debian/Ubuntu job). `-fno-plt` is now skipped for `glibc`. `_custom_flags_reset` (used for `glibc`) also resets `LDFLAGS` to the user's `qbt_ldflags`; before, a `glibc` built after another module (module order is user-defined) inherited that module's `-L` / `-pthread` flags | Fixed |
| 3 | High | `_check_dependencies` always stopped a user with neither root nor passwordless sudo with "No root or sudo privileges detected" / "Please request or install the missing core dependencies" and exit code 1, even when every dependency was already installed (reproduced with every package reported present), so the script could not run for unprivileged users (containers, locked-down CI, shared hosts). The warning and exit now only happen when a dependency or test tool is missing, or a privileged action (`update`, `install_test`, `install_core`, `bootstrap_deps`) was requested, and the `apk add` / `apt-get install -y` command hint is omitted when no core packages are missing | Fixed |
| 4 | High | `_check_dependencies` ignored the exit codes of `command_update_upgrade_os` / `command_install_deps` and returned success when standalone `bootstrap_deps` or `install_core` failed or left core dependencies missing, masking a failed environment setup in CI. `_update_os` and `_install_tools` now exit 1 on failure, and `install_core` / `bootstrap_deps` exit 1 if core dependencies are still missing afterwards | Fixed |
| 5 | High | `-cd <dir> rm` ran `rm -rf` on whatever path was given with no validation, canonicalisation or `--` (reproduced: `-cd "$HOME" rm`, the current directory and the script's own directory were all deleted, and the exit code was 1 even on success). `-cd` now requires a path, strips trailing slashes, resolves symlinks and non-existent path tails via `_resolve_path`, and refuses (exit 1) an empty path, `/`, `.`, `..`, `$HOME`, `$PWD`, the script directory, any ancestor directory of `$HOME`, `$PWD` or the script directory (blocking parent-directory deletion such as `-cd /home rm`), or any path rejected by `_validate_path`. A successful removal now exits `0` | Fixed |
| 6 | High | `-o` / `--optimise` (or `qbt_optimise=yes` in `.qbt_env`) given before `-ma` bypassed the cross-compilation check, which only ran when `-ma` came first, so `-march=native` of the build host was injected into cross builds (target instruction mismatches or compiler errors; reproduced). `_set_default_values` now rejects `qbt_optimise=yes` with a cross target in any order and `_custom_flags` only adds `-march=native` when `qbt_cross_name` is `default` | Fixed |
| 7 | High | Absolute paths passed to `-b` (`qbt_build_dir`) were prefixed with `${qbt_working_dir}/` in `_set_default_values` (reproduced: `/work//abs/path`), corrupting `qbt_install_dir`, `qbt_mcm_dir`, `qbt_cross_tool_dir` and `qbt_host_deps_path`; `_set_build_directory` also overwrote `LOCAL_USER_HOME` on repeated calls and constructed `PATH` as `${qbt_install_dir}/bin${PATH:+:${qbt_local_paths}}` (appending a trailing `:` — current working directory — when `qbt_local_paths` was empty). Absolute paths are now used as-is where all four directories are derived, `LOCAL_USER_HOME` and `qbt_local_paths` are preserved idempotently, `PATH` expands `${qbt_local_paths:+:${qbt_local_paths}}` without trailing colons, and `script_parent_path` defaults to `/` when the script is located in `/` | Fixed |
| 8 | Medium | `-bs-c` / `--bootstrap-cmake` pushed `-bs-c` into `params1` but the second option loop had no handler, so the documented flag (see `-h-bs-a`) always aborted with `Unsupported flag -bs-c` (reproduced). The second loop now accepts it; `qbt_build_tool` is already set in the first loop | Fixed |
| 9 | Medium | `-bs-ma` checked `multi_arch_options[${qbt_cross_name}]` without excluding `default`, so the "You must provide a valid arch option" error was unreachable and the flag silently fell through to the module list with exit 0 (reproduced), and it called `_multi_arch` without `bootstrap`, skipping the forced toolchain refresh. It now lists the valid arches (without `default`), exits 1 and runs `_multi_arch bootstrap` | Fixed |
| 10 | Medium | Bootstrap flags (`-bs-ef`, `-bs-p`, `-bs-r`, `-bs-ma`, `-bs-a`) executed immediately during option parsing, before later tag, version or arch flags (`-lt`, `-qt`, `-ma`, ...) were processed, so the generated env file, patch directories, release notes and toolchain used stale values. They are now recorded and run after all flags are parsed; `-bs-ef` runs after `_set_cxx_standard` so it reports the resolved `qbt_standard` (`20` instead of the unresolved default `17`) | Fixed |
| 11 | Medium | `install` ran after `_check_dependencies`, `_test_url` and `_set_module_urls`, so installing an already built binary needed build tools and network access. It now short-circuits right after `_set_default_values` when no other flag is present (so `install -h` still reaches the help), works offline and without build tools, and only uses privileges when the target needs them | Updated |
| 12 | Medium | `_install_qbittorrent custom` ran `mkdir` / `cp` / `chmod` through sudo even inside the user's home, followed by a recursive `chown -R` of the whole target directory, and accepted paths containing `..` (reproduced). The path now goes through `~` expansion (`LOCAL_USER_HOME`), multi-slash stripping, `_validate_path` (rejects `..`) and `_resolve_path` (resolving symlinks even when multiple nested target directories do not exist yet, where `readlink -f` fails); privileges are only used for absolute paths resolving outside the user's home, relative paths stay user-owned, every command uses `--` and the `chown` step is gone | Fixed |
| 13 | Medium | Build tool and Qt precedence: the default was already `cmake` + Qt 6 (only the comment still said qmake + Qt 5), but `qbt_qt_version=5` (env or `.qbt_env`) was silently coerced to cmake + Qt 6 (reproduced), `.qbt_env` values beat `-q` / `-c`, minor pins such as `5.15` or `6.8` matched no case, and `-qtt` only rejected cmake + Qt 5. The cases now accept `5 \| 5.*` and `6 \| 6.*`, `-c` / `-q` are tracked in `qbt_build_tool_cli` so the CLI wins, `qbt_qt_version=5` selects qmake + Qt 5 unless cmake was requested explicitly, and `-qtt` rejects both mismatched combinations | Fixed |
| 14 | Medium | `cxx_qt_cap`, the `qbt_workflow_versions` Qt key and the `loongarch64` Qt 6 check indexed the full `qbt_qt_version`, so minor pins such as `5.15` or `6.8` missed the `"5"` / `"6"` entries (Qt 5 was not capped at c++17, workflow versions were not found). They now use `${qbt_qt_version%%.*}` | Fixed |
| 15 | Medium | `_semantic_version` stripped only a `v` prefix, so prefixed pre-releases (`boost-2.1.0.beta1`, `release-5.1.0rc1`) were parsed with the pre-release number as a build/patch component and ranked above the final release, and `_`-delimited pre-releases (`2.1.0_rc1`) were not recognised. `release-`, `boost-`, `openssl-`, `libtorrent-`, `libtorrent_` and `glibc-` are now stripped and `.`, `_` and `-` are accepted as separators. `_resolve_app_cxx_val` evaluated non-numeric custom branch names as `0.0.0`, a c++14 floor (reproduced); it now falls back to the default standard | Fixed |
| 16 | Medium | `_custom_flags` for `*_host_deps` (only built in `qbt_with_qemu=no` cross builds, not exercised by CI): the LTO wrappers `gcc-ar` / `gcc-nm` / `gcc-ranlib` and the compiler used for the version probe resolved through `PATH` or the cross prefix to the cross toolchain in `${qbt_install_dir}/bin`, and `-I${include_dir}` / `-L${lib_dir}` pointed `/usr/bin/gcc` at cross-target `glibc`/`zlib` headers and archives in `${qbt_install_dir}`, breaking native host-tool compilation. `*_host_deps` now use `/usr/bin/gcc`, `/usr/bin/gcc-ar`, `gcc-nm`, `gcc-ranlib` and scope `-I` / `-L` to `${qbt_host_deps_path}/{include,lib}`, and cross version probes use `${qbt_cross_tool_dir}/${qbt_cross_host}-gcc` matching `CC` | Fixed |
| 17 | Medium | Native builds (`qbt_cross_name=default`) did not delete `icu_host_deps`, `qtbase_host_deps` and `qttools_host_deps` when `qbt_with_qemu=no` (reproduced), so host-only modules were scheduled for native builds, and a positional `icu` / `icu_host_deps` was evaluated after the `icu_host_deps` deletion decision. Native builds now always delete them and the positional check runs first | Fixed |
| 18 | Medium | `_apply_patches` and `_set_icu_sub_dir` used the `*_host_deps` name as the module key instead of stripping the suffix, so `app_version`, `patch_dir` and the cached `icu` `sub_dir` were not found in cross builds without QEMU. `_delete_function` also never removed `${base_app_name}.tar.xz` or the base source directory after `*_host_deps` builds | Fixed |
| 19 | Medium | `_qbt_host_deps` passed `<arch>-host-deps.tar.xz` as the module name to `_download`, which appends `.tar.xz` again (`...tar.xz.tar.xz` archive and log names), and left the working directory and `pushd` stack inside `${qbt_install_dir}/host_deps`. It now passes the bare name and returns to `${qbt_working_dir}` (`dirs -c`) | Fixed |
| 20 | Medium | `_set_module_urls` and `-ot lts` interpolated `qbt_libtorrent_version`, `qbt_qt_version` and `qbt_openssl_lts` into unanchored `awk` regexes: `.` matched any character and prefixes collided (`qbt_qt_version=6.1` selected `v6.10.x`), and the values became part of the awk program text (only reachable by whoever controls the invoking user's own environment, so a correctness problem rather than a privilege boundary). The prefix is now passed with `-v` and matched exactly, followed by `.`, `-` or end of tag, and a failed `-ot lts` lookup resolves to `error_tag` | Fixed |
| 21 | Medium | `_git <url> -t <tag>` handed the ref to `git ls-remote` as a glob pattern, so `v2.*`, `v2.0.1?`, `refs/tags/v2.0.11` and `heads/RC_2_0` were accepted as valid tags (reproduced) and partial tail matches could succeed. Refs starting with `-` or containing glob characters, whitespace or control characters are rejected and only exact `refs/heads/<ref>` / `refs/tags/<ref>` lookups after `--` are accepted; the `-cd <dir> bs` update path uses the same exact lookups | Fixed |
| 22 | Medium | `-pr` and `_apply_patches` iterated `qbt_patches_url` unquoted (word splitting and globbing) and accepted repo paths with arbitrary segments, which were interpolated into GitHub API/raw URLs and local patch file names. The list is now read with `read -ra` and every entry must match `owner/repo` (`[A-Za-z0-9._-]+/[A-Za-z0-9._-]+`) | Fixed |
| 23 | Medium | `_apply_patches` accepted any scheme in `url` files (`file://`, `ftp://`) and trusted remote directory listings. Non-HTTP(S) patch URLs, entries whose name contains `/`, is `.` / `..` or contains control characters, and non-HTTP(S) `download_url` values are now skipped with a message instead of being written to the patch directory | Fixed |
| 24 | Medium | Downloading patches from several `qbt_patches_url` repositories overwrote the `patch`, `url` and `*.patch` / `*.diff` files fetched from the earlier repository. Colliding `url` files are now appended and colliding `patch` / `*.patch` / `*.diff` files are saved as `<owner>_<repo>_<name>`, so every repository contributes | Fixed |
| 25 | Medium | The remote `Jamfile` fallback in `_apply_patches` downloaded straight over `${qbt_dl_folder_path}/Jamfile` and deleted the original source `Jamfile` on an empty or failed response. Both remote and `qbt_libtorrent_master_jamfile=yes` downloads are now staged in `Jamfile.tmp` and only moved into place when non-empty (`-s`); a failed or empty `qbt_libtorrent_master_jamfile=yes` download aborts with `_error_tag` | Fixed |
| 26 | Medium | `_process_local_patches` appended the `url` target to a pre-populated `patch` file even when the contents were identical (e.g. `qtbase` / `qttools` 6.7.2), so `patch -p1` failed on already applied hunks, and wrote comment-only headers when a `url` returned an empty HTTP 200 body (causing `patch -p1` to fail on garbage input). Byte-identical downloads and 0-byte HTTP responses (in both `_process_local_patches` and `_download_remote`) are now skipped | Fixed |
| 27 | Medium | `_download_directory_contents` treated HTTP 404 (normal when a module has no remote patches) as an API error, triggering 8 unnecessary raw URL fallback requests per module. 404 now returns success without a download; other statuses (rate limit, network error) still fall back to raw file probing | Fixed |
| 28 | Medium | JSON parsing and formatting: `jq` is now the primary parser, with `type == "array"` / `"object"` validation and the previous `grep` / `sed` fallback, for `_download_directory_contents`, `_release_info` (`.revision`, only incremented when numeric, with `qbt_revision_url` validated as `owner/repo` and exact `refs/tags/` lookup) and `qbt_workflow_versions` (whose `sed` fallback now tolerates whitespace around `:`); `dependency-version.json` and URL/symlink logs use `%s` instead of `%b` | Updated |
| 29 | Medium | `_download_folder` left `qbt_dl_folder_path` on `${qbt_cache_dir}/${app_name}`, so patches modified the cached repository and, when local patches existed, the cached repository was deleted on every run. The cache is now copied (checked with `_cmd`) and `qbt_dl_folder_path` points at the build copy, leaving the cache untouched, and `_download` ensures `${qbt_install_dir}` exists before `_pushd`. The `bs` update path also gained `--`, exact refs and `_cmd` checks around `fetch` / `checkout` | Fixed |
| 30 | Medium | `_download_folder` and `_download_file` patch detection checked `patch`, `url` and `source/` but missed `*.patch` and `*.diff` files, so a clean re-extraction or clone was skipped when only those files were present | Fixed |
| 31 | Medium | `-cd <dir> bs` ran a redundant `git fetch` and `git checkout` immediately after cloning a new repository, and `_download_file` aborted instead of refreshing a corrupt cached archive. The update is now an `elif` of the clone branch and, in `bs` mode, a corrupt cached archive is removed and downloaded again (other modes still fail with an error) | Fixed |
| 32 | Medium | `_set_module_urls` scraped `ftpmirror.gnu.org/gnu/libiconv/` on every start-up (even when `iconv` was unused or `qbt_workflow_files=yes`) and had no fallback when the `zlib-ng` version could not be fetched or a non-`develop` archive tag was used. The iconv tarball name is now derived from the resolved `app_version[iconv]` (one source of truth for version and archive; resolved URLs verified identical to the scraped ones), `zlib-ng` falls back to the tag version and tagged builds use `archive/refs/tags/<tag>.tar.gz` | Fixed |
| 33 | Medium | Validating `openssl`, `libtorrent` and `qbittorrent` release archives and `-pr` repositories downloaded the full tarball or page (`_curl <url> &> /dev/null`) just to test that it exists. They now use an HTTP `HEAD` request (`_curl -sfLI`) | Updated |
| 34 | Medium | Value-taking flags (`-b`, `-cd`, `-p`, `-ot`, `-bt`, `-lt`, `-pr`, `-qt`, `-qtt`) accepted the next flag as their value (reproduced: `-b -c` made `-c` the build directory), `-ot lts` left `github_tag[openssl]` empty instead of `error_tag` when the lookup failed, and operands after `--` were lost between the two option loops (reproduced). Missing or `-`-prefixed values are now rejected and `--` operands are forwarded | Fixed |
| 35 | Medium | `-ot`, `-lt` and `-qt` did not set `source_default` back to `"file"` when a valid release archive URL followed a branch tag, forcing a needless git clone, while `-ot`, `-bt` (`_boost_url`), `-lt`, `-qt` and `-qtt` still probed `.../error_tag/...` archive URLs and overwrote `qbt_libtorrent_version` / `qbt_qt_version` when tag validation failed. Valid tags now restore `file` via `HEAD` and `error_tag` skips archive probes and version clobbering | Fixed |
| 36 | Medium | `~` prefixes in quoted or `.qbt_env`-defined `qbt_build_dir` / `qbt_cache_dir` were not expanded, creating a literal `./~/` directory (reproduced). Both are now expanded and trailing slashes (including repeated `///`) stripped. `qbt_cache_dir` also stayed relative and `/` collapsed to an empty string (cache silently disabled); a relative cache path is now resolved against the working directory up front and `/` is preserved | Fixed |
| 37 | Medium | `-bs-e` / `-bs-ef` wrote `.qbt_env` to `$(pwd)`, while start-up and the cache copy read `${script_parent_path}/.qbt_env`, so a template created from another directory was never loaded; the `sed` also used the non-POSIX `\x1B` escape and removed only three colour codes. Both now write beside the script and strip every `ESC[..m` sequence using `$'\e'`. `-bs-e` additionally forces the advanced view and blanks every value, so the template lists all 29 variables with empty values (it previously wrote 4 variables, filled from the environment), matching its help text ("empty vars") | Fixed |
| 38 | Medium | `-p` / `--proxy` only set `http.https://github.com.proxy` for git, so `glibc` (sourceware.org) and `iconv` (savannah.gnu.org) were cloned without the proxy while curl used it (verified: the GitHub-only key does not apply to other hosts), and bare `git` calls (`apply`, `submodule update`, `ls-remote`) bypassed `_git_git`. `http.proxy` is now set and every git call goes through `_git_git` | Fixed |
| 39 | Medium | `_boost` compiled `b2` with the target cross-compiler instead of the host `/usr/bin/g++` when `qbt_with_qemu=no`, skipped building `b2` for folder (git) sources under CMake so `b2 headers` failed, and moved the extracted folder onto itself when it was already `${qbt_install_dir}/boost`. `b2` is now built with host tools, for folder sources, only when missing, and the move is guarded | Fixed |
| 40 | Medium | `_qtbase` wrote a cross `qmake.conf` unconditionally (also for CMake builds, and as `mkspecs//qmake.conf` on native builds where `qbt_cross_qtbase` is empty) and overwrote the `-m32` / `-m64` `QMAKE_CFLAGS` / `QMAKE_LFLAGS` bitness flags on `x86` / `x86_64`. The file is only written for qmake cross builds, flags are appended with `+=` and the static `QMAKE_LFLAGS` edit requires qmake | Fixed |
| 41 | Medium | `_libtorrent` and `_qbittorrent` always passed `-D Iconv_LIBRARY=${lib_dir}/libiconv.a` to CMake, even when `iconv` is skipped for libtorrent v2.0 / v2.1 and the archive does not exist. The option is only passed when the archive exists | Fixed |
| 42 | Medium | Unset `qbt_libtorrent_debug` / `qbt_qbittorrent_debug` passed an empty `""` argument to `b2` and `./configure` on non-debug qmake builds. The optional arguments are now arrays | Fixed |
| 43 | Medium | The build functions did not check the `configure`, `b2` / `cmake`, `install` and locale steps with `_post_command` (nor `dot`, `autogen.sh` and `gitsub.sh` with `_cmd`), so a failed step continued silently. Checks were added to every module builder | Fixed |
| 44 | Medium | `_libtorrent` (b2) generated an empty `Version:` field in `libtorrent-rasterbar.pc` when `strings -d` returned nothing on LTO archives. It now falls back to `libtorrent_version_hpp` | Fixed |
| 45 | Medium | `_qbittorrent` did not verify that `${qbt_install_dir}/bin/qbittorrent-nox` existed after installing, the module loop did not exit non-zero when `boost` was missing for `libtorrent` / `qbittorrent`, and the script ended with a bare `exit` that returned the status of the last command. A missing binary now raises `_error_tag`, a missing `boost` exits 1 after the loop and the script ends with `exit 0` | Fixed |
| 46 | Medium | `_icu_host_deps` ended with `_pushd` instead of `_popd` (leaking a directory-stack entry) and the main loop pushed `${qbt_working_dir}` for every module. The stack is now balanced and each iteration ends with `cd "${qbt_working_dir}"` and `dirs -c` | Fixed |
| 47 | Medium | `_sort_modules` did not reset `qbt_modules_install_processed`, `_installation_modules` validated parameters with a regex built from user input (metacharacters were interpreted) and passing `all` after another module invoked the non-existent `_all`. The list is reset, parameters are compared as exact strings and `all` is honoured anywhere in the parameter list | Fixed |
| 48 | Medium | `_check_dependencies` simulated the installation of the test tools only (twice) and never the missing core dependencies, always ran `_update_os` for `bootstrap_deps` and re-installed test tools that were already present. The simulation now covers test tools plus missing core dependencies once, `update` only runs when the simulation fails (and never twice) and only missing test tools are installed | Fixed |
| 49 | Medium | Updated `patches/libtorrent/1.2.20/url` and `patches/libtorrent/RC_1_2/url` (`7f04953b` to `49746087` in `userdocs/libtorrent`, "Add Boost 1.87-1.92 and OpenSSL 4.0 support") so libtorrent 1.2 builds with current Boost and OpenSSL; the newer commit additionally patches the b2 `Jamfile` and socket headers that the script's b2 build of libtorrent 1.2 uses | Updated |
| 50 | Low | `_tee` tested `${1%/*} =~ /`, which is false for single-level relative paths such as `logs/zlib.log`, so `mkdir -p` was skipped and `tee` failed (reproduced); it now tests `${1} == */*`. `_download_directory_contents` and `_download_remote` also left `.tmp` files behind when `url` downloads failed | Fixed |
| 51 | Low | `_script_version` did not guard against multi-line, empty or unparseable `script_version_remote` responses, producing malformed version comparisons. It now takes the first line and skips the check when nothing parses | Fixed |
| 52 | Low | `_cache_dirs_qbt_env_copy` overwrote the cached `.qbt_env` on every run, so the drift warning in `_cache_dirs_qbt_env` could never fire (the files were made identical first). It now copies on initial cache creation, or in `bs` mode only when the contents differ | Updated |
| 53 | Low | `_get_archive_dir_name` used a greedy `grep -Eom1 "(.*)[^/]"` that returned a whole path when the first archive entry was not a directory entry; it now extracts the first top-level component with `awk` (skipping `./` and `.`). The pipeline status is no longer used: awk exits at the first entry so `tar` receives SIGPIPE, which fails the lookup under `pipefail` for any realistic archive (reproduced 100 of 100 runs on a 4000-entry archive) and made the unit suite occasionally flaky | Fixed |
| 54 | Low | `_debug` (`-sdu`) raised `bad array subscript` on empty associative arrays (e.g. `qbt_workflow_versions` when `-wf` is not set); every sorted-key loop now skips empty keys | Fixed |
| 55 | Low | Variable scope hygiene: `gcc_version`, `gcc_command` and `qbt_optimise_march` in `_custom_flags`, plus loop and temporary variables in `_color_test`, `_git`, `_boost_url`, `_debug`, `_apply_patches`, `_cache_dirs_qbt_env`, `_install_qbittorrent`, `_qbt_host_deps` (`sub_dir`), `_fix_static_links`, `_fix_multiarch_static_links`, `_multi_arch`, `_release_info` (`qbt_revision_version`) and the module builders (`openssl_config`, `icu`, `arm_libatomic`, `stacktrace`) were global and leaked state between module iterations. They are now `local`, replacing the `done && unset var` pattern | Fixed |
| 56 | Low | Removed dead and redundant code: the `bootstrap-help` branch of `_apply_patches` (and its callers in `-h-bs-p` / `-h-pr`), the `build_tools` / `command_test_tool` arrays in `_check_dependencies`, the unreachable `_error_tag` branches after `_git clone` in `_download_folder` (`_git` already exits on failure), the duplicate `qbt_skip_icu` `else` branch in `_set_default_values`, the tautological `if` in `-i`, the redundant `qbt_workflow_files` check in `_download`, the no-op `printf ''` ternary in `_cache_dirs_qbt_env_copy` and the duplicate relative `qbt_cache_dir` normalisation after `_set_default_values` | Fixed |
| 57 | Low | `_apply_patches bootstrap` miscounted modules in the "Patch directories created for N modules" message (it counted every sorted module, including `*_host_deps` and deleted ones, instead of the directories created) | Fixed |
| 58 | Low | `qbt_patches_url` is no longer re-validated through `-pr` when it equals the default `userdocs/qbittorrent-nox-static`, which saves a network request on every run and lets the offline test harness run. `-pr` with any other value still validates every repository | Updated |
| 59 | Low | `_multi_arch`: a failed toolchain download now aborts with `_error_tag` and the extraction is checked with `_cmd`; the messages named the wrong file (`.tar.xz` instead of the `.tar.gz` that is stored) and claimed multiarch only works on Alpine | Fixed |
| 60 | Low | `_cache_dirs_qbt_env`: the `\|\| echo "unavailable"` fallback applied to `cut`, never to a missing `sha256sum` (so the checksum was blank instead of `unavailable`), and was the last `echo` in the script. The checksum now defaults to `unavailable` when `sha256sum` is missing or fails | Fixed |
| 61 | Low | `-m` and `-lm` did not re-run `_libtorrent_v2_iconv_check` after switching libtorrent to its `RC_x_y` branch and, like `-qtt`, left `source_archive_url` pointing at the previous default release. `-sdu` output and the `iconv` module selection now match the branch or tag actually used | Fixed |
| 62 | Low | Help and message fixes: `--help-staticish` and `--help-multi-arch` now work next to `--help-static-ish` / `--help-multiarch` (the `-h` list advertised spellings that failed), `-h-p` exits `0` (it returned the last test's status, `1` without a proxy), invalid `-bs-ma default`, `-bs-a` and `-o` examples were corrected, `qbt_with_qemu` was added to the `-h` env list, the `qbt_workflow_files` / `qbt_standard` descriptions were fixed and the `mipsel` release-note row printed `-with-arch=mips32` instead of `--with-arch=mips32` | Fixed |
| 63 | Low | Cosmetic only, no behaviour change: 26 comment dividers normalised (145 / 154 / 56 to 151 / 60 characters), about 50 lines of `$var` to `${var}` (clears the optional `shellcheck -o all` SC2250 check; CI only enforces `--severity=warning`), duplicate `${color_end}` sequences and unmatched colour codes removed from `printf` strings (guarded by a unit test) and 9 comment typos fixed | Fixed |
| 64 | Info | Added an offline unit test suite (`tests/unit_tests.bash`: 872 tests across 18 sections, zero module compilation, about 15 seconds), `.github/workflows/ci-unit-tests.yml` and `$GITHUB_STEP_SUMMARY` Markdown output across the GitHub Actions workflows. The `cxx_*` maps are declared `declare -gA` so the suite can source the function library from inside a function | Added |

### v2.2.5 - 23/04/2026

| #   | Severity | Finding                                                                                                 | Status  |
| --- | -------- | ------------------------------------------------------------------------------------------------------- | ------- |
| 1   | Medium   | Added Debian/Ubuntu `/usr/bin` toolchain support alongside Alpine `qbt_mcm_dir` via `qbt_cross_tool_dir`| Added   |
| 2   | Medium   | Refactored `cxx_version_map` to `_resolve_app_cxx_val` utilizing Bash 4.3 namerefs for cleaner checks   | Updated |
| 3   | Medium   | Deployed dynamic GCC LTO wrappers (`gcc-ar`, `gcc-nm`, `gcc-ranlib`) for cross and native targets       | Added   |
| 4   | Medium   | Expanded `mold` linker dependency triggers across Alpine natively and Debian/Ubuntu                     | Updated |
| 5   | Medium   | Updated `qbt_workflow_versions` logic with robust `jq` and `sed` fallback URL parsers                   | Updated |
| 6   | Low      | Cleaned up deprecated patch files (`openssl3_linux.patch`, `api.diff`) mapping to upstream URLs         | Fixed   |
| 7   | Medium   | Added `-ot`/`--openssl-tag` flag and `qbt_openssl_tag` to allow custom OpenSSL versions and `lts` handling| Added   |

### v2.2.4 - 29/03/2026

| #   | Severity | Finding                                                                                                 | Status  |
| --- | -------- | ------------------------------------------------------------------------------------------------------- | ------- |
| 1   | High     | Missing branch name validation for patch repos could allow command injection via malformed URLs         | Fixed   |
| 2   | Medium   | C++ standard configuration dynamically resolved with Floor/Ceiling limits (`_set_cxx_standard`)         | Added   |
| 3   | Medium   | `_apply_patches` only permitted single `url` files; now sequentially loops multiple patch lines         | Fixed   |
| 4   | Medium   | Unhandled iteration over multiple remote repositories assigned in `qbt_patches_url`                     | Fixed   |
| 5   | Medium   | `_semantic_version` `master`/`latest` tags did not resolve accurately against highest C++ floors        | Fixed   |
| 6   | Medium   | Libtorrent CMake configuration triggers deprecation issues and missed `webtorrent=ON` for v2.1+         | Fixed   |
| 7   | Medium   | `iconv` retention logic bypassed reliable checks and incorrectly peristed on some non-v1 setups         | Fixed   |
| 8   | Low      | `python-numpy` and `python-numpy-dev` package inclusion caused resolution conflicts                     | Fixed   |
| 9   | Low      | Libtorrent `version_str` fallback in `version.hpp` not parsed when missing `LIBTORRENT_VERSION`         | Fixed   |
| 10  | Info     | OS max capability capping limits introduced to cleanly prevent incompatible `c++` compilations          | Added   |
| 11  | Info     | `-std=c++${qbt_standard}` format dynamically merged into `CXXFLAGS`/`QMAKE_CXXFLAGS` internally         | Updated |
| 12  | High     | `cxx_os_cap` fallback for unlisted OS defaulted to `23` instead of `17` circumventing compiler safety   | Fixed   |
| 13  | High     | ABI Mismatch Check added to strictly prevent mixing `c++14` targeted projects with `c++17`              | Added   |
| 14  | Medium   | `_set_cxx_standard` resolved lowest requirement instead of intersecting highest safe capable standard   | Fixed   |
| 15  | Low      | `_download` Shellcheck `SC2015` warnings related to unsafe short-circuit evaluation logic               | Fixed   |
| 16  | Low      | GitHub API JSON parsing in `_download_directory_contents` made robust against `null` types              | Fixed   |
| 17  | Medium   | Manual `Jamfile` overrides correctly preserved during external patch directory synchronization          | Fixed   |
| 18  | Medium   | Temporary patch files in `_process_local_patches` processed safely to avoid duplicate merge conflicts   | Fixed   |

### v2.2.3 - 21/03/2026

No breaking changes. Some work towards Libtorrent RC_2_1 support but mostly bugs fixes.

| #   | Severity | Finding                                                                                                 | Status |
| --- | -------- | ------------------------------------------------------------------------------------------------------- | ------ |
| 1   | Critical | `-lm\|--libtorrent-master` sets `source_default[qbittorrent]` instead of `[libtorrent]`                 | Fixed  |
| 2   | Critical | `-q\|--qmake` sets `qbt_build_tool="--qmake"` instead of `"qmake"` — breaks all qmake builds            | Fixed  |
| 3   | Critical | `_git` — `git_test_cmd` not local/reset; stale URL from prior call used silently                        | Fixed  |
| 4   | Critical | `_post_command` PIPESTATUS capture fragile — any code before `outcome=` line silently breaks it         | Fixed  |
| 5   | Critical | Duplicate `qbt_strip_flags` logic — second block overrides first, injects `-g` even when debug=no       | Fixed  |
| 6   | Critical | Linker flag `-z,--no-copy-dt-needed-entries` — `--no-copy-dt-needed-entries` is not a `-z` argument     | Fixed  |
| 7   | Critical | `armhf` cross_arch set to `"armel"` for Debian — installs wrong crossbuild package                      | Fixed  |
| 8   | High     | Bare `exit` (code 0) in `_set_build_cons` error path — CI sees success on rejected builds               | Fixed  |
| 9   | High     | Infinite retry loop in `_release_info` — hangs CI if URL is permanently unavailable                     | Fixed  |
| 10  | Info     | `_check_dependency_status` modifies global `filtered_params`                                            | Fixed  |
| 11  | Info     | `_debug` inner for loop over single-element string is misleading                                        | Fixed  |
| 12  | Info     | `_qt_std_cons` and similar functions use `printf` return pattern — fragile if output is polluted        | Noted  |
| 13  | Info     | `_test_url` comment says "google.com" but function tests `github.com`                                   | Fixed  |
| 14  | Info     | Glob in `_multi_arch` symlink loop may fail silently on no match                                        | Fixed  |
| 15  | Info     | Help text for `-h-qtt` shows `-qt` in usage examples instead of `-qtt`                                  | Fixed  |
| 16  | Logic    | `_error_tag` ignores its arguments — silent exits with no error message                                 | Fixed  |
| 17  | Logic    | `qbt_dl_folder_path` collapses to install dir on corrupt/empty archive                                  | Fixed  |
| 18  | Logic    | `qbt_host_deps` referenced before its default is assigned                                               | Fixed  |
| 19  | Logic    | `qbt_patches_url_branch` unset when remote download is skipped — malformed Jamfile URL                  | Fixed  |
| 20  | Logic    | Duplicate dependency deletion block for Debian — idempotent but indicates copy-paste error              | Fixed  |
| 21  | Low      | Alpine version check comment says "min v3.10" but code enforces 3.18                                    | Fixed  |
| 22  | Low      | `-fuse-ld=mold` placed in CFLAGS/CXXFLAGS — linker selection flag belongs in LDFLAGS only               | Fixed  |
| 23  | Low      | `-h-m` (`--help-master`) shows `-lm` in usage example instead of `-m`                                   | Fixed  |
| 24  | Low      | `arm_libatomic` not declared `local` in `_libtorrent`/`_qtbase` — leaks between calls                   | Fixed  |
| 25  | Low      | `chmod +x -R` on a single file — `-R` flag is misleading and redundant                                  | Fixed  |
| 26  | Low      | `command_privilege` may be unset if neither root nor sudo                                               | Fixed  |
| 27  | Low      | `exit_script` in `_set_build_cons` not declared `local` — could fire on leaked global                   | Fixed  |
| 28  | Low      | `pkgman` function shadows `pkgman` array inside loop and is redefined every iteration                   | Fixed  |
| 29  | Low      | `qbt_core_deps_sorted` grows without reset on re-check across multiple `_check_dependency_status` calls | Fixed  |
| 30  | Low      | `qbt_dl_folder_path` collapses to install dir on corrupt archive (carried from v1)                      | Fixed  |
| 31  | Low      | `sub_dir` global variable leaks between modules if bootstrap does not unset it                          | Fixed  |
| 32  | Low      | `_boost` runs `sed -i` on `build.sh` without checking file exists or pattern matches                    | Fixed  |
| 33  | Low      | `_cache_dirs_qbt_env` calls `exit 1` from inside download hot path — confusing failure context          | Fixed  |
| 34  | Low      | `_download_directory_contents` grep-based JSON parsing fragile against API format changes               | Fixed   |
| 35  | Low      | `_fix_multiarch_static_links` ignores its argument, uses global `qbt_cross_host` directly               | Fixed  |
| 36  | Low      | `_icu_host_deps` second `make` call uses `_tee` without `-a` — overwrites configure log                 | Fixed  |
| 37  | Low      | `_installation_modules` regex over `${!qbt_modules_install[*]}` fragile with non-default IFS            | Open   |
| 38  | Critical | `_semantic_version` output starting with `0` (e.g. `0.8`) is evaluated as octal by `[[ -lt ]]`          | Fixed  |
| 39  | Low      | `_semantic_version` strips non-numeric chars: `10rc1` becomes `101` — misparses RC versions             | Fixed  |
| 40  | Low      | `_semantic_version` zero-padded components (`08`, `09`) trigger bash octal parse error                  | Fixed  |
| 41  | Low      | `_test_git_ouput` function name typo (`ouput`)                                                          | Fixed  |
| 42  | Low      | Missing `${color_end}` after `${color_green}` in `-h-m` output — color bleeds into terminal             | Fixed  |
| 43  | Low      | Multiple assignments on one line after `&&` — second assignment always executes regardless of test      | Fixed  |
| 44  | Low      | Redundant inner `if [[ ${qbt_host_deps} == "yes" ]]` inside already-gated outer block                   | Fixed  |
| 45  | Low      | Stale `unset tar_additional_cmds` — dead codeafter array was removed                                    | Fixed  |
| 46  | Low      | Typo in loongarch64 error message — "on and Alpine Host" → "on an Alpine Host"                          | Fixed  |
| 47  | Low      | Typo: "arugment" → "argument" in error message                                                          | Fixed  |
| 48  | Low      | Undeclared array `build_tools` used in `_check_dependency_status` — unset is a no-op                    | Fixed  |
| 49  | Medium   | `-qm\|--qbittorrent-master` sets `source_archive_url` but not `source_default` — no fallback to git     | Fixed  |
| 50  | Medium   | `gcc_version` unset when cross-compiler unavailable — `[[ -ge ]]` emits integer error to stderr         | Fixed  |
| 51  | Medium   | `github_tag[boost]` assignment missing quotes around command substitution                               | Fixed  |
| 52  | Medium   | `os_arch` never set when OS is unrecognised — empty value used in security flags and multiarch          | Fixed  |
| 53  | Medium   | `qbt_cflags_consumed` missing from top-level `unset` list                                               | Fixed  |
| 54  | Medium   | `qbt_cross_boost` not set for `x86` cross-build — defaults to `gcc`, may be wrong                       | Fixed  |
| 55  | Medium   | Qt/qttools tag regex `sub("(.*)(-alpha\|-beta\|-rc)", "")` still mangles not filters                    | Fixed  |
| 56  | Medium   | `_check_dependency_status` global `filtered_params` — brittle call-order dependency (v4 #7 carried)     | Fixed  |
| 57  | Medium   | `_delete_function` calls `_pushd` without `_popd` — stack grows by one entry per module                 | Fixed  |
| 58  | Medium   | `_download_file` — `tar_additional_cmds` uses `+=` instead of `=`; stale on early return                | Fixed  |
| 59  | Medium   | `_git` curl test passes `-t TAG` to curl — `-t` is curl's `--telnet-option`                             | Fixed  |
| 60  | Medium   | `_git` scans for URLs at hardcoded positional indices 9 and 11                                          | Fixed  |
| 61  | Medium   | `_iconv` missing `_post_command build` check — silent build failure                                     | Fixed  |
| 62  | Medium   | `_iconv` — `autogen.sh` only runs when cache dir is set; folder-source without cache fails              | Fixed  |
| 63  | Medium   | `_post_command` captures `PIPESTATUS` at function entry, not at pipeline call site — may miss failures  | Fixed  |
| 64  | Medium   | Help long-form mismatch: `--help-boost-version` in output vs `--help-boost-tag` in handler              | Fixed  |
| 65  | Medium   | Help long-form mismatch: `--help-multi-arch` in output vs `--help-multiarch` in handler                 | Fixed  |
| 66  | Medium   | Help long-form mismatch: `--help-qtt-tag` in output vs `--help-qt-tag` in handler                       | Fixed  |
| 67  | Medium   | Missing case handler for `-h-bs-c` / `--help-bootstrap-cmake` — documented but does nothing             | Fixed  |
| 68  | Medium   | Qt tag filtering `sub("(.*)(-a\|-b\|-r)", "")` mangles pre-release tags instead of filtering them       | Fixed  |
| 69  | Medium   | `qbt_dl_folder_path` collapses to install dir on corrupt archive (carried from v1)                      | Fixed  |
| 70  | Medium   | fix qt apps multiarch command for qbt_host_deps                                                         | Fixed  |
| 70  | Medium   | fix tag generation with libtorrent when using master branch                                             | Fixed  |
| 71  | Medium   | script version function check will compare its sha256sum against the github hosted one                  | Added  |

### v2.2.2 - 30/08/2025

`qbt-nox-static.bash` was fully merged into `qbittorrent-nox-static.sh` so that the scripts no longer have significantly different code approaches to the same outcomes.

To maintain expected behavior I only needed to make a small adjustment to the script to make it behave the same way without having to support two versions fo the same script.

This essentially completes the transition from the legacy script to the current without any breaking changes.

fixed:

- install binary function was not working correctly and has been updated.
- fixed building glibc in debug mode due to incorrect flags
- fixed glibc utf-8 warning when building qbittorrent. install the locale C.UTF-8 from glibc source dir
- fix alpine version check properly compare versions.
- fixed boost version check that was creating a malformed url for github and beta releases.

updated:

- apply patches function is more capable now.
  - source folder has top priority
  - local patch files has next priority
  - you can now have multiple patch/diff files in the dir as well as a url file.
  - They will be merged into a single file called `patch` and applied.
  - remote that third priority and will mirror the remote to the local dir when it is treated as a local patch files.
- Download file and folder functions tweaked.
- Set -a removed.

### v2.2.1 - 13/08/2025

Debian support bumped to trixie

Debian crossbuild now supports riscv64

`cmake`/`ninja` no longer installed via external builds for any support OS. Related code and arguments removed.

They are only installed via `apt` for Debian based and `apk` for Alpine.

The reason the external tools existed was to overcome issues with outdated or missing stable release packages.

This not be an issue since `trixie` `cmake` is `3.31` or newer and `ninja-build` was reintroduced as an Alpine package some time ago. There was no specific benefit to using them other than enabling building.

This makes the `qbt-cmake-ninja-crossbuilds` and `qbt-ninja-build` redundant as the script no longer depends on them.

### v2.2.0 - 26/07/2025

Context: As the qbt-musl-cross-make toolchains were being revised to properly apply `-static-pie` patches, some issues needed to be resolved that resulted in a rework of some things.

| Status       | Component       | Link                                                                                             |
| ------------ | --------------- | ------------------------------------------------------------------------------------------------ |
| (patched)    | qBittorrent     | https://github.com/qbittorrent/qBittorrent/pull/22987                                            |
| (unresolved) | zlib-ng         | https://github.com/zlib-ng/zlib-ng/issues/1936                                                   |
| (patched)    | musl-cross-make | https://github.com/richfelker/musl-cross-make/tree/master/patches/binutils-2.44                  |
| (patched)    | musl-cross-make | https://github.com/richfelker/musl-cross-make/tree/master/patches/gcc-15.1.0                     |
| (resolved)   | openssl         | n/a - it was an issue with using `LDFLAGS=-static` which triggers unexpected behavior in openssl |

___

- Added the choice of [zlib](https://github.com/madler/zlib) and [zlib-ng](https://github.com/zlib-ng/zlib-ng), defaulting to `zlib` as `zlib-ng` has unresolved arch issues. This shows as `-motley`
- Added the ability for the script to fully cross build all dependencies without using `qemu` emulation.
  - Qemu applies when cross building building QT6 or ICU
  - `qbt_with_qemu` - default: `yes` - if this is set to `no` abd cross compiling then the modules of `icu_host_deps` `qtbase_host_deps` `qttools_host_deps` are added to the installation to bootstrap required host versions.
  - `qbt_host_deps` - default: `no` - if this is set to `yes` the script will pull in prebuilt host dependencies from here - <https://github.com/userdocs/qbt-host-deps>
- `iconv` is no longer installed when using libtorrent `v2` as it was only ever a dependency of libtorrent `v1.2`

> [!NOTE]
> `qbt_host_deps` will always be mirrored to the latest release version.

A lot of general refactoring, formatting and minor bug fixes.

More consistent use if build flags and when the are applied.
More consistent debug triggering so all parts are built in debug mode.
caching behavior tweaked - use workflow files when it can.

### v2.1.3 - 29/06/2025

problem: when the `-lt` flag was used with libtorrent `v1.2` like `-lt v1.2.20` boost was not being defaulted to `boost-1.86.0` as it does when setting the env equivalent, causing a build error when libtorrent was built.

fix: the flag now properly checks and sets boost to `boost-1.86.0` when libtorrent `v1.2` is being built via [e11d7d5](https://github.com/userdocs/qbittorrent-nox-static/commit/e11d7d51b5a0a6a99fcac6ae44c4603286e9a598)

### v2.1.2 - 18/05/2025

fix: `double_conversion` all versions - apply patch for increasing cmake bounds in `CMakeLists.txt` via this [patch](https://github.com/google/double-conversion/commit/0604b4c18815aadcf7f4b78dfa6bfcb91a634ed7)

fix: `v2.0.18` only - `qbittorrent-nox-static.sh` glibc configure flags. An argument `--enable-cet` was missing from this when backporting changes from `qbt-nox-static.bash`

### v2.1.2 - 29/04/2025

build flags: `-fcf-protection=full` (`x86_64`) and `-mbranch-protection=standard` (`aarch64`)

Don't use certain arch specific flags when cross compiling as they will not work with gcc 15 and were probably silently ignored by gcc 14 and previous.

Only use them when not cross compiling

### v2.1.1 - 18/02/2025

build flags tweaked using this information as a guide:

https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#tldr-what-compiler-options-should-i-use

Hardening is preferred over performance.

### v2.1.0 - 20/01/2025

`qbt-nox-static.bash` will be created alongside the `qbittorrent-nox-static.sh`.

`qbt-nox-static.bash` ≥ `v2.1.0`

`qbt-nox-static.bash` will start with `v2.1.0` and `qbittorrent-nox-static.sh` will be frozen at `v2.0.15` going forward. This is to avoid breaking anything by replacing `qbittorrent-nox-static.sh` with `qbt-nox-static.bash` and removing access to the old file. `v2.1.0` is not really changing the outcome but the behavior of the script towards that outcome. So the least disruptive way is the opt-in route. I also wanted to change the extension from `sh` to `bash` as it is a bash script.

There is feature parity between the two scripts as of this change. All major changes, fixes and tweaks are applied to both scripts with the exception of the reworked dependency and module installation logic which breaks expected behavior of the script.

#### Main changes

A reworked dependency and module installation logic, which has changed the default behavior of the script.

Reasoning: The script was designed to be run in a docker and needs `curl` and `git` to perform basic test functions. So it would automatically try to install all deps from a single array when run as root or with sudo to be able to then do the basic interactions. This was not ideal behavior as it would behave the same way on a host system whereas in a docker it didn't really matter. This required reworking how dependencies were checked, managed and installed.

#### Changes unique to `qbt-nox-static.bash`

- The script no longer tries to modify the host or create files if just called by its name. It will do basic dependency checks and offer options to install what's needed.
- It can now just install the required test dependencies or perform basic functions if they are already installed, meaning the basic features and help functions are usable without installing the full suite of dependencies.
- dependency specific modules new modules unique to this check: `update` | `install_test` | `install_core` | `bootstrap_deps`

Changes applied to both `qbt-nox-static.bash` and `qbittorrent-nox-static.sh`

- Removed build script support for buster, focal and jammy due to conflicts with updated build flags and will support current releases only going forward.
  - Builds are fully static so build on a modern OS to use on older systems.
  - Or use Github by forking the repo and running the workflows. You don't need to build on the target.
- Revised the optimization and build flags system to be more modern and useful, which breaks building on some older systems. Though this really only applies to debian hosts and the primary method is Alpine.
- changed: optimize still just applies `march-native` on non crossbuilds but now you can export `CFLAGS` `CPPFLAGS` `CXXFLAGS` `LDFLAGS` in the main env and they will be appended to the builds.
- fixed: optimize was not working as intended for being spelled inconsistently, optimise/optimize, so the checks for cross-building were not correct.
- all build optimization stuff moved to a unified function `_custom_flags` instead of being spread out across the script.
- Alpine only - if building using native gcc on the host it will attempt to use `-flto` - does not do this on crossbuilding as it does not work.
- General refactoring towards more consistent use of array data throughout the script with a preference towards associative arrays.
- fixed: standards checking - checks are more targeted to include os version names so as to avoid certain bad build combinations
- new: a new flag `-bs-e` that dumps a template `.qbt_env` file with all env vars that are unset then exits.
- crossbuild toolchains won't extract every time you run the script and will also now determine if you have the correct toolchains if you change the settings and not just assume.
- many consistency tweaks, minor bug fixes and streamlining of code.
- credits: Borrowed some build flags from here [qbittorrent/docker-qbittorrent-nox](https://github.com/qbittorrent/docker-qbittorrent-nox/blob/main/Dockerfile#L59-L61)

> For example: `release-5.0.3` on Debian Bullseye. Before it would have set `cxx20` and then failed when building qBittorrent. Now it won't try to build and give a warning whilst still allowing building older combos on that host.

### v2.0.15 - 20/01/2025

see `v2.1.0` changelog

### v2.0.14 - 31/12/2024

fix: libtorrent `v1.2` and boost `1.86.0` check to not ignore `RC_1_2`

fix: the `_apply_patches` function was assuming the remote default branch name of `master` which made it fail the check. It now tests for the remote default branch of a patch repo and uses that.

fix: boost source URL. jfrog source is just a problem. Script now defaults to github boost release and falls back to archives.boost.i, jfrog is purged.

fix: Some typos

### v2.0.13 - 31/12/2024

Added `qbt_build_dir` as a definable env variable. This variable is to set the build directory which defaults to `qbt-build` if unset

### v2.0.12 - 17/12/2024

Default to `boost-1.86.0` for `RC_1_2` or `v1.2.x` builds because `RC_1_2` has not been updated to support the (deprecated) features removed in `boost-1.87.0` so the build will fail.

This method allows the user to override the setting by providing a valid boost tag using `qbt_boost_tag` or `-bt`

fix: changed `-bt | --boost-version` to `-bt | --boost-tag` for consistency. It was always supposed to be `--boost-tag` since that is what we are providing and testing via this flag.

### v2.0.11 - 13/10/2024

Disable glib tests on zlib-ng <https://github.com/userdocs/qbittorrent-nox-static/pull/173>

Update contributor info

minor changes - <https://github.com/userdocs/qbittorrent-nox-static/commit/e4a674fa3832e0c0d6950539adac9d1d8d00d0e7>

### v2.0.10 - 05/10/2024

Make `cmake` the default build tool with the release of qBittorrent v5

### v2.0.9 - 14/05/2024

Change default c++ standard used for newer build combinations from 23 to 20.

### v2.0.8 - 12-04-2024

Fixed a regression with `-o` where part of the code was left in and duplicated after introducing a check for cross compilation, causing the positional parameters to be shifted twice, breaking things.

fix - <https://github.com/userdocs/qbittorrent-nox-static/commit/b51e1ef356fbdbd3f2f93f2b2a8a6279b99e5f22>

### v2.0.7 - 12-02-2024

Added: a boost download function to combine some logic around fallback URLs and minimize external calls.

Added: a check to build combos for qt + cmake to prevent env files trying to build a known bad combo.

fixed: modules check for whole word and not accept partial matches

fixed: associative arrays declared earlier and in a group to allow changing settings via functions

### v2.0.6 - 2024-01-27

New flag: `-si` / `--static-ish` for Debian, Ubuntu, and Alpine platforms. This flag disables LDFLAGS static linking, allowing the OS `libc` to be dynamically linked.

You cannot use this flag with cross compilation, only native host builds.

Tests were added for `static-ish` and `optimize` to check for bad combinations, exiting the script with a helpful reason when used in combination with cross compilation, as the build will fail.

### v2.0.5 - 23-01-2024

Codename: Copilot made me do it

- Improved readability of the colour variables used throughout the script.
- Some minor tweaks to OS detection
- Moved some things around or into their own functions and some error handling.
- Some changes to how cxx standard is handled and defined so the script will default to 23 when the conditions are met.
- minor bug fix - `qbt_libtorrent_version` displays correctly when using an RC github tag.

Support for Ubuntu Noble added - Mantic removed as it's preferred to support LTS releases

- Ubuntu Focal - Jammy - Noble
- Debian Bullseye - Bookworm

### v2.0.4 - 16-01-2024

Make sure the workflow override applies when using cached dependencies

Allow patching from a remote raw git patch via URL - a file called `url` in the patch repo for the module version that contains a URL to the raw patch
other minor tweaks and cosmetic changes

### v2.0.3 - 27-12-2023

Fixed a regression from the V2 update where the host arch for `zlib-ng` was incorrectly set to `x86_64`, regardless of the actual host arch, when building on a non `x86_64` host to the same target arch (not cross building).

<https://github.com/userdocs/qbittorrent-nox-static/issues/131>

### v2.0.2 - 26-05-2023

Set `ICU` default to `no`. It does not need to be forced to on as there is no longer a related bug and it also makes more sense when considering the `-i` toggle.

### v2.0.1 - 15-05-2023

Bug fix: `skip_icu` was being unset and defaulting to no. It is no longer unset and if set to skipped when using the module directly will still skip it.

### v2.0.0 - 03-04-2023

There have been various breaking changes in the supporting architecture that affect the script and require updating to v2.0.0 from v1.1.0 or earlier.

A lot of changes and tweaks to workflows and supporting repos to make sure things are as size efficient as they can be. For example, gz to xz where possible.

Alpine Crossbuild tools are 70% reduced in size.

The script can now build for these arches using musl or debian though workflows and releases may not target them all yet.

armel armhf armv7 aarch64 x86_64 x86 s390x powerpc ppc64el mips mipsel mips64 mips64el riscv64

v2 is is an overhaul that aims to be more sensibly coded and and use associative arrays to handle the URL data properly. Less obfuscated and consistent in how it uses this data.

docs to be updated soon.

A quick summary of main changes and features from v1.5.0 through vto 2.0.0

- No more bison or gawk building. They are OS dependencies now and need to be installed on the host.
- Alpine only - Increased multiarch target support, updated musl cross tools and optimised size.
- A caching mechanism for files to store and manage download dependencies to avoid re-downloading them across builds.
- Any valid boost tag can be provided including beta tags. It was not a tag based check before.
- Any valid qt tag can be provided including beta tags.
- patches system reworked to allow patching any module. Source code files can also be used from app_version/source
- Improved the way tags are checked and the changes applied to be more consistent throughout the script.
- Removed any trace of gnu.org for being a really unreliable source location.
- optimised multiarch configurations and multiarch various bug fixes.
- Alpine only - Ninja is now prebuilt instead of locally built.
- All url data can be viewed using the -sdu switch.
- Lots of small tweaks, removing code and simplifying code and rebuilding functions.

### v1.1.0 - 18-03-2023

Breaking changes: -bv 1.81.0 have been replaced with -bt boost-1.81

Reason: This check is now very similar to the -lt and -qt switches to it makes sense to bring it inline with how those are used.

Changes:

The script has gone through a general refactoring with many code optimizations, simplifications and improvements starting from v1.0.6.

Features:

Caching and cache management via -cd

Tag switches are more versatile in how they select source files based on tag input. Trying to use archives first but automatically falling back to folders when required.

More env options introduced to make setting most dynamic features available via env settings.

New switch options added.

### v1.0.6 - 07-03-2023

Lot of tweaks and changes.

cache files method is now integrated into the script as a result of the URL function changes.

Refactored URL function. It now uses associative arrays to hold the data for URLs, tags and versions. This makes the data more structured and easier to use consistently throughout the script.

Changed all instances of echo -e to printf %b

Added a method to using an existing local git repo as a cached source. It will clone a folder with the matching app name in the cache path provided and clone, if it exists.

It will respect manually specified tags and checkout those from the clone folders.

The lowercase naming convention of the applications must be used in the cache_path/folder_name like cache_path/qbittorrent

It must be a git repo

### v1.0.5 - 06-03-2023

Modified the default behavior of the Debian installation to not build gawk and bison by default. It will now install them via apt-get.

There is a new switch -dma which will trigger the alternate mode and instead build gawk and bison from source.

### v1.0.4 - 19-01-2023

Changed: Dropped build support for older Buster-Bionic since they require a more modern gcc version to successfully build natively. Successful builds on a modern OS can be used there instead.

### v1.0.3 - 15-07-2022

Fixed: build - Libtorrent using b2 had checks against supplied tags to do version specific things that failed to match properly when using a pull request tag or non versioned branch. It now always check the version.hpp to determine the version in these build checks.
