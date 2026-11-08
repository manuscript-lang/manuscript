[Wiki](../index.md) › [Runtime](index.md)

# XML comments validate content at every parser site

`@std/data/xml.ms` promises well-formed XML 1.0. Finding `-->` is not enough: comment content cannot contain `--` or end in `-`. `Reader.comment` consumes and validates the whole comment for both child nodes and discarded comments before/after the root, returning the existing `EBADMSG` error. Keep generic `take_until` unchanged: CDATA and processing instructions may contain these hyphens.

Evidence: [issue #2948](https://github.com/manuscript-lang/manuscript/issues/2948), [parser](../../stdlib/data/xml.ms), and [XML fixtures](../../tests/e2e/testdata/stdlib/xml.ms). Tests cover all three positions, malformed/unterminated comments, empty and single-hyphen controls, Unicode/multiline content, and literal entity-looking comment text.

The XML 1.0 `Char` production applies to the entire literal input too (#2950), not only numeric references. Reuse `is_xml_char` before constructing `Reader` so discarded comments/instructions and DTD text cannot hide forbidden scalars. Preserve permitted whitespace, C1 controls, supplementary-plane noncharacters, and BOM; do not substitute a broader Unicode noncharacter ban.

Raw character data must also reject literal `]]>` (#2951) before entity decoding. A delimiter assembled by references or separate nodes remains legal; attributes and CDATA follow their own grammar.
