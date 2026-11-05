+++
title = "Records and nominal types"
weight = 1
+++

# Records and nominal types

Named fields let reviewers check a value’s shape and ownership at construction; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::independent customer update\nPASS example.ms::independent customer update\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Customer:
    name: String
    email: String?

test "independent customer update":
    let original = Customer("Ada")
    var updated = original.clone()
    updated.name = "Grace"
    try expect_equal(original.name, "Ada")
    try expect_equal(updated.name, "Grace")
    try expect_equal(updated.email.is_none(), true)
```

```sh
ms test example.ms
```

```text
RUN example.ms::independent customer update
PASS example.ms::independent customer update
1 tests, 0 failed
```

<span id="public-data-surfaces"></span><span id="opaque-types"></span>

- Export exposes record constructors/fields and enum variants. `export opaque type` or `export opaque enum` hides that representation outside its file; use exported functions instead.
- Record identity follows its declaration. `let` prevents mutation; use `var` intentionally and `.clone()` for independent data.

## Moving a field out

<!-- manuscript-example: {"mode":"test","stdout":"RUN batch.ms::move rows into a batch\nPASS batch.ms::move rows into a batch\n1 tests, 0 failed\n"} -->
```manuscript {filename="batch.ms"}
import expect_equal from "@std/test/test.ms"

type Report:
    title: String
    rows: List[Int]

test "move rows into a batch":
    let report = Report("scores", [3, 4])
    let batches = [report.rows]
    try expect_equal(report.title, "scores")
    try expect_equal(batches[0], [3, 4])
```

```sh
ms test batch.ms
```

```text
RUN batch.ms::move rows into a batch
PASS batch.ms::move rows into a batch
1 tests, 0 failed
```

- The new list owns the rows; the sibling title remains readable, but the whole report and moved rows cannot be reused.
- Reading a field or returning it from a borrow-returning getter does not move it into a new owner.

## Recursive data

<!-- manuscript-example: {"mode":"test","stdout":"RUN chain.ms::finite linked values\nPASS chain.ms::finite linked values\n1 tests, 0 failed\n"} -->
```manuscript {filename="chain.ms"}
import expect_equal from "@std/test/test.ms"

type Node:
    value: Int
    next: Node?

fn sum(node: Node) Int:
    if let next = node.next:
        return node.value + sum(next)
    return node.value

test "finite linked values":
    let chain = Node(2, Node(3))
    try expect_equal(sum(chain), 5)
```

```sh
ms test chain.ms
```

```text
RUN chain.ms::finite linked values
PASS chain.ms::finite linked values
1 tests, 0 failed
```

- End recursive data with an absent value, a base case or an empty collection.
- Recursive types do not derive hashing; generic cycles must preserve their type parameters.

<span id="construction"></span><span id="mutation-and-cloning"></span><span id="domain-identity"></span><span id="resource-fields"></span>

Next: [type and ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md); [enums](alternatives.md).
