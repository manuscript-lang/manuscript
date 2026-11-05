+++
title = "Formatting"
weight = 1
+++

# Formatting

Keep formatting changes separate from logic during review; save this as `format.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"5\n","filename":"format.ms"} -->
```manuscript {filename="format.ms"}
export fn main() Int:
    let total=2+3
    print(total)
    return 0
```

```sh
ms fmt format.ms --check
```

```text
Formatting needed: format.ms; run ms fmt format.ms to rewrite it
```

- Check mode writes the message to stderr, exits 1 and leaves source unchanged.
- Manuscript is in alpha; syntax and formatting rules may change.

## Format one file

```sh
ms fmt format.ms
ms fmt format.ms --check
ms run format.ms
```

```text
5
```

- Both formatting commands succeed silently; the assignment becomes `let total = 2 + 3`.

<span id="format-files-or-a-project"></span>
<span id="formatter-contract"></span>

Next: [project inputs](../builds/project-configuration.md#commands-and-module-discovery), [selection and write guarantees](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-cli/src/fmt.rs) and [formatter rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-syntax/src/format.rs).
