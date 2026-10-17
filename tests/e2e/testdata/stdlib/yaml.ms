import range from "@std/collections.ms"
import {parse, stringify, YamlValue, YamlError, YamlLimits} from "@std/yaml.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn entries(value: YamlValue) -> Map[String, YamlValue]:
    match value:
        ObjectValue(values): return values
        _: return panic("expected YAML mapping")

fn items(value: YamlValue) -> List[YamlValue]:
    match value:
        ArrayValue(values): return values
        _: return panic("expected YAML sequence")

fn limits(
    bytes: Optional[Int],
    depth: Optional[Int],
    values: Optional[Int]
) -> Optional[YamlLimits]:
    return some(YamlLimits(max_bytes: bytes, max_depth: depth, max_values: values))

type ScalarCase:
    text: String
    expected: String

fn scalar(text: String, expected: String) -> Unit:
    let root = parse(text: text) | value | entries
    if root.get("a").unwrap() != YamlValue.StringValue(expected): return panic(
        "scalar folding: {text}"
    )

test "YAML issue 133 folded paragraph":
    scalar(text: "a: >\n  x\n  y\n\n  z\n", expected: "x y\nz\n")

test "YAML issue 133 folded multiple blank lines":
    scalar(text: "a: >\n  x\n\n\n  z\n", expected: "x\n\nz\n")

test "YAML issue 133 single quoted paragraph":
    scalar(text: "a: 'x\n\n  y'", expected: "x\ny")

test "YAML issue 133 double quoted paragraphs":
    scalar(text: "a: \"x\n\n\n  y\"", expected: "x\n\ny")

test "YAML issue 133 plain paragraph before sibling":
    scalar(text: "a: x\n\n  y\nb: 1", expected: "x\ny")

test "YAML quoted folding trims physical whitespace and preserves escapes":
    let cases = [
        ScalarCase(text: "a: 'x \t\n \t\n  y'", expected: "x\ny"),
        ScalarCase(text: "a: \"x \t\n \t\n\n  y\"", expected: "x\n\ny"),
        ScalarCase(text: "a: ' x  \n  y '", expected: " x y "),
        ScalarCase(text: "a: \"x\\t\n  y\"", expected: "x\t y"),
        ScalarCase(text: "a: \"x\\ \n  y\"", expected: "x  y"),
        ScalarCase(text: "a: \"x \\\n  y\"", expected: "x y"),
        ScalarCase(text: "a: \"x \\\n \t\n\n  y\"", expected: "x \n\ny"),
        ScalarCase(
            text: "a: 'x\n\n  # hash: text\n\n  it''s y' # outside",
            expected: "x\n# hash: text\nit's y"
        ),
        ScalarCase(
            text: "a: \"x\n\n  \\\"y\\\"\" # outside",
            expected: "x\n\"y\""
        )
    ]
    for example in cases:
        for ending in ["\n", "\r\n", "\r"]:
            scalar(
                text: (
                    example
                    .text
                    .replace(
                        old: "\n",
                        new: ending,
                        max_replacements: (
                            example
                            .text
                            .byte_length()
                        )
                    )
                ),
                expected: example.expected
            )
    if value(parse(text: "'x\n\n  y'")) != YamlValue.StringValue("x\ny"):
        return panic("root quoted paragraph")

    let flow = parse(text: "['x\n\n  y', \"z\\\n\n  w\"]") | value | items
    if flow != [YamlValue.StringValue("x\ny"), YamlValue.StringValue("z\nw")]:
        return panic("quoted folding inside flow collection")

