[Wiki](../index.md) › [Tooling and docs](index.md)

# Readable formatting needs paragraphs while retaining inline guards

Decision: the user's formatter request keeps inline `if` bodies and introduces natural reading boundaries around declarations, guard sections, substantial control flow. Later feedback in [issue #102](https://github.com/manuscript-lang/manuscript/issues/102) requested authored spacing between match arms and compact short lists and callback signatures. The latest user direction supersedes authored spacing: discard authored blank lines and derive paragraphs from syntax.

Apply when: changing source formatting or adding layout heuristics.
Evidence: [formatting policy](../../documentation/developer-tooling/implementation.md#linting-and-formatting), [formatter](../../crates/ms-syntax/src/format.rs), [formatter CLI tests](../../crates/ms-cli/tests/fmt.rs), [format corpus](../../crates/ms-syntax/tests/data/format).
Verify: setup stays with its immediate uses and simple return; guards stay attached to setup and following work starts a paragraph; section comments stay attached to their code and substantial callbacks get their own paragraphs; branch families remain together; LF/CRLF output preserves literal spellings and is identical after a second format. Outdented comments must not set the code indentation baseline: [binding-group regressions](../../crates/ms-syntax/tests/format_comments.rs) preserve entries and comments independently.
