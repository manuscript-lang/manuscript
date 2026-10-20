# DWARF line-table validation

The backend now emits DWARF4 `.debug_line`, `.debug_info`, `.debug_abbrev`, and
`.debug_ranges` from Cranelift's final source spans. CU statement-list/range
metadata lets native address consumers locate each function's line program.
ELF/COFF addresses relocate against function symbols; Mach-O uses local text-section
relocations with each function's offset in the stored addend, matching LLVM's
assembler and allowing object consumers to distinguish functions before linking.
Offsets into debug sections relocate against their section symbols. Runtime `ms.tables` contents and fault-frame
behavior remain independent.

Known spans end at their actual code end. An unknown location, invalid file, or
gap ends the sequence; the next known location starts another sequence. This
prevents a previous source line from extending into unrelated code. Optimized
instructions retain the file/line of the originating inlined source operation.
Columns, variables, source-language types, inline frame DIEs, unwind information,
breakpoint behavior, and full debugger support are not provided by this change.

## Initial consumer evidence

Linux x86_64 ELF, Rust 1.99.1 / Cranelift 0.136.0, GCC 14.2.0, GNU binutils 2.44.
`cargo test -p ms-clif --test dwarf -- --nocapture` exercises:

- MIR+CLIF unoptimized and optimized (`speed`) code.
- Relocatable objects and linked PIE executables, with actual relocated addresses.
- Several functions and files, duplicate basenames, absolute paths with spaces,
  relative paths, and optimized inline-origin file/line attribution.
- A real internal valid → unknown → invalid-file → valid instruction interval:
  an interior address has no source line; the later address resumes at line 40
  of its correct file. Function boundaries also stop attribution.
- Unknown source locations and absent/empty/NUL file paths emit no invented lines.
- Identical object bytes when compiled twice in the same working directory.
- Executable output and exit status, alongside `readelf`/`addr2line` assertions.

The `*-lines.txt` and `*-addresses.txt` files retain consumer output for both
optimization settings (`false` = unoptimized, `true` = optimized) and both artifact
types. `object-sections.txt` records emitted sections and relocations. Addresses
are example artifact addresses, not portable constants. Temporary source paths
include the test process ID; tests recreate their fixtures.

For example, in the optimized executable, line 70 of `inline/origin.ms` resolves
inside `first`, followed by line 12 of the absolute source path. An internal
unmapped interval separates that from line 40 of `relative/nested/first.ms`.
Binutils may return its object-file name with `:?` for an unmapped address;
the test requires an unknown line rather than a particular fallback filename.

The initial evidence above covers Linux x86_64 only. Byte determinism is within one working directory; the
compilation directory is deliberately embedded for relative source resolution.

## Native-platform validation gate

The portable tests use LLVM `llvm-dwarfdump` and `llvm-symbolizer` without platform
skips. Linux x86_64 with LLVM 19 passes both optimization levels on objects and
linked executables, including unknown intervals and actual source-file paths.
`final_build_keeps_source_lines_after_staging_and_object_cleanup` also passes
Debug and Release through `ms_driver::build_executable`, replaces an existing
output, and queries the final executable after its staged object is deleted.
Consumer tests use ordinary adjacent dSYM discovery without a hint. Publication
normalizes the inner DWARF filename to the final executable's basename, as required
by [LLVM's lookup](https://github.com/llvm/llvm-project/blob/main/llvm/lib/DebugInfo/Symbolize/Symbolize.cpp).

The strict native CI matrix covers Linux, macOS, and Windows on amd64 and arm64.
All six jobs must pass before merge; their results are pending at publication.
The macOS jobs exercise the product's `dsymutil` companion creation and staged
publication, including rollback and retiring an obsolete companion. Windows jobs
exercise native clang/lld linking with `/debug:dwarf`. These are test requirements,
not claims that those targets have passed. Consumer output and generated artifacts
are uploaded per native target. LLVM tools are required; a missing consumer fails
the tests. No full debugger support follows from line-table validation.

A supplemental Linux-hosted x86_64 object probe selected ELF, COFF, and Mach-O ISAs
in a scratch copy of the backend. LLVM 19 verified all three formats. It exposed
overlapping zero-address Mach-O function ranges with external debug relocations;
local section relocations plus stored function offsets fix the verifier and let
LLVM symbolize both functions' distinct source lines. This probe does not link or
execute on macOS/Windows and does not establish native target coverage.

## Checks and review

Passed: full `cargo test -p ms-mir -p ms-clif` (76 tests, including real runtime
faults, six kernels, random-program differential tests, and new regressions);
`cargo test -p ms-driver` (4 tests); fmt; clippy with warnings denied;
`make repo-check`. An independent Sol reviewer approved the implementation after
checking file identity, symbol/section relocation, span gaps, optimized mapping,
runtime-table isolation, and the added internal-gap regression.

Overflow and DWARF are delivered separately. The DWARF draft depends on the
overflow draft so the platform-test harness is shared without duplicating it.
