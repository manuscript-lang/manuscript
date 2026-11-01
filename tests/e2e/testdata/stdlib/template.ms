import compile, TemplateError from "@std/template.ms"
import expect_equal, expect_true, expect_error from "@std/test/test.ms"

test "compiled template owns runtime source and accepts absent budgets":
    var source = try "loaded \{x\}".repeat(1)
    let template = try compile(source, none)
    source = "changed"
    try expect_equal((try template.render({"x": "value"}, none)), "loaded value")
    try expect_equal((try (try compile("", 0)).render(Map[String, String](), 0)), "")

test "runtime templates compile once and render changing maps":
    let template = try compile("Hello \{ name \}/\{name\}! \{名\}")
    try expect_equal(
        (try template.render({"name": "Ada", "名": "🙂"})), "Hello Ada/Ada! 🙂"
    )
    try expect_equal(
        (try template.render({"name": "", "名": "", "unused": "ok"})), "Hello /! "
    )
    try expect_equal(
        (try template.render({"name": "\{other\}", "名": "<&>"})),
        "Hello \{other\}/\{other\}! <&>"
    )

test "runtime templates escape delimiters and treat punctuation as literal keys":
    let template = try compile("\\\{literal\\\} \\\\ \{a.b()\} \{two words\}")
    try expect_equal(
        (try template.render({"a.b()": "x", "two words": "y"})), "\{literal\} \\ x y"
    )
    try expect_equal((try (try compile("")).render(Map[String, String](), 0)), "")

test "runtime templates report missing variables at source byte offsets":
    let template = try compile("é\n\{  missing \}")
    let cause = try expect_error(template.render(Map[String, String]()))
    try expect_equal(cause, TemplateError.MissingVariable("missing", 6))
    try expect_true(cause.message().contains("byte 6"))
    try expect_equal((try template.render({"missing": ""})), "é\n")

test "runtime template syntax errors include source position and cause":
    for source in [
        "\{\}", "\{  \}", "left \}", "\{open", "bad\\x", "\{a\\b\}", "\{\{name\}"
    ]:
        let cause = try expect_error(compile(source))
        try expect_true(cause.message().contains("at byte "))
        try expect_true(cause.message().contains(source))

test "runtime template byte limits include literals and repeated substitutions":
    let template = try compile("é\{x\}\{x\}", 8)
    try expect_equal((try template.render({"x": "🙂"}, 10)), "é🙂🙂")
    try expect_equal(
        (try expect_error(template.render({"x": "🙂"}, 9))), TemplateError.LimitExceeded
    )
    try expect_equal(
        (try expect_error(template.render({"x": "🙂"}, 0))), TemplateError.LimitExceeded
    )
    try expect_equal(
        (try expect_error(template.render({"x": "🙂"}, -1))), TemplateError.InvalidInput
    )
    try expect_equal((try expect_error(compile("é", 1))), TemplateError.LimitExceeded)
    try expect_equal((try expect_error(compile("é", -1))), TemplateError.InvalidInput)
    try expect_equal((try (try compile("é", 2)).render(Map[String, String](), 2)), "é")
    try expect_equal((try (try compile("\{x\}")).render({"x": ""}, 0)), "")

test "template limits stop before looking up later missing keys":
    let template = try compile("ab\{missing\}")
    try expect_equal(
        (try expect_error(template.render(Map[String, String](), 1))),
        TemplateError.LimitExceeded
    )

    let repeated = try compile((try "\{x\}".repeat(10000)))
    let large = try "z".repeat(1000000)
    try expect_equal(
        (try expect_error(repeated.render({"x": large}, 1))),
        TemplateError.LimitExceeded
    )
