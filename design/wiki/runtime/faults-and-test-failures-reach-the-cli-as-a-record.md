[Wiki](../index.md) › [Runtime](index.md)

# Faults and test failures reach the CLI as a record

Decision: a fault or failed test is reported to the CLI as a structured `Record` (`ms-rt-abi/src/record.rs`: kind code, message, frames, cleanup faults, test site) written to the file `MS_FAULT_RECORD` names, tagged with the writer's pid. The human text on standard error is unchanged and is never parsed. A new fault family is a `FaultKind` and a `fault_kind(...)` call at the entry point that raises it, not a substring test on the message.

A failed `expect_*`/`fail` carries its `file:line:column` in `Error.details["site"]`, so wrappers that rebuild an error (a property check) pass `details` on instead of the runtime matching messages. The test runner reports through `msrt_test_failure(message, details)`.

Exit status (2026-11, Chinmay's request "change 67 to the one C uses"): a fault exits as a C program does, through `FaultKind::exit_status` in `ms-rt-abi`: 134 (shell status of `abort`), 139 for `StackOverflow` and `OutOfMemory` (SIGSEGV), on every platform: Windows' own abort status 3 would collide with a `main` that returns 3, and the NT codes would make recorded conformance expectations differ per platform (the first Windows run failed 30 fixtures on exactly that). The process still calls `_exit`, never raises the signal, so there is no core dump, no macOS crash report and no Windows error dialog. The CLI recognises a fault by `FaultKind::is_fault_status` plus the record, and `main` returns at most 125, so no program status collides. Never hard-code a fault status in a test: use `ms_rt_abi::EXIT_ABORT`. The C test runtime in `ms-clif/tests/rt/testrt.c` is a separate double and keeps its own 67.
Out of memory: an allocation the system refuses calls `fault::out_of_memory(bytes)`, which takes the full fault path (kind `OutOfMemory`, source frames, cleanups). Reporting can itself need memory, so a nested failure falls back to `fatal` (bare message, no frames) through the `OOM_REPORTING` flag, cleared when a report finishes. The kernel OOM killer after overcommit cannot be reported.

Apply when: adding a fault, changing the fault report, or touching `ms test` result handling. Keep `MS_FAULT_RECORD` unset for nothing else; a nested program inherits it, which is why the CLI ignores a record whose pid is not the child's.
Evidence: record, runtime writer (`fault_kind`, `write_record`), CLI reader, test failure site.
