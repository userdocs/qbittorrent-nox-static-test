# AI Technical Instructions for This Repo

## Core Standards
- **Precise & Minimal**: Only implement what is requested. No broad refactors.
- **Context Awareness**: Reference `MEMORY.md` for project history. **Update `MEMORY.md` with a summary after completing any significant task.**
- **No Pandering**: Skip agreeable filler text. Focus on the solution.
- **Privacy**: Never include secrets, tokens, private URLs, or personal info in updates. Use placeholders like `[OWNER]/[REPO]` if needed.
- **C-Style Mindset**: Prioritize stability, conciseness, and thoughtful design.

## Bash Scripting
- **Standard**: Always use `#!/bin/bash`.
- **Extension**: `.bash` for Bash; `.sh` for POSIX.
- **I/O**: Use `printf`. **Avoid `echo`.**
- **Quoting**: Quote all variables (`"$var"`).
- **Naming**: Lowercase for script-local variables; UPPERCASE for ENV/Docker settings.
- **Reliability**: Explicit error checks; avoid global `set -e`.
- **Formatting**: Google Shell Style Guide.

## Repository Knowledge (`qbittorrent-nox-static`)

### Toolchain & Linking
- **Flags**: Use both `-static` and `--static`.
- **LTO & Linker**:
  - `userdocs/musl-cross-make` is designed for LTO (`-flto`) and `mold`.
  - **Build Script**: Use `qbt_linker_mold=yes`.
  - **Raw Toolchain**: Use `-fuse-ld=mold`.
- **LDFLAGS**: Apply linker options only during the final link phase.

### OS & Architecture
- **Detection**: `source /etc/os-release`.
- **Arches**: Handle `armhf` differences (Debian armv7 vs Alpine armv6).

## GitHub Workflows
- **Needs**: Job dependencies must be declared in `needs` to access outputs.
- **CLI Usage**:
  ```bash
  run_id=$(gh run list --workflow ci-alpine-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
  gh run watch "$run_id"
  ```

---

## Meta
- Consult https://mywiki.wooledge.org and https://mywiki.wooledge.org/BashFAQ.
- Format with `shfmt -s -bn -ci -sr -i 0`.
