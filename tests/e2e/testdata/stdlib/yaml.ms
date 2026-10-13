import {parse, YamlValue, YamlError, YamlLimits} from "@std/yaml.ms"
import {List, Map} from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import Error from "@std/errors.ms"
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
    return some(
        YamlLimits(
            max_bytes: bytes,
            max_depth: depth,
            max_values: values
        )
    )

type ScalarCase:
    text: String
    expected: String

fn scalar(text: String, expected: String) -> Unit:
    let root = entries(
        value(parse(text: text))
    )
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

    let flow = items(
        value(parse(text: "['x\n\n  y', \"z\\\n\n  w\"]"))
    )
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

    let root = entries(
        value(parse(text: "a:\n  - x\n\n    y\n  - z\nb: 1\n"))
    )
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
        "a: 'x\n\n  y",
        "a: \"x\n\n  y",
        "a: \"x\\\n\n  y\\q\"",
        "a: x\n\n  b: y",
        "a: x\n\n  - y",
        "a: x\n\n \ty",
        "a: x\n # comment\n  y",
        "a: >--\n\n  x",
        "a: >\n  x\n \t\n  y",
        "a: >2\n  x\n y"
    ]:
        match parse(text: text):
            ok(_): return panic("malformed multiline scalar accepted: {text}")
            error(cause):
                match cause:
                    InvalidData(line, column, reason):
                        if (
                            line < 1
                            or column < 1
                            or reason == ""
                        ): return panic("multiline diagnostic")
                    _: return panic("wrong multiline error")

    match parse(text: "a: x\n\n  b: y"):
        error(cause):
            match cause:
                InvalidData(line, column, _):
                    if line != 3 or column != 1: return panic(
                        "continuation error position"
                    )
                _: return panic("wrong continuation error")
        ok(_): return panic("indented mapping accepted as plain continuation")

test "YAML block mappings sequences exact scalars and core schema":
    let text = "name: é🙂\nlarge: 9007199254740993\nboolean: TRUE\nlegacy: yes\ndate: 2024-02-29\nempty:\nvalues:\n- null\n- false\n- 0xFF\npeople:\n  - name: Ada\n    age: 37\n  - name: Grace\n    skills:\n      - compilers\n"
    let root = entries(
        value(parse(text: text))
    )
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
        items(
            root.get("values").unwrap()
        ) != [
            YamlValue.Null,
            YamlValue.BoolValue(false),
            YamlValue.NumberValue("0xFF")
        ]
    ): return panic("indentless sequence")

    let people = items(root.get("people").unwrap())
    if (
        people.length() != 2
        or entries(
            people.first().unwrap()
        ).get("age").unwrap() != YamlValue.NumberValue("37")
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
        entries(
            root.get("flow").unwrap()
        ).get("name").unwrap() != YamlValue.StringValue("it's # fine")
    ): return panic("single quotes")
    if (
        items(
            entries(root.get("flow").unwrap()).get("list").unwrap()
        ).last().unwrap() != YamlValue.StringValue("é☺")
    ): return panic("quoted escape")
    if (
        root.get(
            "url"
        ).unwrap() != YamlValue.StringValue("https://example.org/#fragment")
    ): return panic("URL comment")
    if items(root.get("multiline").unwrap()).length() != 3: return panic(
        "multiline flow"
    )
    if (
        root.get(
            "text"
        ).unwrap() != YamlValue.StringValue("a long continued sentence")
    ): return panic("plain folding")
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
    if (
        root.get(
            "literal"
        ).unwrap() != YamlValue.StringValue("first # text\nsecond\n")
    ): return panic("literal block")
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
    let root = entries(
        value(parse(text: text))
    )
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
    if items(
        value(parse(text: "- - 1\n  - 2\n- - 3\n"))
    ).length() != 2: return panic("compact sequences")