test "YAML folded and literal blocks respect paragraphs indentation and chomping":
    let cases = [
        ScalarCase(text: "a: >-\n  x\n \n  y\n\n", expected: "x\ny"),
        ScalarCase(text: "a: >\n  x\n\n  y\n\n\n", expected: "x\ny\n"),
        ScalarCase(text: "a: >+\n  x\n\n  y\n\n\n", expected: "x\ny\n\n\n"),
        ScalarCase(text: "a: >2-\n  x\n\n\n  y\n", expected: "x\n\ny"),
        ScalarCase(
            text: "a: >\n  x\n\n    y\n\n  z\n",
            expected: "x\n\n  y\n\nz\n"
        ),
        ScalarCase(text: "a: >2-\n  x\n   \n  y\n", expected: "x\n \ny"),
        ScalarCase(
            text: "a: >2-\n  x\n\n  \ty\n\n  z\n",
            expected: "x\n\n\ty\n\nz"
        ),
        ScalarCase(text: "a: >-\n\n  x\n\n  y\n", expected: "\nx\ny"),
        ScalarCase(text: "a: |\n  x\n\n  y\n", expected: "x\n\ny\n"),
        ScalarCase(text: "a: |+\n  x\n\n", expected: "x\n\n"),
        ScalarCase(text: "a: >\n  x", expected: "x"),
        ScalarCase(text: "a: |\n  x", expected: "x"),
        ScalarCase(text: "a: >+\n  x\n\n  y", expected: "x\ny"),
        ScalarCase(text: "a: >\n\n", expected: ""),
        ScalarCase(text: "a: >+\n\n", expected: "\n"),
        ScalarCase(text: "a: |-\n\n", expected: ""),
        ScalarCase(text: "a: >\n   \n", expected: ""),
        ScalarCase(text: "a: >+\n   \n", expected: "\n"),
        ScalarCase(text: "a: >2+\n   \n", expected: " \n"),
        ScalarCase(text: "a: >\n \t\n", expected: "\t\n")
    ]
    for example in cases:
        for ending in ["\n", "\r\n", "\r"]:
            scalar(
                text: (
                    example
                    .text
                    .replace(
                        old: "\n",
                        new: ending,
                        max_replacements: (
                            example
                            .text
                            .byte_length()
                        )
                    )
                ),
                expected: example.expected
            )

test "YAML plain paragraphs retain boundaries and nested collections":
    for ending in ["\n", "\r\n", "\r"]:
        let text = "a: x  \n \t\n\n  y \t\n  z\n\nb: 1\n"
        let root = entries(
            value(
                parse(
                    text: text.replace(
                        old: "\n",
                        new: ending,
                        max_replacements: text.byte_length()
                    )
                )
            )
        )
        if root.get("a").unwrap() != YamlValue.StringValue("x\n\ny z"):
            return panic("plain whitespace paragraphs")
        if root.get("b").unwrap() != YamlValue.NumberValue("1"):
            return panic("plain folding consumed sibling")

    let root = parse(text: "a:\n  - x\n\n    y\n  - z\nb: 1\n") | value | entries
    if (
        items(root.get("a").unwrap()) != [
            YamlValue.StringValue("x\ny"),
            YamlValue.StringValue("z")
        ]
    ):
        return panic("sequence plain paragraph")

    scalar(text: "a: x\n\n# comment\nb: 1\n", expected: "x")
    scalar(text: "a: x\n\n", expected: "x")

test "YAML blank line folding retains byte node and malformed input contracts":
    let text = "a: \"é\r\n\r\n  y\"\r\n"
    let expected = value(parse(text: text))
    if (
        value(
            parse(
                text: text,
                limits: limits(
                    bytes: text.byte_length(),
                    depth: 2,
                    values: 2
                )
            )
        ) != expected
    ):
        return panic("exact original byte and node budgets")

    let limited: Result[YamlValue, YamlError] = error(YamlError.LimitExceeded)
    if (
        parse(
            text: text,
            limits: limits(
                bytes: text.byte_length() - 1,
                depth: none,
                values: none
            )
        ) != limited
    ):
        return panic("byte budget precedes line ending normalization")
    if (
        parse(
            text: text,
            limits: limits(bytes: none, depth: none, values: 1)
        ) != limited
    ):
        return panic("folding does not alter value counting")

    for text in [
        "a: 'x\n\n  y", "a: \"x\n\n  y", "a: \"x\\\n\n  y\\q\"", "a: x\n\n  b: y",
        "a: x\n\n  - y", "a: x\n\n \ty", "a: x\n # comment\n  y", "a: >--\n\n  x",
        "a: >\n  x\n \t\n  y", "a: >2\n  x\n y"
    ]:
        let cause = match parse(text: text):
            ok(_): return panic("malformed multiline scalar accepted: {text}")
            error(cause): cause

        match cause:
            InvalidData(line, column, reason):
                if (line < 1 or column < 1 or reason == ""): return panic(
                    "multiline diagnostic"
                )
            _: return panic("wrong multiline error")

    let cause = match parse(text: "a: x\n\n  b: y"):
        error(cause): cause
        ok(_): return panic("indented mapping accepted as plain continuation")

    match cause:
        InvalidData(line, column, _):
            if line != 3 or column != 1: return panic("continuation error position")
        _: return panic("wrong continuation error")

