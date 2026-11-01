[Wiki](../index.md) › [Runtime](index.md)

# YAML folding must retain physical blank lines until decoding

Verified: stripping continuation lines before joining loses paragraph breaks and can misclassify comment markers inside an open quote. Quoted and plain folding remove the first break before empty lines; folded blocks do so only between ordinary lines, preserving breaks around more-indented content. Chomping also needs to know whether the final physical line had a terminator. Quotes and opening containers are structural only at node starts; quotes inside plain text must not hide comments. Marker search and completeness use one scanner, and fast comment candidates also recognize line-feed separation.

Apply when: changing YAML scalar gathering, comment removal, whitespace handling, folding, or chomping.
Evidence: [YAML parser](../../stdlib/data/yaml.ms), [called scalar regressions](../../tests/e2e/testdata/stdlib/yaml.ms), [node/comment regressions](../../tests/e2e/testdata/stdlib/yaml-node-scan-regression.ms), [YAML contract](../../stdlib/data/json.ms), and [YAML 1.2 folding](https://yaml.org/spec/1.2.2/#65-line-folding).
Verify: run all five issue examples plus escaped continuations, whitespace-only blank lines, more-indented blocks, all chomping modes, and missing final terminators under LF/CRLF/CR normalization; preserve plain embedded quotes/brackets, whole-line flow comments, anchored quotes, adjacent quoted keys, and Unicode spaces.
