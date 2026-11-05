+++
title = "Source tools"
weight = 4
+++

# Source tools

Check a proposed change before executing it; save this as `review.ms`.

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

Next: [formatting](formatting.md), [diagnostics](diagnostics.md) and [effects](effects.md).
