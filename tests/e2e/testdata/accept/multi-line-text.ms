import expect_equal from "@std/test/test.ms"
import parse from "@std/data/json.ms"

fn banner(name: String, count: Int) String:
    return """
        Hello, {name}!
          {count} items, "quoted"\t\{literal\}
        """

fn payload() String:
    return r"""
        {"name": "ada", "tags": ["a", "b"], "path": "C:\dir", "n": 1}
        """

test "indentation of the closing line is removed":
    try expect_equal(
        banner("Ada", 3), "Hello, Ada!\n  3 items, \"quoted\"\t\{literal\}"
    )

test "blank lines and a trailing newline survive":
    let text = """
        first

        last

        """
    try expect_equal(text, "first\n\nlast\n")

test "raw text keeps braces quotes and backslashes":
    try expect_equal(
        payload(),
        "\{\"name\": \"ada\", \"tags\": [\"a\", \"b\"], \"path\": \"C:\\dir\", \"n\": 1\}"
    )

type Person:
    name: String
    n: Int

test "raw text needs no escapes for JSON":
    let person = try parse[Person](text: r"""
    {"name": "ada", "n": 1}
    """, limits: none)
    try expect_equal(person.name, "ada")
    try expect_equal(person.n, 1)