test "YAML block mappings sequences exact scalars and core schema":
    let text = "name: é🙂\nlarge: 9007199254740993\nboolean: TRUE\nlegacy: yes\ndate: 2024-02-29\nempty:\nvalues:\n- null\n- false\n- 0xFF\npeople:\n  - name: Ada\n    age: 37\n  - name: Grace\n    skills:\n      - compilers\n"
    let root = parse(text: text) | value | entries
    if root.get("name").unwrap() != YamlValue.StringValue("é🙂"): return panic(
        "YAML Unicode"
    )
    if root.get("large").unwrap() != YamlValue.NumberValue("9007199254740993"): return panic(
        "YAML precision"
    )
    if root.get("boolean").unwrap() != YamlValue.BoolValue(true): return panic(
        "core boolean"
    )
    if root.get("legacy").unwrap() != YamlValue.StringValue("yes"): return panic(
        "YAML 1.2 yes"
    )
    if root.get("date").unwrap() != YamlValue.StringValue("2024-02-29"): return panic(
        "core date"
    )
    if root.get("empty").unwrap() != YamlValue.Null: return panic("empty scalar")
    if (
        items(root.get("values").unwrap()) != [
            YamlValue.Null,
            YamlValue.BoolValue(false),
            YamlValue.NumberValue("0xFF")
        ]
    ): return panic("indentless sequence")

    let people = items(root.get("people").unwrap())
    if (
        people.length() != 2
        or entries(people.first().unwrap()).get(
            "age"
        ).unwrap() != YamlValue.NumberValue("37")
    ): return panic("compact mappings")
    if (
        items(
            entries(people.last().unwrap()).get("skills").unwrap()
        ).first().unwrap() != YamlValue.StringValue("compilers")
    ): return panic("nested compact mapping")

test "YAML flow collections quotes escapes comments and multiline values":
    let root = entries(
        value(
            parse(
                text: "flow: \{name: 'it''s # fine', list: [true, 2, \"é\\u263A\",],\}\nurl: https://example.org/#fragment # comment\nquoted: \"hash # colon: brace \{\}\"\nmultiline: [1,\n  2, # comment\n  3]\ntext: a long\n  continued sentence\n"
            )
        )
    )
    if (
        entries(root.get("flow").unwrap()).get(
            "name"
        ).unwrap() != YamlValue.StringValue("it's # fine")
    ): return panic("single quotes")
    if (
        items(
            entries(root.get("flow").unwrap()).get("list").unwrap()
        ).last().unwrap() != YamlValue.StringValue("é☺")
    ): return panic("quoted escape")
    if (
        root.get("url").unwrap() != YamlValue.StringValue(
            "https://example.org/#fragment"
        )
    ): return panic("URL comment")
    if items(root.get("multiline").unwrap()).length() != 3: return panic(
        "multiline flow"
    )
    if (root.get("text").unwrap() != YamlValue.StringValue("a long continued sentence")): return panic(
        "plain folding"
    )
    if value(parse(text: "'literal\\n'")) != YamlValue.StringValue("literal\\n"): return panic(
        "literal quote"
    )

test "YAML literal folded and chomped block scalars preserve content":
    let root = entries(
        value(
            parse(
                text: "literal: |\n  first # text\n  second\nfolded: >-\n  hello\n  world\nkeep: |+\n  line\n\nexplicit: |2-\n  indented\ntabs: |-\n  \tcontent\n"
            )
        )
    )
    if (root.get("literal").unwrap() != YamlValue.StringValue("first # text\nsecond\n")): return panic(
        "literal block"
    )
    if root.get("folded").unwrap() != YamlValue.StringValue("hello world"): return panic(
        "folded block"
    )
    if root.get("keep").unwrap() != YamlValue.StringValue("line\n\n"): return panic(
        "keep chomping"
    )
    if root.get("explicit").unwrap() != YamlValue.StringValue("indented"): return panic(
        "explicit indentation"
    )
    if root.get("tabs").unwrap() != YamlValue.StringValue("\tcontent"): return panic(
        "tabs in scalar content"
    )

