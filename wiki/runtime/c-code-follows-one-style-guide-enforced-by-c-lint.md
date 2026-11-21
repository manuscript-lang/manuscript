# C code follows one style guide, enforced by `make c-lint`

Decision (Chinmay, 2026-11-20): "write extremely readable and idiomatic c, use all the levers that c allows for writing good safe code". The rule is `documentation/contributing/c-style.md`.

Rules: pointers travel as `MsBytes` spans and sizes go through `ms_size_add`/`ms_size_mul` (`src/runtime/include/ms_rt/safe.h`); fallible functions return `bool` or a status with `MS_NODISCARD`; one owner per allocation, stated in comments; no mutable globals. `make c-lint` runs the warnings in `toolchain/c-warnings.txt` as errors on every C file and clang-tidy (`.clang-tidy`) on changed files in the PR job "Language checks" and on all files nightly (`c-safety`).

Failure mode: C written before the guide did not pass (40 of 59 files on 2026-11-20, mostly missing prototypes, const casts, alignment casts). Those files are listed in `toolchain/c-lint-pending.txt`; a listed file that passes must be removed, a new file is never added. The owning thread brings its files up to the guide.

Apply when: writing or reviewing any C. Silence a check only on one line with `// NOLINT(<check>): <reason>`.
