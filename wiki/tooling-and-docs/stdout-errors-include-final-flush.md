[Wiki](../index.md) › [Tooling and docs](index.md)

# Stdout errors include the final flush

Verified: a small buffered write may succeed until the final flush, while a large write may fail directly and leave nothing to flush. Ignoring either result can report success after losing the command's output. Track terminal write failures and the final flush centrally, preserving intentional broken pipes and existing nonzero statuses.

Apply when: changing CLI output buffering, rendering, or exit status handling.
Evidence: [output adapter and unit tests](../../crates/ms-cli/src/main.rs), [small/large output regression](../../crates/ms-cli/tests/cli_errors.rs), [command contract](../../documentation/developer-tooling/implementation.md).
Verify: on Linux, redirect small diagram and large guide output to `/dev/full`; both return 1 with a remedy, while broken-pipe and existing-status tests retain their statuses.
