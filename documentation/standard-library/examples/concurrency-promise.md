+++
title = "Retrieve a promise result"
+++

# Retrieve a promise result

Follow a promise from its operation to explicit result handling. APIs may evolve during alpha.

## Handle a promise result

<!-- manuscript-example: {"mode":"test","filename":"promise-result.ms","stdout":"RUN promise-result.ms::promise-result\nPASS promise-result.ms::promise-result\n1 tests, 0 failed\n"} -->
```manuscript {filename="promise-result.ms"}
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import seconds from "@std/os/time.ms"
import expect_equal from "@std/test/test.ms"

test "promise-result":
    let result = promise(fn: ok(6 * 7), options: PromiseOptions(timeout: seconds(5)))
    try expect_equal(try result.wait(), 42)
```

```sh
ms test promise-result.ms
```

```text
RUN promise-result.ms::promise-result
PASS promise-result.ms::promise-result
1 tests, 0 failed
```

See the [API reference](../reference/concurrency/promise.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
