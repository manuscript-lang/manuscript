import expect_equal, expect_error, expect_ok, fail from "@std/test/test.ms"
import parse, YamlValue from "@std/data/yaml.ms"

fn rejects_continuation(text: String) Unit!Error:
    let cause = parse(text) | try expect_error
    if cause.kind != ErrorCategory.InvalidData:
        return fail("expected InvalidData, got {cause}")

    return expect_equal(
        cause.details["reason"], "unexpected indentation or additional document"
    )

test "YAML inline comments end root and mapping plain scalars":
    try rejects_continuation("first # comment\nnext")
    try rejects_continuation("a: first # comment\n  next")
    try rejects_continuation("a: &value first # comment\n  next")

test "YAML inline comments end later plain continuation lines":
    try rejects_continuation("first\nnext # comment\nlast")
    try rejects_continuation("a: first\n  next # comment\n  last")

test "YAML compact mapping rewrites retain terminating comments":
    try rejects_continuation("- key: first # comment\n    next")
    try rejects_continuation("-   key: first # comment\n      next")
    try rejects_continuation("- key: café # comment\n    next")

test "YAML nested compact sequences retain terminating comments":
    try rejects_continuation("- - first # comment\n    next")
    try rejects_continuation("- - - first # comment\n      next")
    try rejects_continuation("- - key: first # comment\n      next")

test "YAML plain hashes without separation keep folding":
    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("first#hash next#hash last"))
    parse("a: first#hash\n  next#hash\n  last") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML comment-terminated values retain following siblings":
    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("first"))
    values.add("b", YamlValue.StringValue("second"))
    parse("a: first # comment\nb: second") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )
    parse("- first # comment\n- second") | try expect_ok | try expect_equal(
        YamlValue.ArrayValue(
            [
                YamlValue.StringValue("first"), YamlValue.StringValue("second")
            ]
        )
    )

test "YAML compact mapping comments preserve Unicode siblings":
    var values = Map[String, YamlValue]()
    values.add("clé", YamlValue.StringValue("café"))
    values.add("next", YamlValue.StringValue("ok"))
    parse("- clé: café # comment\n  next: ok") | try expect_ok | try expect_equal(
        YamlValue.ArrayValue([YamlValue.ObjectValue(values)])
    )

test "YAML empty values with comments may begin on a later line":
    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("next"))
    parse("a: # comment\n  next") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )
    parse("- # comment\n  next") | try expect_ok | try expect_equal(
        YamlValue.ArrayValue([YamlValue.StringValue("next")])
    )

test "YAML quoted and flow hashes retain their scalar behavior":
    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("first # hash next"))
    parse("a: \"first # hash\n  next\"") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )
    parse("[first, # comment\n next]") | try expect_ok | try expect_equal(
        YamlValue.ArrayValue(
            [YamlValue.StringValue("first"), YamlValue.StringValue("next")]
        )
    )

fn rejects_flow_continuation(text: String, reason: String) Unit!Error:
    let cause = parse(text) | try expect_error
    if cause.kind != ErrorCategory.InvalidData:
        return fail("expected InvalidData, got {cause}")

    return expect_equal(cause.details["reason"], reason)

test "YAML flow sequence comments terminate plain scalar text":
    for source in [
        "[first # comment\n next]", "[\n first # comment\n next]",
        "[first\n # comment\n next]", "[café # comment\n next]",
        "&items [first # comment\n next]", "- - [first # comment\n     next]"
    ]:
        try rejects_flow_continuation(source, "expected sequence comma")

test "YAML flow mapping comments terminate plain scalar values":
    for source in ["\{a: first # comment\n next\}", "\{a: first\n # comment\n next\}"]:
        try rejects_flow_continuation(source, "expected mapping comma")

test "YAML flow comments preserve comma and closing boundaries":
    let expected = YamlValue.ArrayValue(
        [YamlValue.StringValue("first"), YamlValue.StringValue("next")]
    )
    parse("[first, # comment\n next]") | try expect_ok | try expect_equal(expected)
    parse("[first # comment\n ,next]") | try expect_ok | try expect_equal(expected)
    parse("[first # comment\n ]") | try expect_ok | try expect_equal(
        YamlValue.ArrayValue([YamlValue.StringValue("first")])
    )

    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("first"))
    values.add("b", YamlValue.StringValue("next"))
    parse("\{a: first # comment\n , b: next\}") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

test "YAML comments before flow values preserve empty starts":
    parse("[ # comment\n first]") | try expect_ok | try expect_equal(
        YamlValue.ArrayValue([YamlValue.StringValue("first")])
    )

    var values = Map[String, YamlValue]()
    values.add("a", YamlValue.StringValue("first"))
    parse("\{a: # comment\n first\}") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(values)
    )

    var empty = Map[String, YamlValue]()
    empty.add("a", YamlValue.Null)
    parse("\{a: # comment\n\}") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(empty.clone())
    )
    parse("\{a # comment\n\}") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(empty.clone())
    )
    empty.add("b", YamlValue.Null)
    parse("\{a # comment\n , b\}") | try expect_ok | try expect_equal(
        YamlValue.ObjectValue(empty)
    )

test "YAML flow comment stops follow quoted and alias nodes":
    let expected = YamlValue.ArrayValue(
        [
            YamlValue.StringValue("café"), YamlValue.StringValue("quoted # hash"),
            YamlValue.StringValue("café"), YamlValue.StringValue("last")
        ]
    )
    parse(
        "&items [&a café # first\n, \"quoted # hash\" # second\n, *a # third\n, last]"
    ) | try expect_ok | try expect_equal(expected)
