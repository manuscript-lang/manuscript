+++
title = "Diagnostics"
weight = 2
+++

# Diagnostics

Review the compiler's proposed repair before accepting it; save this as `count.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"3\n","filename":"count.ms"} -->
```manuscript {filename="count.ms"}
export fn main() Int:
    var count = 2
    count += 1
    print(count)
    return 0
```

```sh
ms run count.ms
```

```text
3
```

- Change `var count` to `let count` to make the assignment invalid.
- Manuscript is in alpha; syntax, APIs and diagnostics may change.

## Follow a repair

```sh
ms check count.ms --fix
ms run count.ms
```

```text
ms: applied 1 fix in 1 file
Checked count.ms
3
```

- After the intentional edit above, `--fix` restores `var`; the first line is written to stderr.
- Without `--fix`, checking exits 1 and points to line 3: `cannot assign immutable binding count; declare it with 'var count = ...' instead of 'let'`.

<span id="message-shape"></span>
<span id="explaining-a-violated-rule"></span>
<span id="json-diagnostics"></span>

Next: [bindings](../../core-language/basics/bindings.md), [diagnostic fields and positions](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-cli/src/diagnostic.rs).
