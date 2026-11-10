import parse, stringify from "@std/data/xml.ms"
import panic from "@std/core.ms"
import monotonic from "@std/time.ms"
import arguments from "@std/os/env.ms"

fn measure(
    name: String,
    source: String,
    indent: String,
    expected: String,
    count: Int
) Unit:
    let node = parse(source).get()
    if stringify(node, indent) != expected: panic("wrong untimed output: {name}")

    var checksum = 0
    let start = monotonic()

    for unused in 0..count:
        let out = stringify(node, indent)
        if out != expected: panic("wrong output: {name}")
        checksum += out.byte_length()

    let elapsed = monotonic().difference(start).to_nanoseconds()
    print("{name},{count},{elapsed},{checksum}")

export fn main() Int:
    let mode = arguments().get(0, "all")
    let count = if mode == "profile": 1 else: 500
    measure("empty", "<a/>", "", "<a/>", count * 200)
    measure("small", "<a><b/></a>", "", "<a><b/></a>", count * 100)
    measure("small-pretty", "<a><b/></a>", "  ", "<a>\n  <b/>\n</a>\n", count * 100)

    for size in [8, 128, 2048]:
        let tag = "élément_long_name_012345678901234567890123456789"
        let leaves = "<{tag} k=\"&amp;\"/>".repeat(size).get()
        let source = "<a>{leaves}</a>"
        measure("compact-{size}", source, "", source, count)

        let pretty = "<a>\n{"  <{tag} k=\"&amp;\"/>\n".repeat(size).get()}</a>\n"
        measure("pretty-{size}", source, "  ", pretty, count)

        let first = "<a>text{leaves}</a>"
        measure("first-text-{size}", first, "  ", "{first}\n", count)

        let last = "<a>{leaves}text</a>"
        measure("last-text-{size}", last, "  ", "{last}\n", count)

    let text = "é日x".repeat(16384).get()
    measure("long-text", "<a>{text}</a>", "", "<a>{text}</a>", count)
    measure("long-text-pretty", "<a>{text}</a>", "  ", "<a>{text}</a>\n", count)

    let comments = "<!--note-->".repeat(1024).get()
    measure("comments", "<a>{comments}</a>", "", "<a>{comments}</a>", count)
    measure(
        "comments-pretty", "<a>{comments}</a>", "  ",
        "<a>\n{"  <!--note-->\n".repeat(1024).get()}</a>\n", count
    )
    return 0
