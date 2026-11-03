[Wiki](../index.md) › [Runtime](index.md)

# Faults and test failures reach the CLI as a record

Decision: a fault or failed test is reported to the CLI as a structured `Record` (`ms-rt-abi/src/record.rs`: kind code, message, frames, cleanup faults, test site) written to the file `MS_FAULT_RECORD` names, tagged with the writer's pid. The human text on standard error is unchanged and is never parsed. A new fault family is a `FaultKind` and a `fault_kind(...)` call at the entry point that raises it, not a substring test on the message.

A failed `expect_*`/`fail` carries its `file:line:column` in `Error.details["site"]`, so wrappers that rebuild an error (a property check) pass `details` on instead of the runtime matching messages. The test runner reports through `msrt_test_failure(message, details)`.

Apply when: adding a fault, changing the fault report, or touching `ms test` result handling. Keep `MS_FAULT_RECORD` unset for nothing else; a nested program inherits it, which is why the CLI ignores a record whose pid is not the child's.
Evidence: [record](../../crates/ms-rt-abi/src/record.rs), [runtime writer](../../crates/ms-rt/src/fault.rs) (`fault_kind`, `write_record`), [CLI reader](../../crates/ms-cli/src/fault.rs), [test failure site](../../crates/ms-lower/src/testing.rs).
