+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "Write, understand, test, and ship native programs with a small typed language, a bundled standard library, and one development toolchain. Built for agents and people working together."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"run","files":{"changes.txt":"Internal cleanup\n+ Add CSV export\n+ Fix date parsing\n","template.txt":"Release notes\n$changes"},"stdout":"Release notes\n+ Add CSV export\n+ Fix date parsing\n"} -->
```manuscript {filename="generate_release_notes.ms"}
import open, read_file from "@std/os/fs.ms"
import lines, collect from "@std/io/streams.ms"

fn render() Unit!:
    let template = read_file("template.txt")
    let file = try open("changes.txt", "r", 0)
    let source = try file.reader() | lines
    let highlights = try collect(source)
        | .filter(fn line: line.starts_with("+ "))
        | .join("\n")
    let page = try template.wait()
    let text = try page.decode_utf8().ok_or()
    print(text.replace("$changes", highlights))
    return ok(unit)

export fn main() Int:
    return if render().is_ok(): 0 else: 1
```
{{< /docs-home >}}
