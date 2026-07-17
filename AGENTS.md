# Repository instructions

## Workflow

- Never commit directly to `master`.
- Confirm the working branch with the user at the beginning of a coding session.
- Once confirmed, work on that branch without further approval.
- Do not create, switch, merge, rebase, or delete branches without approval.
- Commits and pushes on the confirmed working branch do not require approval.
- Preserve existing behavior unless the task explicitly changes it.
- Keep code comments in English.
- Do not modify unrelated user changes.

## Project areas

- `lemonbar/` contains the Bash implementation.
- `lemonbar_c/` contains the C17 implementation.
- Treat the Bash implementation as a behavioral reference and fallback.
- Follow additional instructions from nested `AGENTS.md` files.
- Do not run the Bash and C panels simultaneously during visual tests.

## Shell development

For changed shell scripts:

- Run `bash -n` on every changed shell script.
- Run `shellcheck` on every changed shell script.
- Run `git diff --check` before committing.

## C development

The C project uses:

- C17
- CMake and CMake presets
- CTest
- GCC and Clang
- clang-format
- clang-tidy
- AddressSanitizer and UndefinedBehaviorSanitizer
- Docker or rootless Podman
- Xvfb for automated X11 integration tests

Follow `lemonbar_c/AGENTS.md` for detailed C and container rules.

For normal C changes, use the reproducible container workflow:

    ./lemonbar_c/scripts/container-build.sh

This command is expected to run:

- clang-format validation
- clang-tidy
- native release compilation
- CLI-only compilation without XCB
- CTest
- ASan/UBSan tests
- automated X11 tests under Xvfb

Set `CONTAINER_ENGINE=podman` when rootless Podman should be used instead of
Docker.

A local build may be used for quick iteration:

    cmake -S lemonbar_c -B build/lemonbar_c \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo
    cmake --build build/lemonbar_c --parallel
    ctest --test-dir build/lemonbar_c --output-on-failure

The container build remains the authoritative validation before committing C
changes.

## Tool usage

Prefer these tools where appropriate:

- `rg` for searching files and source code
- `clang-format` for C formatting
- `clang-tidy` for static C analysis
- `cmake` for configuring and building the C project
- `ctest` for C test execution
- `shellcheck` and `bash -n` for shell validation
- Docker or rootless Podman for reproducible builds
- Xvfb for automated X11 tests
- `git diff --check` for whitespace validation

Use runtime tools such as `xprop`, `xrandr`, `xdotool`, `xwininfo`, `bspc`,
`pactl`, `nmcli`, `ps`, and `strace` only when relevant to integration testing
or runtime diagnosis.

## Validation and reporting

- Run checks appropriate to every changed file type.
- Report exactly which checks were run and whether they passed.
- Report checks that could not be run and explain why.
- Do not claim that a runtime or visual test passed unless it was actually run.
- Keep build artifacts outside source directories.
