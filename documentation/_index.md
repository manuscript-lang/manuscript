+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "Help agents build correct, fast programs you can understand. Static checks catch mistakes, compiler feedback guides repairs, and straightforward code compiles to native executables."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"run","files":{"changes.txt":"Internal cleanup\n+ Add CSV export\n+ Fix date parsing\n","template.txt":"Release notes\n$changes"},"stdout":"Release notes\n+ Add CSV export\n+ Fix date parsing\n"} -->
```manuscript {filename="release.ms"}
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
    print(page.decode_utf8().get()
        .replace("$changes", highlights))
    return ok(unit)

export fn main() Int:
    if render().is_error():
        return 1
    return 0
```
{{< /docs-home >}}
