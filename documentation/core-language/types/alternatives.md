+++
title = "Enums"
weight = 2
+++

# Enums

A declared set of outcomes lets reviewers check that every variant is handled; Manuscript is in alpha and syntax/APIs may change.

<span id="alternatives"></span><span id="construction-and-identity"></span><span id="handling-a-case"></span>

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::publication status\nPASS example.ms::publication status\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

enum Status:
    Draft
    Published(path: String)

fn label(status: Status) String:
    match status:
        Draft:
            return "Not published"
        Published(path):
            return "Published at {path}"

test "publication status":
    try expect_equal(label(Status.Draft), "Not published")
    try expect_equal(label(Status.Published("/help")), "Published at /help")
```

```sh
ms test example.ms
```

```text
RUN example.ms::publication status
PASS example.ms::publication status
1 tests, 0 failed
```

- An `enum` declares one or more bare variants; payloads have explicit types and no defaults.
- Matches cover every variant. This alpha syntax may change; constructors and patterns use the same declared enum.

<span id="resource-payloads"></span>

Next: [enum declarations](../basics/grammar.md#modules-declarations-and-types); [pattern matching](../control-flow/pattern-matching.md).
