+++
title = "Build levels"
weight = 2
+++

# Build levels

Review source behavior without optimization or build optimized deployment code; save this as `main.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"Ready to review\n","filename":"main.ms"} -->
```manuscript {filename="main.ms"}
export fn main() Int:
    print("Ready to review")
    return 0
```

```sh
ms run main.ms --build-type Debug
ms build main.ms --build-type Release -o program
ms build main.ms --build-type MinSizeRel -o small-program
```

```text
Ready to review
Built program
Built small-program
```

- `Debug` disables optimization; default `Release` favors speed; `MinSizeRel` favors size and strips symbols.
- Manuscript is in alpha; syntax, APIs and build behavior may change.

<span id="levels"></span>
<span id="defaults-and-command-behavior"></span>

Next: [build options](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-cli/src/help_text.rs), [native debugging](../debugging/debugger-integration.md) and [deployment targets](../how-it-works.md#build-the-executable).
