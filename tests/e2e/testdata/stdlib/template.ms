import expect_equal, expect_true from "@std/test/test.ms"
import parse, JsonValue from "@std/data/json.ms"
import compile, render, to_data, Template, TemplateError from "@std/text/template.ms"

fn data(text: String) JsonValue:
    return parse(text).get()

test "values paths and filters":
    let d = data(
        "\{\"name\":\"ada lovelace\",\"user\":\{\"tags\":[\"a\",\"b\"]\},\"n\":3\}"
    )
    try expect_equal(render("Hi \{\{ name | title \}\}!", d).get(), "Hi Ada Lovelace!")
    try expect_equal(
        render(
            "\{\{ user.tags.1 \}\} \{\{ user.tags | join(\"+\") \}\} \{\{ user.tags | length \}\}",
            d
        ).get(),
        "b a+b 2"
    )
    try expect_equal(
        render(
            "\{\{ missing | default(\"x\") \}\}|\{\{ name | upper | truncate(3) \}\}", d
        ).get(),
        "x|ADA..."
    )
    try expect_equal(render("\{\{ n \}\} \{\{ \"\{\{\" \}\}", d).get(), "3 \{\{")

test "conditions":
    let d = data("\{\"n\":3,\"s\":\"hi\",\"empty\":[],\"on\":true\}")
    try expect_equal(
        render(
            "\{\{ if n > 2 and on \}\}big\{\{ else \}\}small\{\{ end \}\}", d
        ).get(),
        "big"
    )
    try expect_equal(
        render(
            "\{\{ if empty \}\}a\{\{ else if s == \"hi\" \}\}b\{\{ else \}\}c\{\{ end \}\}",
            d
        ).get(),
        "b"
    )
    try expect_equal(render("\{\{ if not nothing \}\}y\{\{ end \}\}", d).get(), "y")
    try expect_equal(
        render("\{\{ if s | length >= 2 \}\}ok\{\{ end \}\}", d).get(), "ok"
    )

test "loops":
    let d = data("\{\"xs\":[\"a\",\"b\",\"c\"],\"m\":\{\"k\":1,\"j\":2\},\"none\":[]\}")
    try expect_equal(
        render(
            "\{\{ for x in xs \}\}\{\{ x \}\}\{\{ if not loop.last \}\},\{\{ end \}\}\{\{ end \}\}",
            d
        ).get(),
        "a,b,c"
    )
    try expect_equal(
        render(
            "\{\{ for i, x in xs \}\}\{\{ i \}\}\{\{ x \}\}\{\{ end \}\}", d
        ).get(),
        "0a1b2c"
    )
    try expect_equal(
        render(
            "\{\{ for k, v in m \}\}\{\{ k \}\}=\{\{ v \}\};\{\{ end \}\}", d
        ).get(),
        "k=1;j=2;"
    )
    try expect_equal(
        render("\{\{ for e in m \}\}\{\{ e.key \}\}\{\{ end \}\}", d).get(), "kj"
    )
    try expect_equal(
        render(
            "\{\{ for x in none \}\}x\{\{ else \}\}empty\{\{ end \}\}", d
        ).get(),
        "empty"
    )

test "html escaping and raw":
    let d = data("\{\"t\":\"<b>&\\\"'\"\}")
    try expect_equal(
        render("\{\{ t \}\}", d, html: true).get(), "&lt;b&gt;&amp;&#34;&#39;"
    )
    try expect_equal(render("\{\{ t | raw \}\}", d, html: true).get(), "<b>&\"'")
    try expect_equal(render("\{\{ t \}\}", d).get(), "<b>&\"'")
    try expect_equal(
        render("\{\{ t | escape \}\}", d, html: true).get(), "&lt;b&gt;&amp;&#34;&#39;"
    )

test "trim markers and comments":
    let d = data("\{\"a\":1\}")
    try expect_equal(render("x  \{\{- a -\}\}  y\{\{# note \}\}", d).get(), "x1y")

test "partials":
    let page = compile("[\{\{ include \"row\" \}\}]").get()
    var partials = Map[String, Template]()
    partials.add("row", compile("\{\{ a \}\}").get())
    try expect_equal(page.render(data("\{\"a\":7\}"), partials: partials).get(), "[7]")
    try expect_true(page.render(data("\{\"a\":7\}")).is_error())

test "strict missing values and limits":
    try expect_true(render("\{\{ nope \}\}", data("\{\}")).is_error())
    try expect_equal(render("[\{\{ nope \}\}]", data("\{\}")).get(""), "")

    let page = compile("\{\{ nope \}\}").get()
    try expect_equal(page.render(data("\{\}"), strict: false).get(), "")

    let big = compile("\{\{ for i in xs \}\}abcdefgh\{\{ end \}\}").get()
    try expect_true(big.render(data("\{\"xs\":[1,2,3,4]\}"), max_output: 10).is_error())

test "compile errors name the line":
    for bad in [
        "\{\{ if x \}\}", "\{\{ end \}\}", "\{\{ x | nope \}\}",
        "\{\{ for x xs \}\}\{\{ end \}\}", "\{\{ x", "\{\{ a ++ \}\}",
        "\{\{ for x in xs \}\}"
    ]:
        try expect_true(compile(bad).is_error())

    let failed = compile("a\n\n\{\{ if \}\}")
    try expect_true(failed.is_error())

test "typed data converts":
    let page = compile("\{\{ id \}\}:\{\{ tags | join(\",\") \}\}").get()
    let d = to_data(Row(id: 4, tags: ["x", "y"])).get()
    try expect_equal(page.render(d).get(), "4:x,y")

type Row:
    id: Int
    tags: List[String]