test "YAML rejects duplicates invalid indentation malformed flow and aliases":
    for text in [
        "a: 1\na: 2",
        "\{a: 1, a: 2\}",
        "a:\n\tb: 1",
        "a: 1\n  b: 2",
        "a:\n  b: 1\n c: 2",
        "[1,",
        "[1,,2]",
        "\{a: 1 b: 2\}",
        "\"\\uD800\"",
        "\"\\q\"",
        "'unterminated",
        "*missing",
        "a: &loop [*loop]",
        "<<: 1",
        "---\na: 1\n---\nb: 2",
        "a: |0\n  text"
    ]:
        match parse(text: text):
            ok(_): return panic("invalid YAML accepted: {text}")

            error(cause):
                match cause:
                    InvalidData(line, column, reason):
                        if (
                            line < 1
                            or column < 1
                            or reason == ""
                        ): return panic("YAML diagnostic details")

                        let boundary = Error(cause)
                        if not boundary.message().starts_with("YAML "): return panic(
                            "source YAML Error"
                        )

                    _: return panic("wrong YAML error")

    for text in [
        "!custom value",
        "? complex\n: value",
        "%TAG ! tag:example.org\n---\na: 1"
    ]:
        match parse(text: text):
            ok(_): return panic("unsupported YAML accepted")

            error(cause):
                match cause:
                    UnsupportedFeature(_, _): let expected = unit
                    _: return panic("expected unsupported feature")

test "YAML limits cover root nested nodes aliases and exact bytes":
    let limited: Result[YamlValue, YamlError] = error(YamlError.LimitExceeded)
    let invalid: Result[YamlValue, YamlError] = error(YamlError.InvalidInput)
    if (
        parse(
            text: "é",
            limits: limits(
                bytes: 1,
                depth: none,
                values: none
            )
        ) != limited
    ): return panic("UTF8 byte limit")
    if (
        parse(
            text: "[[[]]]",
            limits: limits(
                bytes: none,
                depth: 2,
                values: none
            )
        ) != limited
    ): return panic("flow depth limit")
    if (
        parse(
            text: "a:\n  b: 1",
            limits: limits(
                bytes: none,
                depth: 2,
                values: none
            )
        ) != limited
    ): return panic("block depth limit")
    if (
        parse(
            text: "[1,2]",
            limits: limits(
                bytes: none,
                depth: none,
                values: 2
            )
        ) != limited
    ): return panic("value limit")
    if (
        parse(
            text: "a: &a [1,2]\nb: *a",
            limits: limits(
                bytes: none,
                depth: none,
                values: 6
            )
        ) != limited
    ): return panic("expanded alias limit")
    if (
        parse(
            text: "",
            limits: limits(
                bytes: 0,
                depth: 1,
                values: 1
            )
        ) != parse(text: "")
    ): return panic("empty exact limits")
    if (
        parse(
            text: "",
            limits: limits(
                bytes: none,
                depth: none,
                values: 0
            )
        ) != limited
    ): return panic("zero values")
    if (
        parse(
            text: "",
            limits: limits(
                bytes: none,
                depth: -1,
                values: none
            )
        ) != invalid
    ): return panic("negative limit")
    if (
        parse(
            text: "[1,2]",
            limits: limits(
                bytes: 5,
                depth: 2,
                values: 3
            )
        ) != parse(text: "[1,2]")
    ): return panic("exact limits")

test "YAML exact decimal syntax does not depend on binary64 conversion":
    for text in [
        ".5",
        "1.",
        "1.e2",
        "1e999999",
        ".Inf",
        ".NAN",
        "-0",
        "0001"
    ]:
        if value(parse(text: text)) != YamlValue.NumberValue(text): return panic(
            "YAML number treated as string: {text}"
        )

    for text in [
        ".",
        "1e",
        "1_000",
        "+0xFF",
        "-.nan",
        ".iNF",
        "it's plain",
        "text [with] punctuation"
    ]:
        if value(parse(text: text)) != YamlValue.StringValue(text): return panic(
            "plain scalar resolved incorrectly: {text}"
        )
