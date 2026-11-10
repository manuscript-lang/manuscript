[Wiki](../index.md) › [Runtime](index.md)

# YAML folding must retain physical blank lines until decoding

Verified: stripping continuation lines before joining loses paragraph breaks and can misclassify comment markers inside an open quote. Quoted and plain folding remove the first break before empty lines; folded blocks do so only between ordinary lines, preserving breaks around more-indented content. Chomping also needs to know whether the final physical line had a terminator. Quotes and opening containers are structural only at node starts; quotes inside plain text must not hide comments. Marker search and completeness use one scanner, and fast comment candidates also recognize line-feed separation.

Block-scalar indentation is relative to the containing mapping/sequence (zero at the root), not the header column or plain-scalar continuation threshold. Preserve that structural base through standalone headers and anchor-only lines; it determines both automatic indentation and explicit indicators. See [indentation regressions](../../tests/e2e/testdata/stdlib/yaml-block-indentation.ms) (#2977). When detecting indentation, leading empty lines may not exceed the first nonempty content line; apply that validation only to implicit indentation, preserving explicit-indicator spaces and empty-only scalars (#2982).

A supported version directive must accept the same explicit document-start forms as a directive-free document; validate same-line content before the existing source-projected split (#2985).

Apply when: changing YAML scalar gathering, comment removal, whitespace handling, folding, or chomping.
Evidence: [YAML parser](../../stdlib/data/yaml.ms), [called scalar regressions](../../tests/e2e/testdata/stdlib/yaml.ms), [node/comment regressions](../../tests/e2e/testdata/stdlib/yaml-regressions.ms), [YAML contract](../../stdlib/data/json.ms), and [YAML 1.2 folding](https://yaml.org/spec/1.2.2/#65-line-folding).
Verify: run all five issue examples plus escaped continuations, whitespace-only blank lines, more-indented blocks, all chomping modes, and missing final terminators under LF/CRLF/CR normalization; preserve plain embedded quotes/brackets, whole-line flow comments, anchored quotes, adjacent quoted keys, and Unicode spaces.

A synthetic split after an inline `---` marker must not admit same-line block
collections. Use the recorded physical-line boundary and existing structural
classification, not colon/dash text searches; preserve inline flow/scalar nodes
and anchor-only marker lines followed by a block collection on the next line.

Before gathering any physical continuation of a flow collection or quoted scalar,
reject column-zero `---` or `...` followed by ASCII space, tab or line end. These
are document boundaries even inside an open quote; stripping comments or folding
first can silently turn them into content. Keep indented markers and prefixes
such as `---word` as content; [boundary tests](../../tests/e2e/testdata/stdlib/yaml-document-boundaries.ms)
cover these distinctions and physical error rows ([YAML markers](https://yaml.org/spec/1.2.2/#912-document-markers)).
