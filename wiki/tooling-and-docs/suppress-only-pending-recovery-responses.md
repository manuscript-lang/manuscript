[Wiki](../index.md) › [Tooling and docs](index.md)

# Suppress only pending recovery responses

Verified: filtering every reply with a private replay ID also hides ordinary client replies with that valid string ID, even before a crash. Response suppression must apply only to the pending private initialize answer, then clear before forwarding later replies. This is a response-routing rule, not isolation of the transport's cancellation IDs.

Apply when: changing supervisor restart, replay, or response forwarding.
Evidence: [supervisor](../../crates/ms-lsp/src/supervise.rs), [regressions](../../crates/ms-lsp/tests/supervise.rs), [issue #3262](https://github.com/manuscript-lang/manuscript/issues/3262).
Verify: the client receives a response with the replay's ID both without a restart and after recovery; the private initialize response stays hidden.

Recovery snapshots must also use the worker's parameter decoder and ordered edit transaction. Treating a malformed range as an absent range saved a replacement that the worker rejected, and an empty change batch advanced only the supervisor's version ([#3415](https://github.com/manuscript-lang/manuscript/issues/3415)). Verify rejected edits preserve text and version, and accepted UTF-16 edits, full replacements and stale versions match the worker; the supervisor's document tests pin these cases.
