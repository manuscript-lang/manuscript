+++
title = "Parse a media type"
+++

# Parse a media type

Review a media type and its parameters before using them. APIs may evolve during alpha.

## Read a media type parameter

<!-- manuscript-example: {"mode":"test","filename":"media-type.ms","stdout":"RUN media-type.ms::media-type\nPASS media-type.ms::media-type\n1 tests, 0 failed\n"} -->
```manuscript {filename="media-type.ms"}
import parse_media_type from "@std/net/mime.ms"
import expect_equal from "@std/test/test.ms"

test "media-type":
    let media = try parse_media_type("text/html; charset=utf-8")
    try expect_equal(media.essence, "text/html")
    try expect_equal(media.params.get("charset"), "utf-8")
```

```sh
ms test media-type.ms
```

```text
RUN media-type.ms::media-type
PASS media-type.ms::media-type
1 tests, 0 failed
```

See the [API reference](../reference/net/mime.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
