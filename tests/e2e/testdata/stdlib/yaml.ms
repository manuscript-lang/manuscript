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
        value: YamlLimits(
            max_bytes: bytes,
            max_depth: depth,
            max_values: values
        )
    )

test "YAML block mappings sequences exact scalars and core schema":
    let text = "name: é🙂\nlarge: 9007199254740993\nboolean: TRUE\nlegacy: yes\ndate: 2024-02-29\nempty:\nvalues:\n- null\n- false\n- 0xFF\npeople:\n  - name: Ada\n    age: 37\n  - name: Grace\n    skills:\n      - compilers\n"
    let root = entries(
        value(parse(text: text))
    )
    if root.get("name").unwrap() != YamlValue.StringValue(value: "é🙂"): return panic(
        "YAML Unicode"
    )
    if root.get("large").unwrap() != YamlValue.NumberValue(text: "9007199254740993"): return panic(
        "YAML precision"
    )
    if root.get("boolean").unwrap() != YamlValue.BoolValue(value: true): return panic(
        "core boolean"
    )
    if root.get("legacy").unwrap() != YamlValue.StringValue(value: "yes"): return panic(
        "YAML 1.2 yes"
    )
    if root.get("date").unwrap() != YamlValue.StringValue(value: "2024-02-29"): return panic(
        "core date"
    )
    if root.get("empty").unwrap() != YamlValue.Null: return panic("empty scalar")
    if (
        items(
            root.get("values").unwrap()
        ) != [
            YamlValue.Null,
            YamlValue.BoolValue(value: false),
            YamlValue.NumberValue(text: "0xFF")
        ]
    ): return panic("indentless sequence")

    let people = items(root.get("people").unwrap())
    if (
        people.length() != 2
        or entries(
            people.first().unwrap()
        ).get("age").unwrap() != YamlValue.NumberValue(text: "37")
    ): return panic("compact mappings")
    if (
        items(
            entries(people.last().unwrap()).get("skills").unwrap()
        ).first().unwrap() != YamlValue.StringValue(value: "compilers")
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
        ).get("name").unwrap() != YamlValue.StringValue(value: "it's # fine")
    ): return panic("single quotes")
    if (
        items(
            entries(root.get("flow").unwrap()).get("list").unwrap()
        ).last().unwrap() != YamlValue.StringValue(value: "é☺")
    ): return panic("quoted escape")
    if (
        root.get(
            "url"
        ).unwrap() != YamlValue.StringValue(value: "https://example.org/#fragment")
    ): return panic("URL comment")
    if items(root.get("multiline").unwrap()).length() != 3: return panic(
        "multiline flow"
    )
    if (
        root.get(
            "text"
        ).unwrap() != YamlValue.StringValue(value: "a long continued sentence")
    ): return panic("plain folding")
    if value(parse(text: "'literal\\n'")) != YamlValue.StringValue(value: "literal\\n"): return panic(
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
        ).unwrap() != YamlValue.StringValue(value: "first # text\nsecond\n")
    ): return panic("literal block")
    if root.get("folded").unwrap() != YamlValue.StringValue(value: "hello world"): return panic(
        "folded block"
    )
    if root.get("keep").unwrap() != YamlValue.StringValue(value: "line\n\n"): return panic(
        "keep chomping"
    )
    if root.get("explicit").unwrap() != YamlValue.StringValue(value: "indented"): return panic(
        "explicit indentation"
    )
    if root.get("tabs").unwrap() != YamlValue.StringValue(value: "\tcontent"): return panic(
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
        config.get("retries").unwrap() != YamlValue.NumberValue(text: "5")
        or config.get("enabled").unwrap() != YamlValue.BoolValue(value: true)
    ): return panic("merge override")
    if root.get("alias").unwrap() != YamlValue.NumberValue(text: "42"): return panic(
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
        c.get("x").unwrap() != YamlValue.NumberValue(text: "1")
        or c.get("y").unwrap() != YamlValue.NumberValue(text: "4")
    ): return panic("merge precedence")

test "YAML documents BOM CRLF empty input and version directive":
    let root = value(
        parse(text: "\u{feff}%YAML 1.2\r\n---\r\na: 1\r\n...\r\n# done\r\n")
    )
    if entries(root).get("a").unwrap() != YamlValue.NumberValue(text: "1"): return panic(
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

                        let boundary = Error(value: cause)
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
    let limited: Result[YamlValue, YamlError] = error(cause: YamlError.LimitExceeded)
    let invalid: Result[YamlValue, YamlError] = error(cause: YamlError.InvalidInput)
    if (
        parse(
            text: "é",
            limits: limits(
                bytes: some(value: 1),
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
                depth: some(value: 2),
                values: none
            )
        ) != limited
    ): return panic("flow depth limit")
    if (
        parse(
            text: "a:\n  b: 1",
            limits: limits(
                bytes: none,
                depth: some(value: 2),
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
                values: some(value: 2)
            )
        ) != limited
    ): return panic("value limit")
    if (
        parse(
            text: "a: &a [1,2]\nb: *a",
            limits: limits(
                bytes: none,
                depth: none,
                values: some(value: 6)
            )
        ) != limited
    ): return panic("expanded alias limit")
    if (
        parse(
            text: "",
            limits: limits(
                bytes: some(value: 0),
                depth: some(value: 1),
                values: some(value: 1)
            )
        ) != parse(text: "", limits: none)
    ): return panic("empty exact limits")
    if (
        parse(
            text: "",
            limits: limits(
                bytes: none,
                depth: none,
                values: some(value: 0)
            )
        ) != limited
    ): return panic("zero values")
    if (
        parse(
            text: "",
            limits: limits(
                bytes: none,
                depth: some(value: -1),
                values: none
            )
        ) != invalid
    ): return panic("negative limit")
    if (
        parse(
            text: "[1,2]",
            limits: limits(
                bytes: some(value: 5),
                depth: some(value: 2),
                values: some(value: 3)
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
        if value(parse(text: text)) != YamlValue.NumberValue(text: text): return panic(
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
        if value(parse(text: text)) != YamlValue.StringValue(value: text): return panic(
            "plain scalar resolved incorrectly: {text}"
        )
