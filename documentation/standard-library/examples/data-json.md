+++
title = "Read and encode JSON"
+++

# Read and encode JSON

Review JSON member access, typed decoding, and a custom encoding contract. APIs may evolve during alpha.

## Read object members

<!-- manuscript-example: {"mode":"test","filename":"json-members.ms","stdout":"RUN json-members.ms::json-members\nPASS json-members.ms::json-members\n1 tests, 0 failed\n"} -->
```manuscript {filename="json-members.ms"}
import JsonValue, parse from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

test "json-members":
    let doc = try parse[JsonValue]("\{\"user\":\{\"name\":\"Ada\"\}\}")
    let name = try doc.get_in(["user", "name"]).ok_or(Error("missing name"))
    try expect_equal(name.as_string(), "Ada")
```

```sh
ms test json-members.ms
```

```text
RUN json-members.ms::json-members
PASS json-members.ms::json-members
1 tests, 0 failed
```

## Customize JSON encoding

<!-- manuscript-example: {"mode":"test","filename":"custom-json.ms","stdout":"RUN custom-json.ms::custom-json\nPASS custom-json.ms::custom-json\n1 tests, 0 failed\n"} -->
```manuscript {filename="custom-json.ms"}
import JsonEncode, JsonValue, stringify from "@std/data/json.ms"

type Status:
    ready: Bool

impl JsonEncode for Status:
    fn to_json() JsonValue:
        return JsonValue.StringValue(if self.ready: "ready" else: "waiting")
import expect_equal from "@std/test/test.ms"

test "custom-json":
    let text = try stringify(Status(ready: true))
    try expect_equal(text, "\"ready\"")
```

```sh
ms test custom-json.ms
```

```text
RUN custom-json.ms::custom-json
PASS custom-json.ms::custom-json
1 tests, 0 failed
```

## Decode a typed record

<!-- manuscript-example: {"mode":"test","filename":"json-record.ms","stdout":"RUN json-record.ms::json-record\nPASS json-record.ms::json-record\n1 tests, 0 failed\n"} -->
```manuscript {filename="json-record.ms"}
import stringify from "@std/data/json.ms"

type Request:
    model: String
    stream: Bool
    user: String?
import expect_equal from "@std/test/test.ms"

test "json-record":
    let text = try stringify(Request(model: "example", stream: true, user: none))
    try expect_equal(text, "\{\"model\":\"example\",\"stream\":true\}")
```

```sh
ms test json-record.ms
```

```text
RUN json-record.ms::json-record
PASS json-record.ms::json-record
1 tests, 0 failed
```

See the [API reference](../reference/data/json.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
