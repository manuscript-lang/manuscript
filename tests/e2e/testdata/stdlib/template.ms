import (
	JsonValue, parse from "@std/data/json.ms",
	expect_equal, expect_true from "@std/test/test.ms",
	RenderOptions, Template, compile, render, to_data from "@std/text/template.ms",
)

fn data(text: String) JsonValue:
	return parse(text).get()

test "values paths and filters":
	d := data(
		"\{\"name\":\"ada lovelace\",\"user\":\{\"tags\":[\"a\",\"b\"]\},\"n\":3\}"
	)
	expect_equal(render("Hi \{\{ name | title \}\}!", d).get(), "Hi Ada Lovelace!")?
	expect_equal(
		render(
			"\{\{ user.tags.1 \}\} \{\{ user.tags | join(\"+\") \}\} \{\{ user.tags | length \}\}",
			d,
		).get(),
		"b a+b 2",
	)?
	expect_equal(
		render(
			"\{\{ missing | default(\"x\") \}\}|\{\{ name | upper | truncate(3) \}\}",
			d,
		).get(),
		"x|ADA...",
	)?
	expect_equal(render("\{\{ n \}\} \{\{ \"\{\{\" \}\}", d).get(), "3 \{\{")?

test "conditions":
	d := data("\{\"n\":3,\"s\":\"hi\",\"empty\":[],\"on\":true\}")
	expect_equal(
		render(
			"\{\{ if n > 2 and on \}\}big\{\{ else \}\}small\{\{ end \}\}",
			d,
		).get(),
		"big",
	)?
	expect_equal(
		render(
			"\{\{ if empty \}\}a\{\{ else if s == \"hi\" \}\}b\{\{ else \}\}c\{\{ end \}\}",
			d,
		).get(),
		"b",
	)?
	expect_equal(render("\{\{ if not nothing \}\}y\{\{ end \}\}", d).get(), "y")?
	expect_equal(render("\{\{ if s | length >= 2 \}\}ok\{\{ end \}\}", d).get(), "ok")?

test "loops":
	d := data("\{\"xs\":[\"a\",\"b\",\"c\"],\"m\":\{\"k\":1,\"j\":2\},\"none\":[]\}")
	expect_equal(
		render(
			"\{\{ for x in xs \}\}\{\{ x \}\}\{\{ if not loop.last \}\},\{\{ end \}\}\{\{ end \}\}",
			d,
		).get(),
		"a,b,c",
	)?
	expect_equal(
		render(
			"\{\{ for i, x in xs \}\}\{\{ i \}\}\{\{ x \}\}\{\{ end \}\}",
			d,
		).get(),
		"0a1b2c",
	)?
	expect_equal(
		render(
			"\{\{ for k, v in m \}\}\{\{ k \}\}=\{\{ v \}\};\{\{ end \}\}",
			d,
		).get(),
		"k=1;j=2;",
	)?
	expect_equal(
		render("\{\{ for e in m \}\}\{\{ e.key \}\}\{\{ end \}\}", d).get(),
		"kj",
	)?
	expect_equal(
		render(
			"\{\{ for x in none \}\}x\{\{ else \}\}empty\{\{ end \}\}",
			d,
		).get(),
		"empty",
	)?

test "html escaping and raw":
	d := data("\{\"t\":\"<b>&\\\"'\"\}")
	expect_equal(render("\{\{ t \}\}", d, html: true).get(), "&lt;b&gt;&amp;&#34;&#39;")?
	expect_equal(render("\{\{ t | raw \}\}", d, html: true).get(), "<b>&\"'")?
	expect_equal(render("\{\{ t \}\}", d).get(), "<b>&\"'")?
	expect_equal(
		render("\{\{ t | escape \}\}", d, html: true).get(),
		"&lt;b&gt;&amp;&#34;&#39;",
	)?

test "trim markers and comments":
	d := data("\{\"a\":1\}")
	expect_equal(render("x  \{\{- a -\}\}  y\{\{# note \}\}", d).get(), "x1y")?

test "partials":
	page := compile("[\{\{ include \"row\" \}\}]").get()
	var partials = Map[String, Template]()
	partials.add("row", compile("\{\{ a \}\}").get())
	expect_equal(
		page.render(
			data("\{\"a\":7\}"),
			RenderOptions(partials: partials),
		).get(),
		"[7]",
	)?
	expect_true(page.render(data("\{\"a\":7\}")).is_error())?

