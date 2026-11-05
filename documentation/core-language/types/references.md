+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

Ownership makes copies, mutation and scope-end drop visible during review; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::borrow a customer name\nPASS example.ms::borrow a customer name\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Customer:
    name: String

fn name_of(customer: Customer) String:
    return customer.name

test "borrow a customer name":
    let customer = Customer("Ada")
    let name = name_of(customer)
    try expect_equal(name, "Ada")
    try expect_equal(customer.name, "Ada")
```

```sh
ms test example.ms
```

```text
RUN example.ms::borrow a customer name
PASS example.ms::borrow a customer name
1 tests, 0 failed
```

- A getter can lend a parameter field; the owner must stay available until the borrow’s last use.
- `Map.get` lends its entry: use `if let` to read or `if var` to mutate; the borrow prevents conflicting access until its last use.

## Reassignment

<!-- manuscript-example: {"mode":"test","stdout":"RUN scores.ms::copy before independent mutation\nPASS scores.ms::copy before independent mutation\n1 tests, 0 failed\n"} -->
```manuscript {filename="scores.ms"}
import expect_equal from "@std/test/test.ms"

fn append_score(var scores: List[Int]) Unit:
    scores.append(3)

test "copy before independent mutation":
    var scores = [1, 2]
    let original = scores.clone()
    append_score(var scores)
    try expect_equal(original, [1, 2])
    try expect_equal(scores, [1, 2, 3])
```

```sh
ms test scores.ms
```

```text
RUN scores.ms::copy before independent mutation
PASS scores.ms::copy before independent mutation
1 tests, 0 failed
```

- The `var` parameter changes caller-owned storage; the clone has independent contents.
- Replacing an owning variable drops its old value and closes resource parts.

<span id="how-memory-works"></span><span id="borrowing"></span><span id="data-copies"></span><span id="sharing-a-value"></span><span id="references-inside-other-values"></span><span id="memory-and-open-resources"></span><span id="returning-a-resource"></span>

Next: [type and ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md); [scope-end cleanup](../cleanup/scopes.md).
