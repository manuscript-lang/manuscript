+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "Help agents build correct, fast programs you can understand. Static checks catch mistakes, compiler feedback guides repairs, and straightforward code compiles to native executables."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"run","stdout":"Ship\n"} -->
```manuscript {filename="next.ms"}
type Task:
    title: String
    done: Bool = false

export fn main() Int:
    let tasks = [
        Task("Write", true),
        Task("Ship"),
    ]
    let next = tasks
        | .filter(fn task: not task.done)
        | .map(fn task: task.title)
        | .join(", ")
    print(next)
    return 0
```
{{< /docs-home >}}