test "strict missing values and limits":
	expect_true(render("\{\{ nope \}\}", data("\{\}")).is_error())?
	expect_equal(render("[\{\{ nope \}\}]", data("\{\}")).get(""), "")?

	page := compile("\{\{ nope \}\}").get()
	expect_equal(page.render(data("\{\}"), RenderOptions(strict: false)).get(), "")?

	big := compile("\{\{ for i in xs \}\}abcdefgh\{\{ end \}\}").get()
	expect_true(
		big.render(
			data("\{\"xs\":[1,2,3,4]\}"),
			RenderOptions(max_output: 10),
		).is_error()
	)?

test "the output limit counts UTF-8 bytes":
	accent := compile("é").get()
	expect_equal(accent.render(data("null"), RenderOptions(max_output: 2)).get(), "é")?
	expect_equal(
		accent.render(data("null"), RenderOptions(max_output: 1)).err().kind,
		"EOVERFLOW",
	)?

	emoji := compile("😀").get()
	expect_equal(
		emoji.render(data("null"), RenderOptions(max_output: 3)).err().kind,
		"EOVERFLOW",
	)?
	expect_equal(emoji.render(data("null"), RenderOptions(max_output: 4)).get(), "😀")?

	value := compile("\{\{ v \}\}\{\{ v \}\}").get()
	input := data("\{\"v\":\"é\"\}")
	expect_equal(value.render(input, RenderOptions(max_output: 4)).get(), "éé")?
	expect_equal(
		value.render(input, RenderOptions(max_output: 3)).err().kind,
		"EOVERFLOW",
	)?

test "compile errors name the line":
	for bad in [
		"\{\{ if x \}\}", "\{\{ end \}\}", "\{\{ x | nope \}\}",
		"\{\{ for x xs \}\}\{\{ end \}\}", "\{\{ x", "\{\{ a ++ \}\}",
		"\{\{ for x in xs \}\}"
	]:
		expect_true(compile(bad).is_error())?

	failed := compile("a\n\n\{\{ if \}\}")
	expect_true(failed.is_error())?

test "typed data converts":
	page := compile("\{\{ id \}\}:\{\{ tags | join(\",\") \}\}").get()
	d := to_data(Row(id: 4, tags: ["x", "y"])).get()
	expect_equal(page.render(d).get(), "4:x,y")?

type Row:
	id: Int
	tags: List[String]

test "lexing handles openers inside actions and large sources":
	d := data("\{\"x\":\"v\"\}")
	expect_equal(render("a\{\{ \"\{\{\" \}\}b", d).get(), "a\{\{b")?
	expect_equal(render("\{\{ x \}\}\{\{ x \}\}", d).get(), "vv")?
	expect_true(compile("a \{\{ x \}\} \{\{ y").is_error())?

	// A quadratic lexer would take minutes on this many actions.
	big := compile("\{\{ x \}\},".repeat(60000).get()).get()
	expect_equal(big.render(d).get().scalar_length(), 120000)?

test "equality never crosses value kinds":
	d := data("\{\"one\":1,\"text\":\"1\",\"yes\":true\}")
	expect_equal(
		render(
			"\{\{ one == text \}\}|\{\{ text == \"1\" \}\}|\{\{ one == 1 \}\}",
			d,
		).get(),
		"false|true|true",
	)?
	expect_equal(
		render("\{\{ yes == \"true\" \}\}|\{\{ one != text \}\}", d).get(),
		"false|true",
	)?

test "nested paths resolve through the loop frames and miss cleanly":
	d := data(
		"\{\"a\":\{\"b\":\{\"c\":\"deep\"\},\"l\":[\"x\",\"y\"]\},\"rows\":[\{\"a\":\{\"b\":\"row\"\}\}]\}"
	)
	expect_equal(
		render(
			"\{\{ a.b.c \}\}|\{\{ a.l.1 \}\}|\{\{ a.zz.c | default(\"none\") \}\}|\{\{ a.b.c.d | default(\"none\") \}\}",
			d,
		).get(),
		"deep|y|none|none",
	)?
	expect_equal(
		render("\{\{ for r in rows \}\}\{\{ r.a.b \}\}\{\{ end \}\}", d).get(),
		"row",
	)?
