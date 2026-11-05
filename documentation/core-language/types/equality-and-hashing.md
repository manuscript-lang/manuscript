+++
title = "Equality and hashing"
weight = 8
+++

# Equality and hashing

Explicit key identity makes deduplication and lookup decisions reviewable; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::deduplicate by identifier\nPASS example.ms::deduplicate by identifier\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type CustomerKey:
    id: Int
    label: String

impl Equal for CustomerKey:
    fn equals(other: CustomerKey) Bool:
        return self.id == other.id

impl Hashable for CustomerKey:
    fn hash() Int:
        return self.id

test "deduplicate by identifier":
    var keys = Set[CustomerKey]()
    keys.add(CustomerKey(7, "Ada"))
    keys.add(CustomerKey(7, "Ada Lovelace"))
    try expect_equal(keys.length(), 1)
```

```sh
ms test example.ms
```

```text
RUN example.ms::deduplicate by identifier
PASS example.ms::deduplicate by identifier
1 tests, 0 failed
```

- An explicit Equal implementation defines identity; Hashable must give equal values equal hashes.
- Records and enums otherwise compare their components when those components support equality.

<span id="built-in-value-semantics"></span><span id="domain-identity"></span><span id="key-consistency"></span>

Next: [type checking](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/src/checker.rs); [interfaces and implementations](contracts.md).
