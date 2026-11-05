+++
title = "Collections"
weight = 3
+++

# Collections

Choose a collection whose ordering and update behavior a reviewer can recognize; Manuscript is in alpha and syntax/APIs may change.

<span id="list-literals"></span><span id="mutation-and-copies"></span><span id="naming-and-migration"></span>

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::update one independent list\nPASS example.ms::update one independent list\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "update one independent list":
    let original = [3, 1, 2]
    var scores = original.clone()
    scores.sort()
    scores.append(4)
    try expect_equal(original, [3, 1, 2])
    try expect_equal(scores, [1, 2, 3, 4])
```

```sh
ms test example.ms
```

```text
RUN example.ms::update one independent list
PASS example.ms::update one independent list
1 tests, 0 failed
```

- A clone has independent storage; an ordinary binding of a place can borrow instead.
- Use `var` only for mutations; collection cleanup follows ownership of the stored values.

<span id="map-literals"></span><span id="lookup-and-updates"></span>

## Maps

<!-- manuscript-example: {"mode":"test","stdout":"RUN visits.ms::count visits by path\nPASS visits.ms::count visits by path\n1 tests, 0 failed\n"} -->
```manuscript {filename="visits.ms"}
import expect_equal from "@std/test/test.ms"

test "count visits by path":
    var visits = {"/help": 1}
    visits.update("/help", 0, fn count: count + 1)
    visits.add("/tour", 1)
    if let count = visits.get("/help"):
        try expect_equal(count, 2)
    else:
        return error(Error("missing path"))
    try expect_equal(visits.keys(), ["/help", "/tour"])
```

```sh
ms test visits.ms
```

```text
RUN visits.ms::count visits by path
PASS visits.ms::count visits by path
1 tests, 0 failed
```

- Map and set traversal keeps insertion order; replacing an existing entry keeps its position.
- Keys and set elements require `Hashable`; ordinary lookup returns `T?` when absence is expected.

<span id="element-requirements"></span><span id="iteration"></span><span id="walking-two-lists-or-a-list-with-its-index"></span><span id="other-collections"></span><span id="primitive-storage-and-memory"></span><span id="search-and-enumeration"></span><span id="transforming-map-keys-and-values"></span><span id="reducing-and-querying"></span><span id="building-data"></span>

Next: [type and ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md); [equality and hashing](equality-and-hashing.md).
