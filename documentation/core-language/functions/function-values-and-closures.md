+++
title = "Function values and closures"
weight = 2
+++

# Function values and closures

A callback makes the varying operation visible without duplicating its caller; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::borrow a prepared offset\nPASS example.ms::borrow a prepared offset\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

fn apply(value: Int, transform: fn(Int) Int) Int:
    return transform(value)

test "borrow a prepared offset":
    let offset = 2
    let adjust = fn(value: Int) Int:
        return value + offset
    try expect_equal(apply(10, adjust), 12)
```

```sh
ms test example.ms
```

```text
RUN example.ms::borrow a prepared offset
PASS example.ms::borrow a prepared offset
1 tests, 0 failed
```

- Local closures borrow captures; an escaping closure takes ownership and its cleanup duties.
- Function-value calls and interface methods return owned values; clone captured data when an independent owner is needed.

## Mutable parameters

<!-- manuscript-example: {"mode":"test","stdout":"RUN mutation.ms::explicit mutation through a callback\nPASS mutation.ms::explicit mutation through a callback\n1 tests, 0 failed\n"} -->
```manuscript {filename="mutation.ms"}
import expect_equal from "@std/test/test.ms"

fn append_one(var values: List[Int]) Unit:
    values.append(1)

fn change(operation: fn(var List[Int]) Unit, var values: List[Int]) Unit:
    operation(var values)

test "explicit mutation through a callback":
    var values: List[Int] = []
    change(append_one, var values)
    try expect_equal(values, [1])
```

```sh
ms test mutation.ms
```

```text
RUN mutation.ms::explicit mutation through a callback
PASS mutation.ms::explicit mutation through a callback
1 tests, 0 failed
```

- Both the function type and call mark the mutable argument with `var`.
- A mutable parameter remains owned by the caller; it cannot be moved out without replacement.

<span id="function-type-compatibility"></span><span id="changing-parameters"></span><span id="closure-captures"></span><span id="resource-captures"></span><span id="contextual-callback-inference"></span>

Next: [capture and ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md); [mutation and references](../types/references.md).
