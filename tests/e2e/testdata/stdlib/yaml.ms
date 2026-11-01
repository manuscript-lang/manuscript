import (
    expect_equal,
    expect_error,
    expect_false,
    expect_ok,
    expect_true,
    fail
) from "@std/test/test.ms"
import from_scalars from "@std/string.ms"
import TextError from "@std/core.ms"
import parse, stringify, YamlValue, YamlError, YamlLimits from "@std/data/yaml.ms"

fn entries(value: YamlValue) Map[String, YamlValue]!:
    match value:
        ObjectValue(values): return ok(values)
        _: return error(TextError("expected YAML mapping"))

fn items(value: YamlValue) List[YamlValue]!:
    match value:
        ArrayValue(values): return ok(values)
        _: return error(TextError("expected YAML sequence"))

fn limits(bytes: Int?, depth: Int?, values: Int?) YamlLimits?:
    return YamlLimits(max_bytes: bytes, max_depth: depth, max_values: values)

type ScalarCase:
    text: String
    expected: String

fn scalar(text: String, expected: String) Unit!:
    let root = parse(text: text) | try expect_ok | try entries
    if root["a"] != YamlValue.StringValue(expected): return error(
        TextError("scalar folding: {text}")
    )

    return ok(unit)

test "YAML issue 133 folded paragraph":
    (try scalar(text: "a: >\n  x\n  y\n\n  z\n", expected: "x y\nz\n"))

test "YAML issue 133 folded multiple blank lines":
    (try scalar(text: "a: >\n  x\n\n\n  z\n", expected: "x\n\nz\n"))

test "YAML issue 133 single quoted paragraph":
    (try scalar(text: "a: 'x\n\n  y'", expected: "x\ny"))

test "YAML issue 133 double quoted paragraphs":
    (try scalar(text: "a: \"x\n\n\n  y\"", expected: "x\n\ny"))

test "YAML issue 133 plain paragraph before sibling":
    (try scalar(text: "a: x\n\n  y\nb: 1", expected: "x\ny"))

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
            text: "a: \"x\n\n  \\\"y\\\"\" # outside", expected: "x\n\"y\""
        )
    ]
    for example in cases:
        for ending in ["\n", "\r\n", "\r"]:
            (
                try scalar(
                    text: (
                        example
                        .text
                        .replace(old: "\n", new: ending)
                    ),
                    expected: example.expected.clone()
                )
            )
    parse(text: "'x\n\n  y'") | try expect_ok | try expect_equal(
        YamlValue.StringValue("x\ny")
    )

    let flow = parse(text: "['x\n\n  y', \"z\\\n\n  w\"]") | try expect_ok | try items
    flow | try expect_equal(
        [YamlValue.StringValue("x\ny"), YamlValue.StringValue("z\nw")]
    )

