+++
title = "C style and safety"
weight = 23
+++

# C style and safety

The runtime (`src/runtime/`) and the compiler core (`src/compiler/`) are C. This page is the rule for every line of it. The aim is code a reader can check by eye and a compiler can check by machine: make the wrong program fail to compile, then fail a test, before it can fail a user.

`make c-lint` enforces what a tool can enforce, on every pull request. `make c-test` runs the unit tests under AddressSanitizer and UndefinedBehaviorSanitizer and `make c-fuzz` fuzzes the parsers; run both before pushing C, since CI runs them nightly, not per pull request.

## Language

- C11, no extensions beyond the attributes and builtins that both clang and gcc accept. Attributes are written only through the `MS_` macros in `ms_rt/safe.h`, so one line changes if a compiler differs. `__builtin_` functions are allowed where a freestanding file has no header for the operation.
- The build sets `-fno-strict-aliasing`, so the compiler assumes nothing from pointer types; write as if it did anyway and move bytes with `memcpy`.
- The runtime switches task stacks itself, so it is built with `-fno-stack-protector`; guard pages under each stack catch overflow instead.
- No `__attribute__((cleanup))`: cleanup is visible code.
- `src/runtime/sys` and `src/runtime/core` are freestanding: they include only `stdint.h`, `stddef.h`, `stdbool.h` and runtime headers.
- No variable-length arrays, no `alloca`, no `goto` except one forward jump to a single cleanup label, no `setjmp`, no recursion without a depth limit the code states.
- No function-like macro where a `static inline` function works. A macro that remains evaluates each argument once.

## Names and layout

- Types are `MsUpperCamel`. Functions and variables are `lower_snake`. Constants and macros are `MS_UPPER_SNAKE`.
- A function visible outside its file starts with `ms_` and its module (`ms_http1_parse`, `ms_bytes_slice`); one that programs call across the ABI keeps its recorded `msrt_` or `msstd_` name. Everything else is `static`. Enum constants are `MS_UPPER_SNAKE`.
- A header declares what other files need and nothing else. It compiles on its own, and a struct other files need not look into is declared opaque (`typedef struct MsThing MsThing;`).
- Spell words out: `length`, `capacity`, `index`, `buffer`, not `ln`, `cp`, `i2`, `bf`. `i`, `n` and `p` are fine in a loop of a few lines, and `ptr` and `len` are the field names of every span.
- One declaration per concept. Declare a variable where it gets its value, and make it `const` when it never changes.
- A file starts with a comment saying what the module does and what it owns. A function gets a comment when its name and types do not say everything: who owns what it returns, what a false result means, what it requires of its arguments.
- Functions fit on a screen (the gate fails past 80 lines). When a function needs a comment to separate its phases, the phases are functions.
- Braces on every multi-line body. An early return on one line may go without. No nested conditional operators.

## Ownership

Manuscript's rule holds in the C too: every allocation has one owner.

- A function that returns allocated memory says so in its name (`_new`, `_create`, `_clone`) and has a matching `_free` or `_destroy`. Its comment names the owner.
- A pointer parameter is borrowed for the call unless the comment says "takes ownership".
- A struct field that owns memory is marked `/* owned */`; one that borrows is marked `/* borrowed from <whom>, valid until <when> */`.
- After a free, the owning field is set to null in the same statement block.
- Cleanup runs in reverse order of acquisition through one exit path.

## Errors

- A function that can fail returns `bool` (true is success) or a named status enum, and writes its result through an out parameter. It carries `MS_NODISCARD`, so ignoring the result does not compile.
- On failure the out parameter is left untouched and nothing is leaked.
- No sentinel values mixed into a result (`-1` as a length, null meaning two things). `SIZE_MAX` for "absent" is allowed only where the ABI already records it.
- Faults a program can observe go through the runtime's fault record with the statuses in `ms-rt-abi`. No literal exit status. No `abort()` or `assert()` for a condition input can cause.
- `_Static_assert` states every layout the compiler or the ABI depends on: struct sizes, field offsets, enum ranges.

## Bounds and arithmetic

- A pointer travels with its length. That is an `MsBytes` or `MsBytesMut` from `ms_rt/safe.h` (the compiler core includes it with `-Iruntime/include`), read with `ms_bytes_get`, `ms_bytes_slice` and `ms_bytes_copy`, which check every index. The ABI still passes `(pointer, length)` pairs; wrap them at the entry point.
- Sizes are `size_t`. Every addition or multiplication of sizes that input can influence goes through `ms_size_add` and `ms_size_mul`. `count * sizeof(T)` is always `ms_size_mul`.
- Indices and counts are `size_t`; a pointer difference is checked to be non-negative before it becomes one.
- No signed overflow, no shift by a value that can reach the type's width, no narrowing without a range check on the line above.
- Small unsigned types promote to `int`: `(uint32_t)byte << 24`, not `byte << 24`, and widen before multiplying two `uint16_t`.
- A `switch` that must handle every value of an enum has no `default`, so adding a value fails the build.
- No `strcpy`, `strcat`, `sprintf`, `gets`, `strtok`, `atoi`. Use lengths: `memcpy` after a bounds check, `snprintf` with its result checked.
- No cast that removes `const`, and none between unrelated pointer types. Reading a wider value from bytes is a `memcpy` into a local, never a pointer cast.
- Pointer parameters that must not be null carry `MS_NONNULL`.
- No uninitialised locals: initialise at the declaration, structs with `{0}` or designated initialisers.

