[Wiki](../index.md) › [Tooling and docs](index.md)

# Preserve OS argument identity before dispatch

Verified: lossy OS argument conversion can map a nonexistent byte path to a different, existing replacement-character filename, so `check` reports success for the wrong input. Reject invalid UTF-8 before dispatch rather than replacing argument bytes.

Apply when: changing CLI argument decoding or path identity.
Evidence: [entry point](../../crates/ms-cli/src/main.rs), [collision regression](../../crates/ms-cli/tests/cli_errors.rs), [argument requirement](../../documentation/developer-tooling/implementation.md).
Verify: an invalid-byte argument returns usage status 2 even when its lossy spelling exists; a genuine UTF-8 replacement-character filename remains accepted.
