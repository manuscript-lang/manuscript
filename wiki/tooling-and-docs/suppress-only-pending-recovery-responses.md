[Wiki](../index.md) › [Tooling and docs](index.md)

# Suppress only pending recovery responses

Verified: filtering every reply with a private replay ID also hides ordinary client replies with that valid string ID, even before a crash. Response suppression must apply only to the pending private initialize answer, then clear before forwarding later replies. This is a response-routing rule, not isolation of the transport's cancellation IDs.

Replay text and versions must follow the worker's accepted-edit rules. Empty or missing `contentChanges` must preserve the cached version as well as the text; otherwise the replay copy can reject a subsequent edit that the worker accepts. The supervisor's `empty_changes_preserve_replay_version_and_later_edits` unit test pins this boundary.

Apply when: changing supervisor restart, replay, or response forwarding.
Evidence: [supervisor](../../crates/ms-lsp/src/supervise.rs), [regressions](../../crates/ms-lsp/tests/supervise.rs), [issue #3262](https://github.com/manuscript-lang/manuscript/issues/3262).
Verify: the client receives a response with the replay's ID both without a restart and after recovery; the private initialize response stays hidden.
