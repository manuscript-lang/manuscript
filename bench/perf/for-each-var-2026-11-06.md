# `for_each` with a `var` callback, 2026-11-06

Same machine, `ms` release builds of `main` (969c83ca) and the branch. One list of 1,000 `Int`s, `xs.for_each(fn n: total = total + n)` repeated 200,000 times (200M calls); wall time of the built executable, three runs each.

| Build | Time (s) |
| --- | --- |
| main | 0.098, 0.097, 0.098 |
| branch | 0.098, 0.107, 0.102 |
| branch with the reader adapter (rejected design) | 0.27 |

A reading callback is passed as written and receives values, so it costs what it did. A `fn var n:` callback receives the element address and measured 0.10 to 0.115 s.
