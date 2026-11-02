# conform: tags=control-flow,faults,formatter,interpolation,lists,maps,match,modules,mutation,optional,parser,records,stdlib-collections,stdlib-errors,stdlib-string,stdlib-testing,stdlib-yaml,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/yaml.ms
import expect_equal, expect_false, expect_ok, expect_true, fail from "@std/test/test.ms"
import from_scalars from "@std/string.ms"
import parse, stringify, YamlValue, YamlLimits from "@std/data/yaml.ms"

fn entries(value: YamlValue) (Map[String, YamlValue])!:
    match value:
        ObjectValue(values): return ok(values)
        _: return error(Error("expected YAML mapping"))

fn items(value: YamlValue) List[YamlValue]!:
    match value:
        ArrayValue(values): return ok(values)
        _: return error(Error("expected YAML sequence"))

fn limits(bytes: Int?, depth: Int?, values: Int?) YamlLimits?:
    return YamlLimits(max_bytes: bytes, max_depth: depth, max_values: values)

type ScalarCase:
    text: String
    expected: String

fn scalar(text: String, expected: String) Unit!:
    let root = parse(text: text) | try expect_ok | try entries
    if root.get("a").get() != YamlValue.StringValue(expected): return error(
        Error("scalar folding: {text}")
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
        root.get("a").get() | try expect_equal(YamlValue.StringValue("x\n\ny z"))
        root.get("b").get() | try expect_equal(YamlValue.NumberValue("1"))

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

    let limited: YamlValue! = error(
        Error("YAML limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
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

        cause.kind | try expect_equal(ErrorCategory.InvalidData)
        (
            (
                cause.details["line"].parse_int().get() < 1
                or cause.details["column"].parse_int().get() < 1
                or cause.details["reason"] == ""
            ) | try expect_false
        )

    let cause = match parse(text: "a: x\n\n  b: y"):
        error(cause): cause
        ok(_): return fail("indented mapping accepted as plain continuation")

    cause.kind | try expect_equal(ErrorCategory.InvalidData)
    (
        (
            cause.details["line"] != "3"
            or cause.details["column"] != "1"
        ) | try expect_false
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

        cause.kind | try expect_equal(ErrorCategory.InvalidData)
        (
            (
                cause.details["line"].parse_int().get() < 1
                or cause.details["column"].parse_int().get() < 1
                or cause.details["reason"] == ""
            ) | try expect_false
        )
        ((cause.message.starts_with("YAML ")) | try expect_true)

    for text in [
        "!custom value", "? complex\n: value", "%TAG ! tag:example.org\n---\na: 1"
    ]:
        let cause = match parse(text: text):
            ok(_): return fail("unsupported YAML accepted")
            error(cause): cause

        cause.kind | try expect_equal(ErrorCategory.Unsupported)

test "YAML limits cover root nested nodes aliases and exact bytes":
    let limited: YamlValue! = error(
        Error("YAML limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
    let invalid: YamlValue! = error(
        Error("invalid YAML input", kind: ErrorCategory.InvalidInput)
    )
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
        error(cause): return cause.message

test "YAML merge and block header errors name their own line":
    failure("<<: 1") | try expect_equal("YAML 1:1: merge requires mappings")
    failure("x: 1\ny: 2\n<<: 1") | try expect_equal("YAML 3:1: merge requires mappings")
    failure("a: |x") | try expect_equal("YAML 1:5: invalid block scalar header")
    failure("x: 1\ny: |x\nz: 3") | try expect_equal(
        "YAML 2:5: invalid block scalar header"
    )

test "YAML limits fields default to none":
    let limited: YamlValue! = error(
        Error("YAML limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
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
    let invalid: String! = error(
        Error("invalid YAML input", kind: ErrorCategory.InvalidInput)
    )
    let limited: String! = error(
        Error("YAML limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
    stringify(value: YamlValue.NumberValue("not a number")) | try expect_equal(invalid)

    let root = (parse(text: "a: 1") | try expect_ok)
    stringify(value: root, max_bytes: 3) | try expect_equal(limited)

    let exact: String! = ok("a: 1\n")
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
        (
            folded.get("run").get() != YamlValue.StringValue(
                "util/check.sh --flag value"
            )
        )
    )
    folded.get("next").get() | try expect_equal(YamlValue.NumberValue("1"))

    let list = parse(text: "- foo\n  bar\n-\n  baz\n  qux\n") | try expect_ok | try items
    list | try expect_equal(
        [YamlValue.StringValue("foo bar"), YamlValue.StringValue("baz qux")]
    )

    let anchored = parse(text: "a:\n  &x\n  k: 1\nb: *x\n") | try expect_ok | try entries
    anchored.get("a").get() | try expect_equal(anchored.get("b").get())
    try expect_false(
        (
            (try entries(anchored.get("b").get())).get(
                "k"
            ).get() != YamlValue.NumberValue("1")
        )
    )

test "YAML quoted merge key is an ordinary string key":
    let block = parse(text: "\"<<\": 1\nplain: 3\n") | try expect_ok | try entries
    block.get("<<").get() | try expect_equal(YamlValue.NumberValue("1"))
    block.length() | try expect_equal(2)

    let single = parse(text: "'<<': 2\n") | try expect_ok | try entries
    single.get("<<").get() | try expect_equal(YamlValue.NumberValue("2"))

    let flow = parse(text: "\{\"<<\": 1, a: 2\}\n") | try expect_ok | try entries
    flow.get("<<").get() | try expect_equal(YamlValue.NumberValue("1"))

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
    first.get("b").get() | try expect_equal(YamlValue.NumberValue("2"))
    (try items(list.get(1).clone())).length() | try expect_equal(2)
    (try entries(list.last().get())).get("d").get() | try expect_equal(
        YamlValue.NumberValue("4")
    )

fn repeated(text: String, count: Int) String:
    if count <= 0: return ""
    if count == 1: return text.clone()

    let half = repeated(text: text.clone(), count: count / 2)
    if count % 2 == 1: return half.concat(half).concat(text)

    return half.concat(half)

test "YAML long plain scalars and large mappings parse in linear time":
    let long = repeated(text: "x", count: 300000)
    let scalar = parse(text: "a: {long}") | try expect_ok | try entries
    scalar.get("a").get() | try expect_equal(YamlValue.StringValue(long))

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
    first.get("x").get() | try expect_equal(YamlValue.Null)
    first.get("y").get() | try expect_equal(YamlValue.NumberValue("1"))
    first.get("z").get() | try expect_equal(YamlValue.Null)

    let second = (try entries(root.get("b").get()))
    second.get("q").get() | try expect_equal(YamlValue.Null)

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
    double.get("a").get() | try expect_equal(YamlValue.StringValue(long.clone()))

    let single = parse(text: "a: '{long}'") | try expect_ok | try entries
    single.get("a").get() | try expect_equal(YamlValue.StringValue(long.clone()))

    let lines = repeated(text: "word\n  ", count: 20000)
    let plain = parse(text: "a: {lines}end") | try expect_ok | try entries
    try expect_false(
        (
            plain.get("a").get() != YamlValue.StringValue(
                repeated(text: "word ", count: 20000).concat("end")
            )
        )
    )

    let body = repeated(text: "  line\n", count: 20000)
    let literal = parse(text: "a: |\n{body}") | try expect_ok | try entries
    try expect_false(
        (
            literal.get("a").get() != YamlValue.StringValue(
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
