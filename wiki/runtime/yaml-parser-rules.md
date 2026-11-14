[Wiki](../index.md) › [Runtime](index.md)

# YAML parser rules

Verified: lessons from the `@std/yaml` parser ([parser](../../stdlib/data/yaml.ms), [regressions](../../tests/conformance/fixtures/e2e/stdlib/yaml-regressions.ms)). Each section is one failure mechanism; read the ones for the code you change.

## YAML plain colons depend on the following character

Verified: splitting a plain flow key at every colon changes `{a:1}` from a key `a:1` with null value into key `a` with number 1, and corrupts URL keys. A plain colon separates only before whitespace, end of input, or flow punctuation. Quoted keys retain adjacent-value syntax. In values, a separating colon must be rejected instead of silently becoming string content; tabs, line breaks and trailing colons need the same rule as spaces. Flow punctuation separates only inside a flow collection, so block plain strings retain it.

Apply when: changing YAML plain scalar scanning or its fast path.
Evidence: [parser](../../stdlib/data/yaml.ms), [regressions](../../tests/conformance/fixtures/e2e/stdlib/yaml-regressions.ms), [YAML 1.2.2 flow mappings](https://yaml.org/spec/1.2.2/#742-flow-mappings).
Verify: `{a:1}` and `{key:"word"}` keep their entire plain keys; quoted adjacent keys, URL keys, empty values, whitespace, and nested collections retain their shapes; malformed scalar separators are rejected in flow and block values.

## YAML implicit keys need physical-source validation

Verified: a colon-bearing implicit flow key must stay on one physical source line. Checking its decoded text is wrong: a quoted key may legitimately contain an escaped newline, while an escaped physical line break is still a source break. Validate the raw key span through the colon without copying it. Preserve omitted-value entries, where a multiline flow node can remain the key and line breaks may separate entries.

Apply when: changing YAML flow mapping keys, quoted decoding, or folding.
Evidence: [parser](../../stdlib/data/yaml.ms), [regressions](../../tests/conformance/fixtures/e2e/stdlib/yaml-regressions.ms), [YAML flow mappings](https://yaml.org/spec/1.2.2/#742-flow-mappings).
Verify: reject plain, quoted and escaped physical breaks before a key's colon; preserve escaped newline text, omitted values and multiline values after the colon.

## YAML diagnostics need source origins

Verified: a flow cursor is relative to its gathered value, not the complete source line. Reporting that offset as a column loses mapping, sequence, indentation and anchor prefixes; treating the whole cursor as one column loses physical line breaks. Capture the origin before gathering advances the context, carry its scalar column through prefix removal, and project the cursor through retained line feeds only when reporting an error. Keep virtual row/column shifts in separate diagnostic metadata rather than changing parsing bases. Merge failures and unsupported forms must use the same projection; locate rejected controls only on their error path. Valid input needs no per-character position tracking.

Apply when: changing YAML gathering, scalar prefixes, compact virtual source lines, or diagnostics. Root continuation uses `base - 1`, so the source origin must independently retain the original `base + 1` column. All prefix arithmetic uses scalar lengths.
Evidence: [parser](../../stdlib/data/yaml.ms), [source-origin regressions](../../tests/conformance/fixtures/e2e/stdlib/yaml-regressions.ms).
Verify: root controls, mapping/sequence/anchor prefixes, Unicode, retained comment line breaks and quoted EOF. Virtual document-marker rows and compact tab prefixes retain their diagnostic projection separately from parsing bases. Check same-row accumulation, later-row isolation, lazy merge failures, later-line unsupported constructs and invalid controls after Unicode. Parser bases, splicing and valid values stay unchanged.

## YAML folding must retain physical blank lines until decoding

Verified: stripping continuation lines before joining loses paragraph breaks and can misclassify comment markers inside an open quote. Quoted and plain folding remove the first break before empty lines; folded blocks do so only between ordinary lines, preserving breaks around more-indented content. Chomping also needs to know whether the final physical line had a terminator. Quotes and opening containers are structural only at node starts; quotes inside plain text must not hide comments. Marker search and completeness use one scanner, and fast comment candidates also recognize line-feed separation.

Block-scalar indentation is relative to the containing mapping/sequence (zero at the root), not the header column or plain-scalar continuation threshold. Preserve that structural base through standalone headers and anchor-only lines; it determines both automatic indentation and explicit indicators. See [indentation regressions](../../tests/conformance/fixtures/e2e/stdlib/yaml-regressions.ms) (#2977). When detecting indentation, leading empty lines may not exceed the first nonempty content line; apply that validation only to implicit indentation, preserving explicit-indicator spaces and empty-only scalars (#2982).

A supported version directive must accept the same explicit document-start forms as a directive-free document; validate same-line content before the existing source-projected split (#2985).

Apply when: changing YAML scalar gathering, comment removal, whitespace handling, folding, or chomping.
Evidence: [YAML parser](../../stdlib/data/yaml.ms), [called scalar regressions](../../tests/conformance/fixtures/e2e/stdlib/yaml.ms), [node/comment regressions](../../tests/conformance/fixtures/e2e/stdlib/yaml-regressions.ms), [YAML contract](../../stdlib/data/json.ms), and [YAML 1.2 folding](https://yaml.org/spec/1.2.2/#65-line-folding).
Verify: run all five issue examples plus escaped continuations, whitespace-only blank lines, more-indented blocks, all chomping modes, and missing final terminators under LF/CRLF/CR normalization; preserve plain embedded quotes/brackets, whole-line flow comments, anchored quotes, adjacent quoted keys, and Unicode spaces.

A synthetic split after an inline `---` marker must not admit same-line block
collections. Use the recorded physical-line boundary and existing structural
classification, not colon/dash text searches; preserve inline flow/scalar nodes
and anchor-only marker lines followed by a block collection on the next line.

Before gathering any physical continuation of a flow collection or quoted scalar,
reject column-zero `---` or `...` followed by ASCII space, tab or line end. These
are document boundaries even inside an open quote; stripping comments or folding
first can silently turn them into content. Keep indented markers and prefixes
such as `---word` as content; [boundary tests](../../tests/conformance/fixtures/e2e/stdlib/yaml-regressions.ms)
cover these distinctions and physical error rows ([YAML markers](https://yaml.org/spec/1.2.2/#912-document-markers)).

## YAML comments terminate plain scalar continuation

Verified: removing a plain scalar's inline comment before collecting continuation lines erases its terminating boundary. The first line and every consumed continuation line must retain enough raw source to distinguish an actual comment from a literal hash. A compact mapping or nested sequence rewrites its first line; carry its raw suffix through that rewrite, using scalar offsets so Unicode keys and values stay intact. Append and consume a continued line before stopping at its comment. Flow gathering must likewise record the scalar offsets where comments were stripped: plain leaves stop there, while ordinary separation can still admit a comma, closing delimiter, or a value that has not begun. Consume those sorted offsets monotonically to avoid searching every comment boundary for each character.

Apply when: changing YAML comment removal, plain folding, compact collection rewrites, or cached line classification. Only nonempty plain scalars stop this way; a comment after an empty mapping value may precede its nested value.
Evidence: [parser](../../stdlib/data/yaml.ms), [comment continuation regressions](../../tests/conformance/fixtures/e2e/stdlib/yaml-regressions.ms), and [YAML comments](https://yaml.org/spec/1.2.2/#66-comments).
Verify: first-line and later-line comments, compact mappings, deep compact sequences, Unicode prefixes, sibling values, literal hashes, quoted hashes, empty/comment-only values, flow plain continuation, commas after comments, and comments before an unstarted flow value.
