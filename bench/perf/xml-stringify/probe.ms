import (
    parse, stringify from "@std/data/xml.ms",
    panic from "@std/core.ms",
    monotonic from "@std/time.ms",
    arguments from "@std/os/env.ms",
)

fn measure(
    name: String,
    source: String,
    indent: String,
    expected: String,
    count: Int
) Unit:
    node := parse(source).get()
    if stringify(node, indent) != expected: panic("wrong untimed output: {name}")

    var checksum = 0
    start := monotonic()

    for unused in 0..count:
        out := stringify(node, indent)
        if out != expected: panic("wrong output: {name}")
        checksum += out.byte_length()

    elapsed := monotonic().difference(start).to_nanoseconds()
    print("{name},{count},{elapsed},{checksum}")

export fn main() Int:
    mode := arguments().get(0, "all")
    count := if mode == "profile": 1 else: 500
    measure("empty", "<a/>", "", "<a/>", count * 200)
    measure("small", "<a><b/></a>", "", "<a><b/></a>", count * 100)
    measure("small-pretty", "<a><b/></a>", "  ", "<a>\n  <b/>\n</a>\n", count * 100)

    for size in [8, 128, 2048]:
        tag := "élément_long_name_012345678901234567890123456789"
        leaves := "<{tag} k=\"&amp;\"/>".repeat(size).get()
        source := "<a>{leaves}</a>"
        measure("compact-{size}", source, "", source, count)

        pretty := "<a>\n{"  <{tag} k=\"&amp;\"/>\n".repeat(size).get()}</a>\n"
        measure("pretty-{size}", source, "  ", pretty, count)

        first := "<a>text{leaves}</a>"
        measure("first-text-{size}", first, "  ", "{first}\n", count)

        last := "<a>{leaves}text</a>"
        measure("last-text-{size}", last, "  ", "{last}\n", count)

    text := "é日x".repeat(16384).get()
    measure("long-text", "<a>{text}</a>", "", "<a>{text}</a>", count)
    measure("long-text-pretty", "<a>{text}</a>", "  ", "<a>{text}</a>\n", count)

    comments := "<!--note-->".repeat(1024).get()
    measure("comments", "<a>{comments}</a>", "", "<a>{comments}</a>", count)
    measure(
        "comments-pretty", "<a>{comments}</a>", "  ",
        "<a>\n{"  <!--note-->\n".repeat(1024).get()}</a>\n", count
    )
    return 0
