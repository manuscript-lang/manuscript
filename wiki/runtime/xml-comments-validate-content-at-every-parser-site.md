[Wiki](../index.md) › [Runtime](index.md)

# XML comments validate content at every parser site

`@std/data/xml.ms` promises well-formed XML 1.0. Finding `-->` is not enough: comment content cannot contain `--` or end in `-`. `Reader.comment` consumes and validates the whole comment for both child nodes and discarded comments before/after the root, returning the existing `EBADMSG` error. Keep generic `take_until` unchanged: CDATA and processing instructions may contain these hyphens.

Evidence: [issue #2948](https://github.com/manuscript-lang/manuscript/issues/2948), [parser](../../stdlib/data/xml.ms), and [XML fixtures](../../tests/e2e/testdata/stdlib/xml.ms). Tests cover all three positions, malformed/unterminated comments, empty and single-hyphen controls, Unicode/multiline content, and literal entity-looking comment text.

The XML 1.0 `Char` production applies to the entire literal input too (#2950), not only numeric references. Reuse `is_xml_char` before constructing `Reader` so discarded comments/instructions and DTD text cannot hide forbidden scalars. Preserve permitted whitespace, C1 controls, supplementary-plane noncharacters, and BOM; do not substitute a broader Unicode noncharacter ban.

Raw character data must also reject literal `]]>` (#2951) before entity decoding. A delimiter assembled by references or separate nodes remains legal; attributes and CDATA follow their own grammar.

XML names use the exact [XML 1.0 Fifth Edition NameStartChar/NameChar ranges](https://www.w3.org/TR/xml/#NT-NameStartChar), not a punctuation denylist or Unicode alphabetic predicate (#2952). Colon stays legal because this parser does not resolve namespaces; supplementary names end at U+EFFFF even though later scalars are legal document text.

Line ends and attribute whitespace are normalized per XML 1.0 sections 2.11 and 3.3.3 (#3124). `parse` converts `\r\n` and a lone `\r` to `\n` once on the whole input, before the reader sees it, so CDATA and text agree; attribute values turn literal tab and newline into spaces before references decode, so `&#10;` and `&#13;` survive. `escape_text` and `escape_attribute` write `\r` as `&#13;` to round-trip through any conforming parser.

Processing instructions need the same validation at both discarded top-level and child sites: an XML Name target, whitespace before data, and no case variant of the reserved `xml` target. An XML declaration is a separate production allowed only at the document start (after an optional BOM); its ordered `version`, `encoding`, and `standalone` values are literals, so entity decoding must not turn invalid declaration syntax into valid values. XML 1.0 section 2.8 accepts other syntactically valid `1.x` versions under the 1.0 grammar.

A DOCTYPE's public identifier uses XML's restricted ASCII `PubidChar` production, even though its system identifier and skipped entity literals allow other XML characters. Validate the first `PUBLIC` literal separately; sharing a generic quote scanner accepted brackets, tabs and Unicode. Keep both quote styles, empty public identifiers, apostrophes in double quotes, and unrestricted system-literal controls in the XML fixture.

Escape literal braces in source test data: `"\{", "\}"` supplies two characters, while `"{", "}"` is one interpolation with the legal public-identifier value `", "`. Assert that each forbidden-character fixture has one scalar so this mistake fails at the test data rather than masquerading as a parser defect (#3419).

Serialization inspects child text only to choose indentation. Compact output must skip that scan, and mixed content can stop at its first nonempty text result. Calling `text()` just for this decision allocates a copy of the text. Preserve the predicate's handling of empty text and comments; [the allocation fixture](../../tests/ownership-counts/xml_stringify.ms) catches redundant copies, while the XML tests pin exact compact and indented output. [Paired measurements](../../bench/perf/xml-stringify/README.md) cover wide trees and neighboring cases.
