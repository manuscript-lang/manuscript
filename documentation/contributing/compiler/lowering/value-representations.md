+++
title = "Source guarantees and representations"
weight = 94
+++

# Source guarantees and representations

Observe clone independence to review an agent’s ownership-lowering change; save as `copies.ms`.

<!-- manuscript-example: {"mode":"run","filename":"copies.ms","stdout":"2 / 3\n"} -->
```manuscript
export fn main() Int:
    let original = [1, 2]
    var changed = original.clone()
    changed.append(3)
    print("{original.length()} / {changed.length()}")
    return 0
```

```sh
ms run copies.ms
```

```text
2 / 3
```

- Cloning preserves the original list when the clone changes.
- Alpha: internal layouts may change.

<span id="representation-boundaries"></span>

Next: [shared ABI layouts](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-rt-abi/src/lib.rs) and [numeric outcomes](../../../core-language/basics/numbers-and-booleans.md#runtime-numeric-outcomes).