## State

- No mutable global or `static` variable outside the few the runtime design names (per-thread scheduler state). The compiler library has none at all.
- Data another thread can touch is `_Atomic` or guarded by one named lock, and the field's comment says which. No libc function that keeps hidden state (`strtok`, `localtime`, `getenv` after start-up).
- No initialiser that runs before `main`.
- Layering is by directory: `sys` under `core` under `io` under `net` and `std`. System calls only in `src/runtime/sys`, libuv only in `src/runtime/io`, OpenSSL, llhttp and nghttp2 only in `src/runtime/net`, and each other library only in its own `src/runtime/std/<module>.c`.

## Shared helpers: where to find what

One copy of each helper, in `src/runtime/include/ms_rt/`, usable from `src/runtime/` and `src/compiler/` (the compiler core includes it with `-Iruntime/include`). Search here before writing a helper, and add to the matching header, never a local copy. Where libc or a library we already link (libuv, OpenSSL, PCRE2, zlib) provides the operation, call it; the helpers below exist only where libc cannot serve: freestanding runtime code, or locale-dependent `<ctype.h>`.

| Need | Header | Names |
| --- | --- | --- |
| Checked sizes, spans, word loads, attributes, span prefix, suffix and plain find | `safe.h` | `ms_size_add`, `ms_size_mul`, `MsBytes`, `ms_bytes_of`, `ms_load64`, `ms_load32`, `ms_bytes_equal`, `ms_bytes_starts_with`, `ms_bytes_ends_with`, `ms_bytes_find` |
| ASCII class and case (locale-free), hex digits, UTF-8 encode, continuation byte | `chars.h` | `ms_ascii_is_digit`, `ms_ascii_is_alpha`, `ms_ascii_is_ident`, `ms_ascii_is_hex`, `ms_ascii_to_lower`, `ms_ascii_equal_fold`, `ms_hex_digit_value`, `ms_utf8_encode`, `ms_utf8_is_continuation` |
| UTF-8 decode, scalar count, Unicode white space | `utf8.h` | `ms_utf8_decode`, `ms_utf8_count`, `ms_utf8_is_space` |
| Byte and substring search | `search.h` | `ms_find`, `ms_needle_find`, `ms_count` |
| Number to text | `fmt.h` | `msrt_fmt_u64`, `msrt_fmt_i64`, `msrt_fmt_float` |
| String values: build, copy, release | `string.h`, `strbuild.h` | `ms_str_release`, `ms_str_from_bytes`, `ms_copy_bytes` |
| Whole file into memory (dump tools) | `src/compiler/tools/read_file.h` | `read_whole_file` |
| Line protocol of the dump tools: tab fields, one request per line | `src/compiler/tools/dump_io.h` | `split_fields`, `read_line`, `str_of`, `number_of`, `put_text`, `ends_with` |

## What the tools check

| Tool | Where | What |
| --- | --- | --- |
| Warnings in `toolchain/c-warnings.txt`, as errors | every C file, every pull request | conversions, sign changes, shadowing, missing prototypes, VLAs, format strings, const casts, alignment casts, fallthrough |
| clang-tidy with `.clang-tidy` (bugprone, cert, clang static analyzer, misc, performance, portability, readability, thread-unsafe libc calls, close-on-exec) | changed production files on pull requests, all of them nightly | null dereferences, leaks, use after free, dead stores, unsafe calls, suspicious `sizeof`, the naming rules above, function length |
| AddressSanitizer and UndefinedBehaviorSanitizer | `make c-test`, `make c-fuzz`, nightly | out-of-bounds, use after free, overflow, bad shifts on every test and fuzz input |
| Fuzzers in `src/runtime/fuzz` | nightly | every parser of untrusted bytes has a fuzz harness |
| `-D_FORTIFY_SOURCE=2`, `-fno-delete-null-pointer-checks` | the shipped archive (fortify on glibc and macOS; musl and mingw have none) | libc calls with a known destination size are checked; a null check is never optimised away |

A check is silenced only on the one line that needs it, with `// NOLINT(<check>): <reason>`. A check is switched off for everyone only in `.clang-tidy`, with the reason beside it.

`toolchain/c-lint-pending.txt` lists the files written before this guide that do not pass yet. A listed file may fail; once it passes it must come off the list, and the gate rejects a change that adds a line, so the list only shrinks.

Not checked by a tool yet, so reviewers check them: ownership comments, the layering of includes, and code for other systems: `_WIN32` and `__APPLE__` branches and the `src/runtime/sys/darwin` and `src/runtime/sys/windows` folders (the gate runs clang on Linux). The shipped archive is still compiled with `-Wall -Wextra -Werror` only, because musl builds with gcc, whose stricter conversion warnings the pending files do not pass.

## Tests

Every C module has a `src/runtime/tests/<layer>_<module>.c` or a compiler test that runs under the sanitizers. A bug fix adds the input that failed. Code that parses bytes from outside the process is not merged without a fuzz harness.
