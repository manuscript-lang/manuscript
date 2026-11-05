+++
title = "Generics and bounds"
weight = 9
+++

# Generics and bounds

Generics keep one implementation reusable while each call still has known types; Manuscript is in alpha and syntax/APIs may change.

<span id="bounds"></span><span id="declarations-and-applications"></span><span id="body-checking-and-well-formedness"></span>

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::typed reusable values\nPASS example.ms::typed reusable values\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Box[T]:
    value: T

fn same[T: Equal](left: T, right: T) Bool:
    return left == right

test "typed reusable values":
    let count = Box[Int](3)
    let name = Box[String]("Ada")
    try expect_equal(same(count.value, 3), true)
    try expect_equal(same(name.value, "Ada"), true)
```

```sh
ms test example.ms
```

```text
RUN example.ms::typed reusable values
PASS example.ms::typed reusable values
1 tests, 0 failed
```

- Generic bounds expose the operations a function can use; callers supply one concrete type for each parameter.
- Data permits typed JSON: resource, function and interface values do not satisfy that bound.

<span id="default-type-arguments"></span>

## Defaults

<!-- manuscript-example: {"mode":"test","stdout":"RUN pair.ms::default second type\nPASS pair.ms::default second type\n1 tests, 0 failed\n"} -->
```manuscript {filename="pair.ms"}
import expect_equal from "@std/test/test.ms"

type Pair[A, B = A]:
    first: A
    second: B

test "default second type":
    let values = Pair[Int](2, 3)
    let labeled = Pair[Int, String](2, "two")
    try expect_equal(values.second, 3)
    try expect_equal(labeled.second, "two")
```

```sh
ms test pair.ms
```

```text
RUN pair.ms::default second type
PASS pair.ms::default second type
1 tests, 0 failed
```

- Inference runs before defaults; later type parameters need defaults once an earlier one has one.
- A default can name earlier type parameters and must satisfy its bounds.

<span id="inference-from-arguments"></span><span id="finite-recursive-applications"></span><span id="built-in-requirements"></span>

Next: [generic bound checking](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/src/contracts.rs#L1356-L1470); [type compatibility](compatibility.md).