test "YAML anchors aliases merge keys and override precedence":
    let text = "defaults: &defaults\n  retries: 3\n  enabled: true\ncopy: *defaults\nconfig:\n  <<: *defaults\n  retries: 5\nscalar: &answer 42\nalias: *answer\nflow: &flow [1, 2]\nflow_alias: *flow\n"
    let root = parse(text: text) | value | entries
    if root.get("defaults").unwrap() != root.get("copy").unwrap(): return panic(
        "mapping alias"
    )

    let config = entries(root.get("config").unwrap())
    if (
        config.get("retries").unwrap() != YamlValue.NumberValue("5")
        or config.get("enabled").unwrap() != YamlValue.BoolValue(true)
    ): return panic("merge override")
    if root.get("alias").unwrap() != YamlValue.NumberValue("42"): return panic(
        "scalar anchor"
    )
    if root.get("flow_alias").unwrap() != root.get("flow").unwrap(): return panic(
        "flow anchor"
    )

    let merged = entries(
        value(
            parse(
                text: "a: &a \{x: 1\}\nb: &b \{x: 2, y: 3\}\nc: \{<<: [*a, *b], y: 4\}\n"
            )
        )
    )
    let c = entries(merged.get("c").unwrap())
    if (
        c.get("x").unwrap() != YamlValue.NumberValue("1")
        or c.get("y").unwrap() != YamlValue.NumberValue("4")
    ): return panic("merge precedence")

test "YAML documents BOM CRLF empty input and version directive":
    let root = value(
        parse(text: "\u{feff}%YAML 1.2\r\n---\r\na: 1\r\n...\r\n# done\r\n")
    )
    if entries(root).get("a").unwrap() != YamlValue.NumberValue("1"): return panic(
        "document markers"
    )
    if value(parse(text: "# comment\n")) != YamlValue.Null: return panic("empty YAML")
    if value(parse(text: "---\n...\n")) != YamlValue.Null: return panic(
        "empty document"
    )
    if items(value(parse(text: "- - 1\n  - 2\n- - 3\n"))).length() != 2: return panic(
        "compact sequences"
    )

test "YAML rejects duplicates invalid indentation malformed flow and aliases":
    for text in [
        "a: 1\na: 2", "\{a: 1, a: 2\}", "a:\n\tb: 1", "a: 1\n  b: 2",
        "a:\n  b: 1\n c: 2", "[1,", "[1,,2]", "\{a: 1 b: 2\}", "\"\\uD800\"", "\"\\q\"",
        "'unterminated", "*missing", "a: &loop [*loop]", "<<: 1",
        "---\na: 1\n---\nb: 2", "a: |0\n  text"
    ]:
        let cause = match parse(text: text):
            ok(_): return panic("invalid YAML accepted: {text}")
            error(cause): cause

        match cause:
            InvalidData(line, column, reason):
                if (line < 1 or column < 1 or reason == ""): return panic(
                    "YAML diagnostic details"
                )

                let boundary = Error(cause)
                if not boundary.message().starts_with("YAML "): return panic(
                    "source YAML Error"
                )
            _: return panic("wrong YAML error")

    for text in [
        "!custom value", "? complex\n: value", "%TAG ! tag:example.org\n---\na: 1"
    ]:
        let cause = match parse(text: text):
            ok(_): return panic("unsupported YAML accepted")
            error(cause): cause

        match cause:
            UnsupportedFeature(_, _): let expected = unit
            _: return panic("expected unsupported feature")