test "YAML folded and literal blocks respect paragraphs indentation and chomping":
    let cases = [
        ScalarCase(text: "a: >-\n  x\n \n  y\n\n", expected: "x\ny"),
        ScalarCase(text: "a: >\n  x\n\n  y\n\n\n", expected: "x\ny\n"),
        ScalarCase(text: "a: >+\n  x\n\n  y\n\n\n", expected: "x\ny\n\n\n"),
        ScalarCase(text: "a: >2-\n  x\n\n\n  y\n", expected: "x\n\ny"),
        ScalarCase(
            text: "a: >\n  x\n\n    y\n\n  z\n", expected: "x\n\n  y\n\nz\n"
        ),
        ScalarCase(text: "a: >2-\n  x\n   \n  y\n", expected: "x\n \ny"),
        ScalarCase(
            text: "a: >2-\n  x\n\n  \ty\n\n  z\n", expected: "x\n\n\ty\n\nz"
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
            (
                try scalar(
                    text: (
                        example
                        .text
                        .replace(old: "\n", new: ending)
                    ),
                    expected: example.expected.clone()
                )
            )

test "YAML plain paragraphs retain boundaries and nested collections":
    for ending in ["\n", "\r\n", "\r"]:
        let text = "a: x  \n \t\n\n  y \t\n  z\n\nb: 1\n"
        let root = (
            try entries(
                (
                    parse(
                        text: text.replace(
                            old: "\n", new: ending
                        )
                    ) | try expect_ok
                )
            )
        )
        root["a"] | try expect_equal(YamlValue.StringValue("x\n\ny z"))
        root["b"] | try expect_equal(YamlValue.NumberValue("1"))

    let root = parse(text: "a:\n  - x\n\n    y\n  - z\nb: 1\n") | try expect_ok | try entries
    try expect_false(
        (
            (try items(root.get("a").get())) != [
                YamlValue.StringValue("x\ny"), YamlValue.StringValue("z")
            ]
        )
    )
    (try scalar(text: "a: x\n\n# comment\nb: 1\n", expected: "x"))
    (try scalar(text: "a: x\n\n", expected: "x"))

test "YAML blank line folding retains byte node and malformed input contracts":
    let text = "a: \"é\r\n\r\n  y\"\r\n"
    let expected = (parse(text: text) | try expect_ok)
    try expect_false(
        (
            (
                parse(
                    text: text,
                    limits: limits(
                        bytes: text.byte_length(), depth: 2, values: 2
                    )
                ) | try expect_ok
            ) != expected
        )
    )

    let limited: YamlValue!YamlError = error(YamlError.LimitExceeded)
    try expect_false(
        (
            parse(
                text: text,
                limits: limits(
                    bytes: text.byte_length() - 1, depth: none, values: none
                )
            ) != limited
        )
    )
    try expect_false(
        (
            parse(
                text: text, limits: limits(bytes: none, depth: none, values: 1)
            ) != limited
        )
    )

    for malformed in [
        "a: 'x\n\n  y", "a: \"x\n\n  y", "a: \"x\\\n\n  y\\q\"", "a: x\n\n  b: y",
        "a: x\n\n  - y", "a: x\n\n \ty", "a: x\n # comment\n  y", "a: >--\n\n  x",
        "a: >\n  x\n \t\n  y", "a: >2\n  x\n y"
    ]:
        let cause = match parse(text: malformed):
            ok(_): return fail("malformed multiline scalar accepted: {malformed}")
            error(cause): cause

        match cause:
            InvalidData(line, column, reason):
                ((line < 1 or column < 1 or reason == "") | try expect_false)
            _: return fail("wrong multiline error")

    let cause = match parse(text: "a: x\n\n  b: y"):
        error(cause): cause
        ok(_): return fail("indented mapping accepted as plain continuation")

    match cause:
        InvalidData(line, column, _):
            ((line != 3 or column != 1) | try expect_false)
        _: return fail("wrong continuation error")

test "YAML block mappings sequences exact scalars and core schema":
    let text = "name: é🙂\nlarge: 9007199254740993\nboolean: TRUE\nlegacy: yes\ndate: 2024-02-29\nempty:\nvalues:\n- null\n- false\n- 0xFF\npeople:\n  - name: Ada\n    age: 37\n  - name: Grace\n    skills:\n      - compilers\n"
    let root = parse(text: text) | try expect_ok | try entries
    root["name"] | try expect_equal(YamlValue.StringValue("é🙂"))
    root["large"] | try expect_equal(YamlValue.NumberValue("9007199254740993"))
    root["boolean"] | try expect_equal(YamlValue.BoolValue(true))
    root["legacy"] | try expect_equal(YamlValue.StringValue("yes"))
    root["date"] | try expect_equal(YamlValue.StringValue("2024-02-29"))
    root["empty"] | try expect_equal(YamlValue.Null)
    try expect_false(
        (
            (try items(root.get("values").get())) != [
                YamlValue.Null, YamlValue.BoolValue(false),
                YamlValue.NumberValue("0xFF")
            ]
        )
    )

    let people = (try items(root.get("people").get()))
    try expect_false(
        (
            people.length() != 2
            or (try entries(people.first().get())).get(
                "age"
            ).get() != YamlValue.NumberValue("37")
        )
    )
    try expect_false(
        (
            (
                try items(
                    (try entries(people.last().get())).get(
                        "skills"
                    ).get()
                )
            ).first().get() != YamlValue.StringValue("compilers")
        )
    )

test "YAML flow collections quotes escapes comments and multiline values":
    let root = (
        try entries(
            (
                parse(
                    text: "flow: \{name: 'it''s # fine', list: [true, 2, \"é\\u263A\",],\}\nurl: https://example.org/#fragment # comment\nquoted: \"hash # colon: brace \{\}\"\nmultiline: [1,\n  2, # comment\n  3]\ntext: a long\n  continued sentence\n"
                ) | try expect_ok
            )
        )
    )
    try expect_false(
        (
            (try entries(root.get("flow").get())).get(
                "name"
            ).get() != YamlValue.StringValue("it's # fine")
        )
    )
    try expect_false(
        (
            (
                try items(
                    (try entries(root.get("flow").get())).get(
                        "list"
                    ).get()
                )
            ).last().get() != YamlValue.StringValue("é☺")
        )
    )
    try expect_false(
        (root["url"] != YamlValue.StringValue("https://example.org/#fragment"))
    )
    (try items(root.get("multiline").get())).length() | try expect_equal(3)
    root["text"] | try expect_equal(YamlValue.StringValue("a long continued sentence"))
    parse(text: "'literal\\n'") | try expect_ok | try expect_equal(
        YamlValue.StringValue("literal\\n")
    )

test "YAML literal folded and chomped block scalars preserve content":
    let root = (
        try entries(
            (
                parse(
                    text: "literal: |\n  first # text\n  second\nfolded: >-\n  hello\n  world\nkeep: |+\n  line\n\nexplicit: |2-\n  indented\ntabs: |-\n  \tcontent\n"
                ) | try expect_ok
            )
        )
    )
    (
        root["literal"] | try expect_equal(
            YamlValue.StringValue("first # text\nsecond\n")
        )
    )
    root["folded"] | try expect_equal(YamlValue.StringValue("hello world"))
    root["keep"] | try expect_equal(YamlValue.StringValue("line\n\n"))
    root["explicit"] | try expect_equal(YamlValue.StringValue("indented"))
    root["tabs"] | try expect_equal(YamlValue.StringValue("\tcontent"))

test "YAML anchors aliases merge keys and override precedence":
    let text = "defaults: &defaults\n  retries: 3\n  enabled: true\ncopy: *defaults\nconfig:\n  <<: *defaults\n  retries: 5\nscalar: &answer 42\nalias: *answer\nflow: &flow [1, 2]\nflow_alias: *flow\n"
    let root = parse(text: text) | try expect_ok | try entries
    root["defaults"] | try expect_equal(root["copy"])

    let config = (try entries(root.get("config").get()))
    try expect_false(
        (
            config["retries"] != YamlValue.NumberValue("5")
            or config["enabled"] != YamlValue.BoolValue(true)
        )
    )
    root["alias"] | try expect_equal(YamlValue.NumberValue("42"))
    root["flow_alias"] | try expect_equal((root["flow"]))

    let merged = (
        try entries(
            (
                parse(
                    text: "a: &a \{x: 1\}\nb: &b \{x: 2, y: 3\}\nc: \{<<: [*a, *b], y: 4\}\n"
                ) | try expect_ok
            )
        )
    )
    let c = (try entries(merged.get("c").get()))
    try expect_false(
        (
            c["x"] != YamlValue.NumberValue("1")
            or c["y"] != YamlValue.NumberValue("4")
        )
    )

test "YAML documents BOM CRLF empty input and version directive":
    let root = (
        parse(
            text: "\u{feff}%YAML 1.2\r\n---\r\na: 1\r\n...\r\n# done\r\n"
        ) | try expect_ok
    )
    (try entries(root))["a"] | try expect_equal(YamlValue.NumberValue("1"))
    parse(text: "# comment\n") | try expect_ok | try expect_equal(YamlValue.Null)
    parse(text: "---\n...\n") | try expect_ok | try expect_equal(YamlValue.Null)
    (try items((parse(text: "- - 1\n  - 2\n- - 3\n") | try expect_ok))).length() | try expect_equal(
        2
    )

test "YAML document markers end a root plain scalar":
    parse(text: "x\n...\n") | try expect_ok | try expect_equal(
        YamlValue.StringValue("x")
    )
    parse(text: "x\ny\n...\n") | try expect_ok | try expect_equal(
        YamlValue.StringValue("x y")
    )
    parse(text: "null\n...\n") | try expect_ok | try expect_equal(YamlValue.Null)
    try expect_true(parse(text: "x\n---\ny\n").is_error())

test "YAML plain scalars cannot start with an indicator":
    for text in [
        "a: - b\n", "a: -\n", "a: ? b\n", "a: @x\n", "a: `x\n", "a: ]\n", "a: ,\n",
        "a: %d\n", "- ? x\n"
    ]:
        try expect_true(parse(text: text).is_error())

    let _ = try expect_ok(parse(text: "a: -1\nb: -a\nc: ?x\nd: [-1, ?y, :z]\n"))
    let explicit = parse(text: "\{? a : 1\}\n") | try expect_error
    try expect_equal(
        explicit,
        YamlError.UnsupportedFeature(1, "explicit mapping keys are unsupported")
    )

test "YAML rejects duplicates invalid indentation malformed flow and aliases":
    for text in [
        "a: 1\na: 2", "\{a: 1, a: 2\}", "a:\n\tb: 1", "a: 1\n  b: 2",
        "a:\n  b: 1\n c: 2", "[1,", "[1,,2]", "\{a: 1 b: 2\}", "\"\\uD800\"", "\"\\q\"",
        "'unterminated", "*missing", "a: &loop [*loop]", "<<: 1",
        "---\na: 1\n---\nb: 2", "a: |0\n  text"
    ]:
        let cause = match parse(text: text):
            ok(_): return fail("invalid YAML accepted: {text}")
            error(cause): cause

        match cause:
            InvalidData(line, column, reason):
                (line < 1 or column < 1 or reason == "") | try expect_false

                let boundary: Error = cause
                ((boundary.message().starts_with("YAML ")) | try expect_true)
            _: return fail("wrong YAML error")

    for text in [
        "!custom value", "? complex\n: value", "%TAG ! tag:example.org\n---\na: 1"
    ]:
        let cause = match parse(text: text):
            ok(_): return fail("unsupported YAML accepted")
            error(cause): cause

        match cause:
            UnsupportedFeature(_, _): let _expected = unit
            _: return fail("expected unsupported feature")

test "YAML limits cover root nested nodes aliases and exact bytes":
    let limited: YamlValue!YamlError = error(YamlError.LimitExceeded)
    let invalid: YamlValue!YamlError = error(YamlError.InvalidInput)
    try expect_false(
        (
            parse(
                text: "é", limits: limits(bytes: 1, depth: none, values: none)
            ) != limited
        )
    )
    try expect_false(
        (
            parse(
                text: "[[[]]]", limits: limits(bytes: none, depth: 2, values: none)
            ) != limited
        )
    )
    try expect_false(
        (
            parse(
                text: "a:\n  b: 1", limits: limits(bytes: none, depth: 2, values: none)
            ) != limited
        )
    )
    try expect_false(
        (
            parse(
                text: "[1,2]", limits: limits(bytes: none, depth: none, values: 2)
            ) != limited
        )
    )
    try expect_false(
        (
            parse(
                text: "a: &a [1,2]\nb: *a",
                limits: limits(bytes: none, depth: none, values: 6)
            ) != limited
        )
    )
    try expect_false(
        (
            parse(
                text: "", limits: limits(bytes: 0, depth: 1, values: 1)
            ) != parse(text: "")
        )
    )
    parse(text: "", limits: limits(bytes: none, depth: none, values: 0)) | try expect_equal(
        limited
    )
    try expect_false(
        (
            parse(
                text: "", limits: limits(bytes: none, depth: -1, values: none)
            ) != invalid
        )
    )
    try expect_false(
        (
            parse(
                text: "[1,2]", limits: limits(bytes: 5, depth: 2, values: 3)
            ) != parse(text: "[1,2]")
        )
    )

test "YAML exact decimal syntax does not depend on binary64 conversion":
    for text in [".5", "1.", "1.e2", "1e999999", ".Inf", ".NAN", "-0", "0001"]:
        if (parse(text: text) | try expect_ok) != YamlValue.NumberValue(text.clone()): return fail(
            "YAML number treated as string: {text}"
        )
    for text in [
        ".", "1e", "1_000", "+0xFF", "-.nan", ".iNF", "it's plain",
        "text [with] punctuation"
    ]:
        if (parse(text: text) | try expect_ok) != YamlValue.StringValue(text.clone()): return fail(
            "plain scalar resolved incorrectly: {text}"
        )

fn failure(text: String) String:
    match parse(text: text):
        ok(_): return "accepted"
        error(cause): return cause.message()

test "YAML merge and block header errors name their own line":
    failure("<<: 1") | try expect_equal("YAML 1:1: merge requires mappings")
    failure("x: 1\ny: 2\n<<: 1") | try expect_equal("YAML 3:1: merge requires mappings")
    failure("a: |x") | try expect_equal("YAML 1:5: invalid block scalar header")
    failure("x: 1\ny: |x\nz: 3") | try expect_equal(
        "YAML 2:5: invalid block scalar header"
    )

test "YAML limits fields default to none":
    let limited: YamlValue!YamlError = error(YamlError.LimitExceeded)
    parse(text: "a: 1", limits: YamlLimits(max_bytes: 2)) | try expect_equal(limited)
    parse(text: "a: 1", limits: YamlLimits()) | try expect_equal(parse(text: "a: 1"))

test "YAML stringify round trips scalars sequences and mappings":
    let source = "title: \"é🙂 \\\"q\\\" \\t tab\"\nnone: null\nflag: true\nint: -42\nfloat: 1.5e3\nlist:\n  - 1\n  - two\n  - [3, 4]\n  - a: 1\n    b: [x, y]\nempty_list: []\nempty_map: \{\}\n\"odd key\": 1\n\"true\": 2\nnested:\n  deep:\n    value: ok\n"
    let parsed = (parse(text: source) | try expect_ok)
    let text = (stringify(value: parsed) | try expect_ok)
    parse(text: text) | try expect_ok | try expect_equal(parsed)
    stringify(value: (parse(text: text) | try expect_ok)) | try expect_ok | try expect_equal(
        text
    )

test "YAML stringify validates numbers and honors max_bytes":
    let invalid: String!YamlError = error(YamlError.InvalidInput)
    let limited: String!YamlError = error(YamlError.LimitExceeded)
    stringify(value: YamlValue.NumberValue("not a number")) | try expect_equal(invalid)

    let root = (parse(text: "a: 1") | try expect_ok)
    stringify(value: root, max_bytes: 3) | try expect_equal(limited)

    let exact: String!YamlError = ok("a: 1\n")
    stringify(value: root, max_bytes: 5) | try expect_equal(exact)
    stringify(value: root, max_bytes: -1) | try expect_equal(invalid)

test "YAML scalars and anchors on their own line continue at the same indentation":
    let folded = (
        try entries(
            (
                parse(
                    text: "run:\n  util/check.sh\n  --flag value\nnext: 1\n"
                ) | try expect_ok
            )
        )
    )
    try expect_false(
        (folded["run"] != YamlValue.StringValue("util/check.sh --flag value"))
    )
    folded["next"] | try expect_equal(YamlValue.NumberValue("1"))

    let list = parse(text: "- foo\n  bar\n-\n  baz\n  qux\n") | try expect_ok | try items
    list | try expect_equal(
        [YamlValue.StringValue("foo bar"), YamlValue.StringValue("baz qux")]
    )

    let anchored = parse(text: "a:\n  &x\n  k: 1\nb: *x\n") | try expect_ok | try entries
    anchored["a"] | try expect_equal(anchored["b"])
    try expect_false(
        (
            (try entries(anchored.get("b").get())).get(
                "k"
            ).get() != YamlValue.NumberValue("1")
        )
    )

test "YAML quoted merge key is an ordinary string key":
    let block = parse(text: "\"<<\": 1\nplain: 3\n") | try expect_ok | try entries
    block["<<"] | try expect_equal(YamlValue.NumberValue("1"))
    block.length() | try expect_equal(2)

    let single = parse(text: "'<<': 2\n") | try expect_ok | try entries
    single["<<"] | try expect_equal(YamlValue.NumberValue("2"))

    let flow = parse(text: "\{\"<<\": 1, a: 2\}\n") | try expect_ok | try entries
    flow["<<"] | try expect_equal(YamlValue.NumberValue("1"))

    let merged = (
        try entries(
            (
                parse(
                    text: "base: &b \{x: 1\}\nm:\n  <<: *b\n  y: 2\n"
                ) | try expect_ok
            )
        )
    )
    try expect_false(
        (
            (try entries(merged.get("m").get())).get(
                "x"
            ).get() != YamlValue.NumberValue("1")
        )
    )

    let original = (parse(text: "\"<<\": 1\n") | try expect_ok)
    try expect_equal(
        (
            parse(
                text: (stringify(value: original) | try expect_ok)
            ) | try expect_ok
        ),
        original
    )

test "YAML plain scalars continued inside flow collections fold their line breaks":
    let root = (
        try entries(
            (
                parse(
                    text: "a: [x\n  y, z]\nb: \{k: one\n    two\}\nc: [p\n  q\n\n  r]\n"
                ) | try expect_ok
            )
        )
    )
    try expect_false(
        (
            (try items(root.get("a").get())) != [
                YamlValue.StringValue("x y"), YamlValue.StringValue("z")
            ]
        )
    )
    try expect_false(
        (
            (try entries(root.get("b").get())).get(
                "k"
            ).get() != YamlValue.StringValue("one two")
        )
    )
    (try items(root.get("c").get())) | try expect_equal(
        [YamlValue.StringValue("p q\nr")]
    )

test "YAML document start marker accepts same-line content":
    parse(text: "--- a") | try expect_ok | try expect_equal(YamlValue.StringValue("a"))
    (try items((parse(text: "--- [1, 2]") | try expect_ok))).length() | try expect_equal(
        2
    )
    parse(text: "--- # note\na: 1") | try expect_ok | try expect_equal(
        (parse(text: "a: 1") | try expect_ok)
    )

test "YAML compact mapping after a sequence marker follows the marker's spacing":
    let root = (
        parse(
            text: "-   a: 1\n    b: 2\n-  - x\n   - y\n- c: 3\n  d: 4\n"
        ) | try expect_ok
    )
    let list = (try items(root))
    list.length() | try expect_equal(3)

    let first = (try entries(list.first().get()))
    first["b"] | try expect_equal(YamlValue.NumberValue("2"))
    (try items(list.get(1).clone())).length() | try expect_equal(2)
    (try entries(list.last().get()))["d"] | try expect_equal(YamlValue.NumberValue("4"))

fn repeated(text: String, count: Int) String:
    if count <= 0: return ""
    if count == 1: return text.clone()

    let half = repeated(text: text.clone(), count: count / 2)
    if count % 2 == 1: return half.concat(half).concat(text)

    return half.concat(half)

test "YAML long plain scalars and large mappings parse in linear time":
    let long = repeated(text: "x", count: 300000)
    let scalar = parse(text: "a: {long}") | try expect_ok | try entries
    scalar["a"] | try expect_equal(YamlValue.StringValue(long))

    var keys = ""
    for index in 0..30000:
        keys = keys.concat("k{index}: 1\n")
    (try entries((parse(text: keys) | try expect_ok))).length() | try expect_equal(
        30000
    )

    match parse(text: keys.concat("k7: 2\n")):
        ok(_): return fail("duplicate key after many keys")
        error(_): return

test "YAML flow mapping keys without a colon map to null":
    let root = parse(text: "a: \{x, y: 1, z\}\nb: \{\"q\", r: [1]\}") | try expect_ok | try entries
    let first = (try entries(root.get("a").get()))
    first.length() | try expect_equal(3)
    first["x"] | try expect_equal(YamlValue.Null)
    first["y"] | try expect_equal(YamlValue.NumberValue("1"))
    first["z"] | try expect_equal(YamlValue.Null)

    let second = (try entries(root.get("b").get()))
    second["q"] | try expect_equal(YamlValue.Null)

    match parse(text: "\{x, x\}"):
        ok(_): return fail("duplicate null keys")
        error(_): let _ignored = unit

    let limited = limits(bytes: none, depth: none, values: 2)

    match parse(text: "\{a, b, c\}", limits: limited):
        ok(_): return fail("null keys count against the value limit")
        error(_): let _ignored = unit

test "YAML long quoted block and multi-line scalars decode and stringify in linear time":
    let long = repeated(text: "x", count: 300000)
    let double = parse(text: "a: \"{long}\"") | try expect_ok | try entries
    double["a"] | try expect_equal(YamlValue.StringValue(long.clone()))

    let single = parse(text: "a: '{long}'") | try expect_ok | try entries
    single["a"] | try expect_equal(YamlValue.StringValue(long.clone()))

    let lines = repeated(text: "word\n  ", count: 20000)
    let plain = parse(text: "a: {lines}end") | try expect_ok | try entries
    try expect_false(
        (
            plain["a"] != YamlValue.StringValue(
                repeated(text: "word ", count: 20000).concat("end")
            )
        )
    )

    let body = repeated(text: "  line\n", count: 20000)
    let literal = parse(text: "a: |\n{body}") | try expect_ok | try entries
    try expect_false(
        (
            literal["a"] != YamlValue.StringValue(
                repeated(text: "line\n", count: 20000)
            )
        )
    )

    let root = (parse(text: "a: \"{long}\"") | try expect_ok)
    parse(text: (stringify(value: root) | try expect_ok)) | try expect_ok | try expect_equal(
        root
    )

test "YAML block scalar chomping counts every trailing line break":
    (try scalar(text: "a: |\n  x\n\n\n\nb: 1", expected: "x\n"))
    (try scalar(text: "a: |-\n  x\n\n\n\nb: 1", expected: "x"))
    (try scalar(text: "a: |+\n  x\n\n\n\nb: 1", expected: "x\n\n\n\n"))
    (try scalar(text: "a: >-\n  x\n\n\n", expected: "x"))
    (try scalar(text: "a: |\n\n\nb: 1", expected: ""))
    (try scalar(text: "a: |+\n\n\nb: 1", expected: "\n\n"))

test "YAML compact nested sequences resume each level and parse deep chains in linear time":
    let small = (
        try items(
            (
                parse(
                    text: "- - - x\n    - y\n  - z\n- - 1\n  - - 2\n    - 3\n-\n  - -\n    - a: 1\n      b: 2\n"
                ) | try expect_ok
            )
        )
    )
    small.length() | try expect_equal(3)

    let first = (try items(small.first().get()))
    first.length() | try expect_equal(2)
    (try items(first.first().get())).length() | try expect_equal(2)
    first.last().get() | try expect_equal(YamlValue.StringValue("z"))

    let depth = 3000
    var source = "{repeated(text: "- ", count: depth)}x\n"
    var root = (parse(text: source, limits: YamlLimits()) | try expect_ok)

    for level in 1..depth:
        let inner = (try items(root))
        inner.length() | try expect_equal(1)
        root = inner.first().get()

    (try items(root)) | try expect_equal([YamlValue.StringValue("x")])

test "YAML stringify escapes C1 control characters so output reparses":
    for code in [127, 128, 133, 150, 159]:
        let text = try from_scalars([97, code, 98])
        let encoded = try stringify(YamlValue.StringValue(text.clone()))
        try expect_equal((try parse(encoded)), YamlValue.StringValue(text))

test "YAML parse without limits stops alias bombs and deep nesting":
    var bomb = "l0: &l0 [x, x, x, x, x, x, x, x, x, x]\n"
    for i in 0..9:
        bomb = bomb + "l{i+1}: &l{i+1} [" + "*l{i}, ".repeat(9).get() + "*l{i}]\n"

    let bombed = parse(bomb)
    if bombed.is_ok(): return fail(
        "alias expansion over the default value budget was accepted"
    )

    let deep = "[".repeat(20000).get() + "]".repeat(20000).get()
    let nested = parse(deep)
    if nested.is_ok(): return fail("nesting over the default depth was accepted")

    let lifted = parse(deep, YamlLimits())
    try expect_true(lifted.is_ok())

test "YAML plain scalars and keys keep Unicode spaces":
    (try scalar(text: "a: x\u{a0}\n", expected: "x\u{a0}"))
    (try scalar(text: "a: \u{3000}x\n", expected: "\u{3000}x"))

    let root = parse(text: "k\u{a0}: 1\n") | try expect_ok | try entries
    try expect_true(root.contains("k\u{a0}"))
