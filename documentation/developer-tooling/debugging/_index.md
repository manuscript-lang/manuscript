+++
title = "Debugging"
weight = 5
+++

# Debugging

Reproduce an observed result before investigating agent-written code; save this as `review.ms`.

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

Next: [inspect checked source](metadata.md) and [profile or debug](debugger-integration.md).
