+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "Help agents build correct, fast programs you can understand. Static checks catch mistakes, compiler feedback guides repairs, and straightforward code compiles to native executables."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"run","files":{"changes.txt":"Internal cleanup\n+ Add CSV export\n+ Fix date parsing\n","template.txt":"Release notes\n$changes"},"stdout":"Release notes\n+ Add CSV export\n+ Fix date parsing\n"} -->
```manuscript {filename="release.ms"}
import read_file from "@std/os/fs.ms"
import wait_all from "@std/concurrency/promise.ms"

export fn main() Int:
    let changes = read_file("changes.txt")
    let template = read_file("template.txt")
    if let files = wait_all([changes, template]):
        let highlights = files[0].decode_utf8().get()
            | .lines()
            | .filter(fn line: line.starts_with("+ "))
            | .join("\n")
        let page = files[1].decode_utf8().get()
        print(page.replace("$changes", highlights))
        return 0
    return 1
```
{{< /docs-home >}}