test "YAML limits cover root nested nodes aliases and exact bytes":
    let limited: Result[YamlValue, YamlError] = error(YamlError.LimitExceeded)
    let invalid: Result[YamlValue, YamlError] = error(YamlError.InvalidInput)
    if (
        parse(
            text: "é",
            limits: limits(bytes: 1, depth: none, values: none)
        ) != limited
    ): return panic("UTF8 byte limit")
    if (
        parse(
            text: "[[[]]]",
            limits: limits(bytes: none, depth: 2, values: none)
        ) != limited
    ): return panic("flow depth limit")
    if (
        parse(
            text: "a:\n  b: 1",
            limits: limits(bytes: none, depth: 2, values: none)
        ) != limited
    ): return panic("block depth limit")
    if (
        parse(
            text: "[1,2]",
            limits: limits(bytes: none, depth: none, values: 2)
        ) != limited
    ): return panic("value limit")
    if (
        parse(
            text: "a: &a [1,2]\nb: *a",
            limits: limits(bytes: none, depth: none, values: 6)
        ) != limited
    ): return panic("expanded alias limit")
    if (
        parse(text: "", limits: limits(bytes: 0, depth: 1, values: 1)) != parse(
            text: ""
        )
    ): return panic("empty exact limits")
    if (parse(text: "", limits: limits(bytes: none, depth: none, values: 0)) != limited): return panic(
        "zero values"
    )
    if (
        parse(
            text: "",
            limits: limits(bytes: none, depth: -1, values: none)
        ) != invalid
    ): return panic("negative limit")
    if (
        parse(
            text: "[1,2]",
            limits: limits(bytes: 5, depth: 2, values: 3)
        ) != parse(text: "[1,2]")
    ): return panic("exact limits")

test "YAML exact decimal syntax does not depend on binary64 conversion":
    for text in [".5", "1.", "1.e2", "1e999999", ".Inf", ".NAN", "-0", "0001"]:
        if value(parse(text: text)) != YamlValue.NumberValue(text): return panic(
            "YAML number treated as string: {text}"
        )
    for text in [
        ".", "1e", "1_000", "+0xFF", "-.nan", ".iNF", "it's plain",
        "text [with] punctuation"
    ]:
        if value(parse(text: text)) != YamlValue.StringValue(text): return panic(
            "plain scalar resolved incorrectly: {text}"
        )

fn failure(text: String) -> String:
    match parse(text: text):
        ok(_): return "accepted"
        error(cause): return cause.message()

test "YAML merge and block header errors name their own line":
    if failure("<<: 1") != "YAML 1:1: merge requires mappings": return panic(
        "single line merge"
    )
    if failure("x: 1\ny: 2\n<<: 1") != "YAML 3:1: merge requires mappings": return panic(
        "later merge"
    )
    if failure("a: |x") != "YAML 1:5: invalid block scalar header": return panic(
        "header"
    )
    if failure("x: 1\ny: |x\nz: 3") != "YAML 2:5: invalid block scalar header": return panic(
        "later header"
    )

test "YAML limits fields default to none":
    let limited: Result[YamlValue, YamlError] = error(YamlError.LimitExceeded)
    if parse(text: "a: 1", limits: some(YamlLimits(max_bytes: 2))) != limited: return panic(
        "partial byte limit"
    )
    if parse(text: "a: 1", limits: some(YamlLimits())) != parse(text: "a: 1"): return panic(
        "empty limits"
    )

test "YAML stringify round trips scalars sequences and mappings":
    let source = "title: \"é🙂 \\\"q\\\" \\t tab\"\nnone: null\nflag: true\nint: -42\nfloat: 1.5e3\nlist:\n  - 1\n  - two\n  - [3, 4]\n  - a: 1\n    b: [x, y]\nempty_list: []\nempty_map: \{\}\n\"odd key\": 1\n\"true\": 2\nnested:\n  deep:\n    value: ok\n"
    let parsed = value(parse(text: source))
    let text = value(stringify(value: parsed))
    if value(parse(text: text)) != parsed: return panic("YAML stringify round trip")
    if value(stringify(value: value(parse(text: text)))) != text: return panic(
        "YAML stringify is stable"
    )

test "YAML stringify validates numbers and honors max_bytes":
    let invalid: Result[String, YamlError] = error(YamlError.InvalidInput)
    let limited: Result[String, YamlError] = error(YamlError.LimitExceeded)
    if stringify(value: YamlValue.NumberValue("not a number")) != invalid: return panic(
        "invalid number text"
    )

    let root = value(parse(text: "a: 1"))
    if stringify(value: root, max_bytes: 3) != limited: return panic("output limit")

    let exact: Result[String, YamlError] = ok("a: 1\n")
    if stringify(value: root, max_bytes: 5) != exact: return panic("exact limit")
    if stringify(value: root, max_bytes: -1) != invalid: return panic("negative limit")

