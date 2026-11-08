import expect_equal from "@std/test/test.ms"

type Titled:
    title: String

type Holder:
    text: String

fn quoted(t: Titled) String:
    return "{t.title}"

test "a lone interpolation of a borrowed string is a new string wherever it is owned":
    let t = Titled("a")
    var xs = List[String]()
    xs.append("{t.title}")

    let h = Holder("{t.title}")
    let f = fn: "{t.title}"
    try expect_equal(quoted(t), "a")
    try expect_equal(xs, ["a"])
    try expect_equal(h.text, "a")
    try expect_equal(f(), "a")
