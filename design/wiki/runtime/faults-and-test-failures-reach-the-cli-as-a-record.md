[Wiki](../index.md) › [Runtime](index.md)

# Faults and test failures reach the CLI as a record

Decision: a fault or failed test is reported to the CLI as a structured `Record` (`src/runtime/core/record.c`, read by `src/cli/fault_record.c`: kind code, message, frames, cleanup faults, test site) written to the file `MS_FAULT_RECORD` names, tagged with the writer's pid. The human text on standard error is unchanged and is never parsed. A new fault family is a fault kind in `src/abi/fault.h` and a call at the entry point that raises it, not a substring test on the message.

A failed `expect_*`/`fail` carries its `file:line:column` in `Error.details["site"]`, so wrappers that rebuild an error (a property check) pass `details` on instead of the runtime matching messages. The test runner reports through `msrt_test_failure(message, details)`.

Exit status (2026-11, Chinmay's request "change 67 to the one C uses"): a fault exits as a C program does, through `src/abi/fault.h`: 134 (shell status of `abort`), 139 for `StackOverflow` and `OutOfMemory` (SIGSEGV), on every platform: Windows' own abort status 3 would collide with a `main` that returns 3, and the NT codes would make recorded conformance expectations differ per platform (the first Windows run failed 30 fixtures on exactly that). The process still calls `_exit`, never raises the signal, so there is no core dump, no macOS crash report and no Windows error dialog. The CLI recognises a fault by its fault status plus the record, and `main` returns at most 125, so no program status collides. Never hard-code a fault status in a test: use `MS_EXIT_ABORT` and its siblings in `src/abi/fault.h`.
Out of memory: an allocation the system refuses takes the full fault path (kind out of memory, source frames, cleanups). Reporting can itself need memory, so a nested failure falls back to a bare message with no frames, and the flag is cleared when a report finishes (`src/runtime/core/fault.c`). The kernel OOM killer after overcommit cannot be reported.

Apply when: adding a fault, changing the fault report, or touching `ms test` result handling. Keep `MS_FAULT_RECORD` unset for nothing else; a nested program inherits it, which is why the CLI ignores a record whose pid is not the child's.
Evidence: record, runtime writer (`fault_kind`, `write_record`), CLI reader, test failure site.
