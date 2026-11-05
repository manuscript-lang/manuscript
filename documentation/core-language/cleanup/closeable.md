+++
title = "Implementing Closeable"
weight = 3
+++

# Implementing Closeable

Implement fallible cleanup to review how release failures reach callers; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::return a scope-end close error\nPASS example.ms::return a scope-end close error\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import Closeable from "@std/core.ms"
import expect_equal, expect_error from "@std/test/test.ms"

type Gate:
    failed: Bool = false

impl Closeable for Gate:
    var fn close() Unit!:
        if not self.failed:
            self.failed = true
            return error(Error("Release failed", kind: "EIO"))
        return ok(unit)

fn release_gate() Unit!:
    let _gate = Gate()
    return ok(unit)

test "return a scope-end close error":
    let cause = try expect_error(release_gate())
    try expect_equal(cause.kind, "EIO")
```

```sh
ms test example.ms
```

```text
RUN example.ms::return a scope-end close error
PASS example.ms::return a scope-end close error
1 tests, 0 failed
```

<a id="cloning-a-resource"></a>
<a id="records-and-collections-close-what-they-hold"></a>
<a id="a-close-returns-a-result"></a>

- Implement standard `Closeable`; a same-named method alone does not opt in. Close may wait and must tolerate repeated calls.
- Implicit close errors propagate through `T!` when possible; otherwise they fault. An existing error wins after remaining cleanup runs.

Next: [the Closeable contract](../../standard-library/reference/core.ms.md#closeable), [owned-part order](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-lower/src/close.rs#L40-L53) and [fault selection](cleanup-faults.md).
