+++
title = "Interfaces and implementations"
weight = 7
+++

# Interfaces and implementations

Interfaces let a reviewer see the operations a caller depends on, separately from stored data; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::call through a checked interface\nPASS example.ms::call through a checked interface\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

interface Increment:
    fn apply(value: Int) Int

type Offset:
    delta: Int

impl Increment for Offset:
    fn apply(value: Int) Int:
        return value + self.delta

fn adjusted(value: Int, operation: Increment) Int:
    return operation.apply(value)

test "call through a checked interface":
    let offset = Offset(2)
    try expect_equal(adjusted(10, offset), 12)
```

```sh
ms test example.ms
```

```text
RUN example.ms::call through a checked interface
PASS example.ms::call through a checked interface
1 tests, 0 failed
```

- An `impl` supplies the declared operations; assignment creates an interface view without constructor syntax.
- A view borrows its receiver; storing it in an owning value transfers an eligible receiver or needs a clone.

## Generic implementations

<!-- manuscript-example: {"mode":"test","stdout":"RUN box.ms::generic interface returns owned data\nPASS box.ms::generic interface returns owned data\n1 tests, 0 failed\n"} -->
```manuscript {filename="box.ms"}
import expect_equal from "@std/test/test.ms"

interface ReadValue[T]:
    fn read() T

type Box[T: Clonable]:
    value: T

impl ReadValue[T] for Box[T]:
    fn read() T:
        return self.value.clone()

test "generic interface returns owned data":
    let box = Box[String]("ready")
    let value = box.read()
    try expect_equal(value, "ready")
    try expect_equal(box.value, "ready")
```

```sh
ms test box.ms
```

```text
RUN box.ms::generic interface returns owned data
PASS box.ms::generic interface returns owned data
1 tests, 0 failed
```

- Receiver parameters and declared bounds scope the implementation; every application must satisfy them.
- The explicit clone gives the caller an owned result while the box keeps its value.

<span id="explicit-implementations"></span><span id="coherence-and-visibility"></span><span id="generic-operations"></span><span id="interface-conversion"></span><span id="selecting-an-operation"></span><span id="interfaces-and-services"></span>

Next: [type checking](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/src/checker.rs); [generics and bounds](generics.md).
