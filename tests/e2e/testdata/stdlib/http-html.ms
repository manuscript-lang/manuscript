from "@std/web_html.ms" import Html, HtmlLimits, render_html, html_response
from "@std/testing.ms" import expect_equal, expect_true

test "HTML rendering escapes text and attributes and validates executable contexts":
    var fields = Map[String, String]()
    fields.add("title", "a\"<&")

    let node = Html.Element("p", fields, [Html.Text("<script>&")])
    try expect_equal(
        try render_html(node), "<p title=\"a&#34;&lt;&amp;\">&lt;script&gt;&amp;</p>"
    )

    for name in ["onclick", "style", "srcdoc", "srcset", "ONCLICK"]:
        var attributes = Map[String, String]()
        attributes.add(name.clone(), "untrusted")
        try expect_true(render_html(Html.Element("div", attributes, [])).is_error())

    for url in [
        "javascript:alert(1)", "data:text/html,unsafe", "//untrusted.test/x",
        " javaScript:bad"
    ]:
        var attributes = Map[String, String]()
        attributes.add("href", url.clone())
        try expect_true(render_html(Html.Element("a", attributes, [])).is_error())

    try expect_true(
        render_html(
            Html.Element(
                "script", Map[String, String](), [Html.Text("unsafe")]
            )
        ).is_error()
    )
    try expect_true(
        render_html(
            Html.Element(
                "img", Map[String, String](), [Html.Text("invalid")]
            )
        ).is_error()
    )

test "HTML rendering enforces encoded expansion node and nesting limits":
    try expect_true(render_html(Html.Text("&&"), HtmlLimits(max_bytes: 9)).is_error())
    try expect_equal(
        try render_html(Html.Text("&&"), HtmlLimits(max_bytes: 10)), "&amp;&amp;"
    )

    let node = Html.Element("div", Map[String, String](), [Html.Text("ok")])
    try expect_true(render_html(node, HtmlLimits(max_nodes: 1)).is_error())
    try expect_true(render_html(node, HtmlLimits(max_depth: 0)).is_error())
    try expect_equal((try html_response(node)).status, 200)
