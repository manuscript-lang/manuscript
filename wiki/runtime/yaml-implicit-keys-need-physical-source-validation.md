[Wiki](../index.md) › [Runtime](index.md)

# YAML implicit keys need physical-source validation

Verified: a colon-bearing implicit flow key must stay on one physical source line. Checking its decoded text is wrong: a quoted key may legitimately contain an escaped newline, while an escaped physical line break is still a source break. Validate the raw key span through the colon without copying it. Preserve omitted-value entries, where a multiline flow node can remain the key and line breaks may separate entries.

Apply when: changing YAML flow mapping keys, quoted decoding, or folding.
Evidence: [parser](../../stdlib/data/yaml.ms), [regressions](../../tests/e2e/testdata/stdlib/yaml-key-line-regression.ms), [YAML flow mappings](https://yaml.org/spec/1.2.2/#742-flow-mappings).
Verify: reject plain, quoted and escaped physical breaks before a key's colon; preserve escaped newline text, omitted values and multiline values after the colon.
