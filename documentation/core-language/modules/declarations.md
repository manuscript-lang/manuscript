+++
title = "Imports and exports"
weight = 1
+++

# Imports and exports

Named imports expose the dependencies in an agent’s change; Manuscript is in alpha, and syntax and APIs may change.

<span id="public-signature-closure"></span>

## A visible contract

Save this tested companion module as `customers.ms`.

<!-- manuscript-example: {"mode":"test","filename":"customers.ms","stdout":"RUN customers.ms::label a customer\nPASS customers.ms::label a customer\n1 tests, 0 failed\n"} -->
```manuscript {filename="customers.ms"}
import expect_equal from "@std/test/test.ms"

export type CustomerId:
    value: String

export fn customer_label(id: CustomerId) String:
    return "Customer {id.value}"

test "label a customer":
    try expect_equal(customer_label(CustomerId("C-17")), "Customer C-17")
```

```sh
ms test customers.ms
```

```text
RUN customers.ms::label a customer
PASS customers.ms::label a customer
1 tests, 0 failed
```

- Public signatures expose only public nominal types, transitively; [opaque types](../types/records.md#public-data-surfaces) hide representation.
- Each `.ms` file is one module, identified by its resolved path.

Save this caller beside it as `main.ms`.

<!-- manuscript-example: {"mode":"run","filename":"main.ms","files":{"customers.ms":"import expect_equal from \"@std/test/test.ms\"\n\nexport type CustomerId:\n    value: String\n\nexport fn customer_label(id: CustomerId) String:\n    return \"Customer {id.value}\"\n\ntest \"label a customer\":\n    try expect_equal(customer_label(CustomerId(\"C-17\")), \"Customer C-17\")\n"},"stdout":"Customer C-17\n"} -->
```manuscript {filename="main.ms"}
import CustomerId, customer_label from "./customers.ms"

export fn main() Int:
    let id = CustomerId("C-17")
    print(customer_label(id))
    return 0
```

```sh
ms run main.ms
```

```text
Customer C-17
```

- Relative imports start from the importing file’s directory and name the exact `.ms` file.
- There is no directory/extension lookup; missing files, exports and cyclic imports are errors.

## Names and declaration order

<!-- manuscript-example: {"mode":"test","filename":"names.ms","stdout":"RUN names.ms::call a later declaration\nPASS names.ms::call a later declaration\n1 tests, 0 failed\n"} -->
```manuscript {filename="names.ms"}
import (
    expect_equal,
    expect_error,
) from "@std/test/test.ms"

test "call a later declaration":
    try expect_equal(try double(3), 6)
    let cause = try expect_error(double(-1))
    try expect_equal(cause.message, "negative input")

fn double(value: Int) Int!:
    if value < 0:
        return error(Error("negative input"))
    return ok(value * 2)
```

```sh
ms test names.ms
```

```text
RUN names.ms::call a later declaration
PASS names.ms::call a later declaration
1 tests, 0 failed
```

- Parentheses wrap named imports; declarations can be used before their definition.
- One module namespace rejects duplicate names and overloads; [shadowing](../basics/bindings.md#scope-and-shadowing) has separate rules.

## Constants

Save as `constants.ms`; each use of a list constant creates an independent value.

<!-- manuscript-example: {"mode":"test","filename":"constants.ms","stdout":"RUN constants.ms::constant values are independent\nPASS constants.ms::constant values are independent\n1 tests, 0 failed\n"} -->
```manuscript {filename="constants.ms"}
import expect_equal from "@std/test/test.ms"

export let MAX_ITEMS = 100
let NAMES: List[String] = ["Ada", "Grace"]
let (
    LOW = 1
    HIGH: Int = LOW + 9
)

test "constant values are independent":
    var names = NAMES
    names.append("Sam")
    try expect_equal(names.length(), 3)
    try expect_equal(NAMES.length(), 2)
    try expect_equal(HIGH, 10)
    try expect_equal(MAX_ITEMS, 100)
```

```sh
ms test constants.ms
```

```text
RUN constants.ms::constant values are independent
PASS constants.ms::constant values are independent
1 tests, 0 failed
```

- Constant expressions use literals, operators or other constants; calls, constructors, functions and `match` are rejected.
- Each use creates a fresh value; constants cannot change or depend on themselves.

## Standard-library imports

Save as `queue_test.ms`; `@std` needs no project alias and cannot be overridden.

<!-- manuscript-example: {"mode":"test","filename":"queue_test.ms","stdout":"RUN queue_test.ms::queue preserves arrival order\nPASS queue_test.ms::queue preserves arrival order\n1 tests, 0 failed\n"} -->
```manuscript {filename="queue_test.ms"}
import Queue from "@std/collections/queue.ms"
import expect_equal from "@std/test/test.ms"

test "queue preserves arrival order":
    var queue = Queue[Int]()
    try expect_equal(queue.enqueue(7), true)
    let first = try queue.dequeue().ok_or(Error("queue is empty"))
    try expect_equal(first, 7)
```

```sh
ms test queue_test.ms
```

```text
RUN queue_test.ms::queue preserves arrival order
PASS queue_test.ms::queue preserves arrival order
1 tests, 0 failed
```

- Imports bring only named exports, not every type in their signatures.
- Prelude names need no import; [standard APIs](../../standard-library/reference/_index.md) list the other available names.

## Optional aliases

Save this project configuration as `ms.toml`, alongside `customers.ms`.

```toml
[project]
name = "customers"
source = "."
entry = "./alias.ms"

[aliases]
"@domain" = "."
"@customers" = "./customers.ms"
```

<!-- manuscript-example: {"mode":"run","filename":"alias.ms","target":"ms.toml","files":{"ms.toml":"[project]\nname = \"customers\"\nsource = \".\"\nentry = \"./alias.ms\"\n\n[aliases]\n\"@domain\" = \".\"\n\"@customers\" = \"./customers.ms\"\n","customers.ms":"import expect_equal from \"@std/test/test.ms\"\n\nexport type CustomerId:\n    value: String\n\nexport fn customer_label(id: CustomerId) String:\n    return \"Customer {id.value}\"\n\ntest \"label a customer\":\n    try expect_equal(customer_label(CustomerId(\"C-17\")), \"Customer C-17\")\n"},"stdout":"Customer C-17\n"} -->
```manuscript {filename="alias.ms"}
import CustomerId, customer_label from "@domain/customers.ms"

export fn main() Int:
    let id = CustomerId("C-17")
    print(customer_label(id))
    return 0
```

```sh
ms run ms.toml
```

```text
Customer C-17
```

- Directory alias `@domain` and file alias `@customers` select the same resolved module.
- Aliases change spelling, not identity; unknown aliases are errors.

Next: [boundaries](boundaries.md), [import resolution](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-driver/src/project/paths.rs), [impl visibility](../types/contracts.md#coherence-and-visibility).
