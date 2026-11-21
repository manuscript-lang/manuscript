[Wiki](../index.md) › [Compiler and build](index.md)

# The C back end runs inside `ms`, and `llc` is its assembler

Verified (2026-11-20): `ms` links the C back end (`libms_backend.a`, CMake target `ms_backend`, built by `crates/ms-build/build.rs`) and calls `ms_backend_ir` and `ms_backend_tables` (`src/compiler/include/ms/emit_program.h`). It runs no helper program and no C compiler, so a build needs only the pinned `opt` and `llc`.

The fault tables are appended to the assembly text, so something must assemble text. The pinned LLVM download has no assembler and system `clang` cannot be assumed (and an older one rejects directives a newer `llc` writes, such as `.prefalign`). The assembly is therefore wrapped as an IR module of `module asm "..."` lines, one per line with `"`, `\` and non-printing bytes as `\XX`, and `llc -filetype=obj` assembles it with its own integrated assembler.

`ms_backend` leaves the project loader out (`MS_LIBMS_NO_PROJECT`): it is the only part of libms that needs POSIX, and this library also builds for a Windows host (MSVC target, as the Rust `ms` there).

Apply when: adding a step to the C build path, wanting `clang` or another tool at build time, or adding a libms source that the back end library must compile on Windows.
