# Project Memory: qbittorrent-nox-static

This file serves as a persistent context log for AI assistants to understand the current state, recent decisions, and technical constraints of the repository.

## Project State
- **Focus**: Building and distributing high-performance, statically linked `qbittorrent-nox` binaries.
- **Current Milestone**: Harmonizing AI configurations and optimizing toolchain linking (LTO/mold).

## Key Technical Decisions
- **Toolchain**: Using `[OWNER]/musl-cross-make` which is dynamically linked and designed for LTO and the `mold` linker.
- **Static Linking**: Always use both `-static` and `--static` to ensure all dependencies (including POSIX threads) are correctly captured.
- **Linker Logic**:
    - Build Script (`qbt-nox-static.bash`) uses `qbt_linker_mold=yes` to handle flag generation.
    - Raw Toolchain requires `-fuse-ld=mold`.
- **Mindset**: "C-like" development—prioritize stability, explicit error handling, and minimal external dependencies.

## Recent Changes (2026-11-28)
- **v2.2.6 security & reliability audit** (`qbt-nox-static.bash`, `tests/unit_tests.bash`, `changelog.md`):
    - Added `[[ ${BASH_SOURCE[0]} == "${0}" ]]` guards around all four top-level execution blocks and isolated `get_os_info` in a `set +u` subshell so `qbt-nox-static.bash` can be sourced and double-sourced under `bash -ec` / `bash -eu` without mutating `PWD`, `IFS`, or `LC_ALL`.
    - Hardened `_install_qbittorrent` (refusing a symlinked/non-regular destination binary so `cp -f` under `sudo` cannot write through it), `_check_dependencies` (requiring `Status: install ok installed` from `dpkg -s` so removed `deinstall ok config-files` packages are not treated as installed), `_write_qbt_env_template` (pure-Bash serialization escaping `\`, `"`, `$`, `` ` `` so values incl. newlines round-trip), `_download_file` and `_multi_arch` (`.tmp` staging preserving prior cached archives on download failure), `-cd <dir> rm` (handling read-only cached subtrees and checking `rm -rf` exit status), `_apply_patches bootstrap` (preserving `qbt_modules_install[all]` so `-bs-p all` and `-bs-a all` succeed), `_validate_github_repo`, segment-exact `_validate_path`, `_git -t` (`\` wildmatch escape rejection), and `patch --batch --forward --dry-run` rollback protection.
- **Unit tests**: `bash tests/unit_tests.bash` (offline, 948 assertions across 18 sections, ~15 s; needs `git`, `jq`, `patch`). Sources `qbt-nox-static.bash` directly via its `${BASH_SOURCE[0]}` guard (`declare -gA` maps allow sourcing inside functions), enforces expected exit codes inside every output assertion helper (`assert_pass_eq`, `assert_contains`, `assert_not_contains`, `assert_match`, `assert_fail_contains`, `assert_fail_not_contains`), and runs with `set -o pipefail` (so `_get_archive_dir_name` does not rely on `tar tf | awk '...exit'` SIGPIPE pipeline status).
- **Regression guards** cover: unprivileged builds when all deps are present, `dpkg` `deinstall ok config-files` rejection, `_install_qbittorrent` symlink-overwrite refusal and relative `install custom` privilege scoping, escaped `-bs-ef` `.qbt_env` round-trips, `_get_archive_dir_name` under `pipefail`, cached archives/repos surviving failed downloads, patches, and advancing shallow branches, non-interactive patch dry-run rollback, `-bs-p all`, and `bash -ec` double-sourcing.

## Technical Notes From The Audit
- `_semantic_version` strips tag prefixes (`release-`, `boost-`, `openssl-`, `libtorrent-`, `libtorrent_`, `glibc-`) and matches `^([0-9]+([._-][0-9]+)*)` in pure Bash so dash-delimited prereleases (`release-77-1-rc1`, `boost-2.1.0.beta1`) rank below final releases.
- `-cd <dir> rm` resolves paths via `_resolve_path` and refuses `$HOME`, `$PWD`, the script directory, any ancestor directory of those three, `/`, `.`/`..`, and existing regular files; success exits `0`.
- `_install_qbittorrent custom` resolves nested non-existent targets via `_resolve_path` and only uses privileges for absolute paths resolving outside `$LOCAL_USER_HOME`; relative paths stay user-owned; `..` path segments are rejected.
- `*_host_deps` builds (`qbt_with_qemu=no`) must use `/usr/bin/gcc` + host LTO wrappers and scope `-I`/`-L` to `${qbt_host_deps_path}/{include,lib}` rather than target `${include_dir}`/`${lib_dir}`.
- Git proxy: only `http.proxy` and `http.<url>.proxy` exist; `https.proxy` is not a git key.
- CI lint is `shellcheck --severity=warning` plus `shfmt -ci -sr -i 0`; optional checks such as SC2250 are not enforced. Debian/Ubuntu fixes (`-B${lib_dir}`, no `-fno-plt` for glibc) are validated by the 24-job Debian build matrix, not by the unit tests.

## Recent Changes (2026-04-25)
- **AI Config Harmonization**:
    - Updated `CLAUDE.md`, `.github/copilot-instructions.md`, and created `.cursorrules`.
    - Stripped "fluffy personas" in favor of strict technical instructions.
    - Synchronized OS/Arch detection logic and toolchain linking rules across all AI tools.
- **Linker Clarifications**: Corrected the documentation to reflect that `gold` is disabled in the toolchain and that `mold` requires explicit activation via `-fuse-ld=mold`.

## Known Gotchas & Constraints
- **I/O**: Never use `echo`; always use `printf '%s'` or `printf '%b'`.
- **Variables**: Lowercase for script-local logic; UPPERCASE for exported ENV/Docker settings.
- **Arch Mapping**: `armhf` is `armv7` on Debian/Ubuntu but `armv6` on Alpine.
- **OS Detection**: Must `source /etc/os-release` and check `ID` or `ID_LIKE`.
- **LTO Wrappers**: For LTO, use `gcc-ar`, `gcc-nm`, and `gcc-ranlib` to ensure symbol table integrity.
- **Privacy**: Use `[OWNER]/[REPO]` placeholders in documentation to prevent leaking specific paths.

## Pending Tasks
- [ ] Monitor CI performance with LTO and mold enabled.
- [ ] Verify `qi.bash` installer behavior on all supported architectures.