test "YAML scalars and anchors on their own line continue at the same indentation":
    let folded = entries(
        value(parse(text: "run:\n  util/check.sh\n  --flag value\nnext: 1\n"))
    )
    if (
        folded.get("run").unwrap() != YamlValue.StringValue(
            "util/check.sh --flag value"
        )
    ): return panic("plain scalar on its own line")
    if folded.get("next").unwrap() != YamlValue.NumberValue("1"): return panic(
        "sibling after scalar"
    )

    let list = parse(text: "- foo\n  bar\n-\n  baz\n  qux\n") | value | items
    if list != [YamlValue.StringValue("foo bar"), YamlValue.StringValue("baz qux")]: return panic(
        "sequence items"
    )

    let anchored = parse(text: "a:\n  &x\n  k: 1\nb: *x\n") | value | entries
    if anchored.get("a").unwrap() != anchored.get("b").unwrap(): return panic(
        "anchor on its own line"
    )
    if (
        entries(anchored.get("b").unwrap()).get(
            "k"
        ).unwrap() != YamlValue.NumberValue("1")
    ): return panic("anchored mapping")

test "YAML quoted merge key is an ordinary string key":
    let block = parse(text: "\"<<\": 1\nplain: 3\n") | value | entries
    if block.get("<<").unwrap() != YamlValue.NumberValue("1"): return panic(
        "block quoted key"
    )
    if block.length() != 2: return panic("block entries")

    let single = parse(text: "'<<': 2\n") | value | entries
    if single.get("<<").unwrap() != YamlValue.NumberValue("2"): return panic(
        "single quoted key"
    )

    let flow = parse(text: "\{\"<<\": 1, a: 2\}\n") | value | entries
    if flow.get("<<").unwrap() != YamlValue.NumberValue("1"): return panic(
        "flow quoted key"
    )

    let merged = entries(
        value(parse(text: "base: &b \{x: 1\}\nm:\n  <<: *b\n  y: 2\n"))
    )
    if (
        entries(merged.get("m").unwrap()).get(
            "x"
        ).unwrap() != YamlValue.NumberValue("1")
    ): return panic("plain merge key")

    let original = value(parse(text: "\"<<\": 1\n"))
    if value(parse(text: value(stringify(value: original)))) != original: return panic(
        "quoted merge key round trip"
    )

test "YAML plain scalars continued inside flow collections fold their line breaks":
    let root = entries(
        value(
            parse(
                text: "a: [x\n  y, z]\nb: \{k: one\n    two\}\nc: [p\n  q\n\n  r]\n"
            )
        )
    )
    if (
        items(root.get("a").unwrap()) != [
            YamlValue.StringValue("x y"),
            YamlValue.StringValue("z")
        ]
    ): return panic("flow sequence fold")
    if (
        entries(root.get("b").unwrap()).get(
            "k"
        ).unwrap() != YamlValue.StringValue("one two")
    ): return panic("flow mapping fold")
    if items(root.get("c").unwrap()) != [YamlValue.StringValue("p q\nr")]: return panic(
        "flow blank line"
    )

test "YAML document start marker accepts same-line content":
    if value(parse(text: "--- a")) != YamlValue.StringValue("a"): return panic(
        "scalar after marker"
    )
    if items(value(parse(text: "--- [1, 2]"))).length() != 2: return panic(
        "flow after marker"
    )
    if value(parse(text: "--- # note\na: 1")) != value(parse(text: "a: 1")): return panic(
        "comment after marker"
    )

test "YAML compact mapping after a sequence marker follows the marker's spacing":
    let root = value(
        parse(text: "-   a: 1\n    b: 2\n-  - x\n   - y\n- c: 3\n  d: 4\n")
    )
    let list = items(root)
    if list.length() != 3: return panic("sequence length")

    let first = entries(list.first().unwrap())
    if first.get("b").unwrap() != YamlValue.NumberValue("2"): return panic(
        "wide marker spacing"
    )
    if items(list.at(1).unwrap()).length() != 2: return panic("wide nested sequence")
    if entries(list.last().unwrap()).get("d").unwrap() != YamlValue.NumberValue("4"): return panic(
        "single space marker"
    )

fn repeated(text: String, count: Int) -> String:
    if count <= 0: return ""
    if count == 1: return text

    let half = repeated(text: text, count: count / 2)
    if count % 2 == 1: return half.concat(half).concat(text)

    return half.concat(half)

