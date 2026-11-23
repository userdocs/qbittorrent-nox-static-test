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

## Recent Changes (2026-11-23)
- **v2.2.6 audit** (squashed commit with `qbt-nox-static.bash`, `tests/unit_tests.bash`, `changelog.md`): every changelog claim was checked against the old script; severities and reasons were rewritten, unlisted behaviour changes documented, and no-op/duplicated code removed (`https.proxy` git key, `|| true` without `set -e`, duplicated `_set_build_directory` normalisation, redundant `qbt_use_qt6`).
- **Unit tests**: `bash tests/unit_tests.bash` (offline, ~15 s; needs `git`, `jq`, `patch`). The suite extracts the function library with `awk` and sources it inside functions, so global arrays must be declared with `declare -gA`, and it runs with `set -o pipefail`, so helpers must not depend on the exit status of `tar tf | awk '...exit'` pipelines (SIGPIPE).
- **Regression guards added** for: non-root without sudo and all deps present, relative `install custom` paths never using privileges, `_get_archive_dir_name` under `pipefail`, and cached repos surviving patches (sentinel file, because delete-and-reclone also recreates the directory).

## Technical Notes From The Audit
- `_semantic_version` must strip tag prefixes (`release-`, `boost-`, ...): without it `release-5.1.0rc1` or `boost-2.1.0.beta1` rank above the final release.
- `-cd <dir> rm` refuses `$HOME`, `$PWD`, the script directory, `/` and `.`/`..` after `readlink -f`; success exits `0`.
- `_install_qbittorrent custom` only uses privileges for absolute paths outside `$LOCAL_USER_HOME`; relative paths stay user-owned; `..` is rejected.
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
