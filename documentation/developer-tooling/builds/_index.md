+++
title = "Builds and projects"
weight = 3
+++

# Builds and projects

Keep build inputs and deployment choices visible during review; save this as `review.ms`.

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

Next: [project configuration](project-configuration.md), [build levels](build-levels.md) and [build caches](incremental-compilation.md).
