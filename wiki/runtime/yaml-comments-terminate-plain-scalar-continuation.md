[Wiki](../index.md) › [Runtime](index.md)

# YAML comments terminate plain scalar continuation

Verified: removing a plain scalar's inline comment before collecting continuation lines erases its terminating boundary. The first line and every consumed continuation line must retain enough raw source to distinguish an actual comment from a literal hash. A compact mapping or nested sequence rewrites its first line; carry its raw suffix through that rewrite, using scalar offsets so Unicode keys and values stay intact. Append and consume a continued line before stopping at its comment. Flow gathering must likewise record the scalar offsets where comments were stripped: plain leaves stop there, while ordinary separation can still admit a comma, closing delimiter, or a value that has not begun. Consume those sorted offsets monotonically to avoid searching every comment boundary for each character.

Apply when: changing YAML comment removal, plain folding, compact collection rewrites, or cached line classification. Only nonempty plain scalars stop this way; a comment after an empty mapping value may precede its nested value.
Evidence: [parser](../../stdlib/data/yaml.ms), [comment continuation regressions](../../tests/e2e/testdata/stdlib/yaml-comment-continuation-regression.ms), and [YAML comments](https://yaml.org/spec/1.2.2/#66-comments).
Verify: first-line and later-line comments, compact mappings, deep compact sequences, Unicode prefixes, sibling values, literal hashes, quoted hashes, empty/comment-only values, flow plain continuation, commas after comments, and comments before an unstarted flow value.
