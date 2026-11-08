import expect_equal from "@std/test/test.ms"

type Label:
    text: String
    parts: List[String]

impl Label:
    fn name() String:
        return self.text

    fn first() String:
        return self.parts[0]

    fn greeting(prefix: String = "hi") String:
        return self.text

test "a temporary receiver returns its borrowed string":
    let name = Label("example", ["a"]).name
    try expect_equal(name(), "example")

test "a named receiver returns its borrowed string":
    let label = Label("named", ["b"])
    let name = label.name
    try expect_equal(name(), "named")
    try expect_equal(label.text, "named")

test "a borrowed list element is copied for each call":
    let label = Label("x", ["elem"])
    let first = label.first
    try expect_equal(first(), "elem")
    try expect_equal(first(), "elem")

test "a method with a default keeps its borrowed result":
    let label = Label("dflt", ["c"])
    let greeting = label.greeting
    try expect_equal(greeting(), "dflt")
    try expect_equal(greeting("yo"), "dflt")
