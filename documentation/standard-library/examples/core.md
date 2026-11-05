+++
title = "Print a result"
+++

# Print a result

Follow a computed value into a readable line of output. APIs may evolve during alpha.

## Print a calculated total

<!-- manuscript-example: {"mode":"run","filename":"print-line.ms","stdout":"total: 3\n"} -->
```manuscript {filename="print-line.ms"}
export fn main() Int:
    let total = 3
    print("total: {total}")
    return 0
```

```sh
ms run print-line.ms
```

```text
total: 3
```

See the [API reference](../reference/core.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
