+++
title = "Developer tools"
weight = 5
+++

# Developer tools

Review agent-written code by checking, running and inspecting the same source; save this as `review.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"Ready to review\n","filename":"review.ms"} -->
```manuscript {filename="review.ms"}
export fn main() Int:
    print("Ready to review")
    return 0
```

```sh
ms check review.ms
ms run review.ms
```

```text
Checked review.ms
Ready to review
```

- Checking does not execute the program; running builds and starts it.
- Manuscript is in alpha; syntax and APIs may change.

Next: [build and share](how-it-works.md), [commands](implementation.md), [source tools](source/_index.md) and [debugging](debugging/_index.md).
