[Wiki](../index.md) › [Runtime](index.md)

# YAML plain colons depend on the following character

Verified: splitting a plain flow key at every colon changes `{a:1}` from a key `a:1` with null value into key `a` with number 1, and corrupts URL keys. A plain colon separates only before whitespace, end of input, or flow punctuation. Quoted keys retain adjacent-value syntax. In values, a separating colon must be rejected instead of silently becoming string content; tabs, line breaks and trailing colons need the same rule as spaces. Flow punctuation separates only inside a flow collection, so block plain strings retain it.

Apply when: changing YAML plain scalar scanning or its fast path.
Evidence: [parser](../../stdlib/data/yaml.ms), [regressions](../../tests/e2e/testdata/stdlib/yaml-colon-regression.ms), [YAML 1.2.2 flow mappings](https://yaml.org/spec/1.2.2/#742-flow-mappings).
Verify: `{a:1}` and `{key:"word"}` keep their entire plain keys; quoted adjacent keys, URL keys, empty values, whitespace, and nested collections retain their shapes; malformed scalar separators are rejected in flow and block values.
