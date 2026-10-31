[Wiki](../index.md) › [Runtime](index.md)

# YAML plain colons depend on the following character

Verified: splitting a plain flow key at every colon changes `{a:1}` from a key `a:1` with null value into key `a` with number 1, and corrupts URL keys. A plain colon separates only before whitespace, end of input, or flow punctuation. Quoted keys retain adjacent-value syntax.

Apply when: changing YAML flow parsing or its limits.
Evidence: [parser](../../stdlib/yaml.ms), [regressions](../../tests/e2e/testdata/stdlib/yaml-colon-regression.ms), [YAML 1.2.2 flow mappings](https://yaml.org/spec/1.2.2/#742-flow-mappings).
Verify: `{a:1}` and `{key:"word"}` keep their entire plain keys; quoted adjacent keys, URL keys, empty values, whitespace, and nested collections retain their shapes.