test "YAML long plain scalars and large mappings parse in linear time":
    let long = repeated(text: "x", count: 300000)
    let scalar = parse(text: "a: {long}") | value | entries
    if scalar.get("a").unwrap() != YamlValue.StringValue(long): return panic(
        "long plain scalar"
    )

    var keys = ""
    for index in range(0, 30000):
        keys = keys.concat("k{index}: 1\n")
    if entries(value(parse(text: keys))).length() != 30000: return panic("many keys")

    match parse(text: keys.concat("k7: 2\n")):
        ok(_): return panic("duplicate key after many keys")
        error(_): return

test "YAML flow mapping keys without a colon map to null":
    let root = parse(text: "a: \{x, y: 1, z\}\nb: \{\"q\", r: [1]\}") | value | entries
    let first = entries(root.get("a").unwrap())
    if first.length() != 3: return panic("flow keys")
    if first.get("x").unwrap() != YamlValue.Null: return panic("first null key")
    if first.get("y").unwrap() != YamlValue.NumberValue("1"): return panic(
        "explicit value"
    )
    if first.get("z").unwrap() != YamlValue.Null: return panic("last null key")

    let second = entries(root.get("b").unwrap())
    if second.get("q").unwrap() != YamlValue.Null: return panic("quoted null key")

    match parse(text: "\{x, x\}"):
        ok(_): return panic("duplicate null keys")
        error(_): let ignored = unit

    let limited = limits(bytes: none, depth: none, values: some(2))

    match parse(text: "\{a, b, c\}", limits: limited):
        ok(_): return panic("null keys count against the value limit")
        error(_): let ignored = unit

test "YAML long quoted block and multi-line scalars decode and stringify in linear time":
    let long = repeated(text: "x", count: 300000)
    let double = parse(text: "a: \"{long}\"") | value | entries
    if double.get("a").unwrap() != YamlValue.StringValue(long): return panic(
        "double quoted"
    )

    let single = parse(text: "a: '{long}'") | value | entries
    if single.get("a").unwrap() != YamlValue.StringValue(long): return panic(
        "single quoted"
    )

    let lines = repeated(text: "word\n  ", count: 20000)
    let plain = parse(text: "a: {lines}end") | value | entries
    if (
        plain.get("a").unwrap() != YamlValue.StringValue(
            repeated(text: "word ", count: 20000).concat("end")
        )
    ): return panic("multi-line plain")

    let body = repeated(text: "  line\n", count: 20000)
    let literal = parse(text: "a: |\n{body}") | value | entries
    if (
        literal.get("a").unwrap() != YamlValue.StringValue(
            repeated(text: "line\n", count: 20000)
        )
    ): return panic("literal block")

    let root = value(parse(text: "a: \"{long}\""))
    if value(parse(text: value(stringify(value: root)))) != root: return panic(
        "stringify round trip"
    )

test "YAML block scalar chomping counts every trailing line break":
    scalar(text: "a: |\n  x\n\n\n\nb: 1", expected: "x\n")
    scalar(text: "a: |-\n  x\n\n\n\nb: 1", expected: "x")
    scalar(text: "a: |+\n  x\n\n\n\nb: 1", expected: "x\n\n\n\n")
    scalar(text: "a: >-\n  x\n\n\n", expected: "x")
    scalar(text: "a: |\n\n\nb: 1", expected: "")
    scalar(text: "a: |+\n\n\nb: 1", expected: "\n\n")

test "YAML compact nested sequences resume each level and parse deep chains in linear time":
    let small = items(
        value(
            parse(
                text: "- - - x\n    - y\n  - z\n- - 1\n  - - 2\n    - 3\n-\n  - -\n    - a: 1\n      b: 2\n"
            )
        )
    )
    if small.length() != 3: return panic("compact chain top level")

    let first = items(small.first().unwrap())
    if first.length() != 2: return panic("compact chain middle level")
    if items(first.first().unwrap()).length() != 2: return panic(
        "compact chain innermost"
    )
    if first.last().unwrap() != YamlValue.StringValue("z"): return panic(
        "compact chain resumes outer level"
    )

    let depth = 3000
    var source = "{repeated(text: "- ", count: depth)}x\n"
    var root = value(parse(text: source))

    for level in range(1, depth):
        let inner = items(root)
        if inner.length() != 1: return panic("deep chain width")

        root = inner.first().unwrap()

    if items(root) != [YamlValue.StringValue("x")]: return panic("deep chain leaf")
