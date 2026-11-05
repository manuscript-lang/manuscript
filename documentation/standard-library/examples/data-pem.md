+++
title = "Decode PEM blocks"
+++

# Decode PEM blocks

Check that encoded PEM blocks preserve their label and bytes when decoded. APIs may evolve during alpha.

## Decode a PEM block

<!-- manuscript-example: {"mode":"test","filename":"pem-blocks.ms","stdout":"RUN pem-blocks.ms::pem-blocks\nPASS pem-blocks.ms::pem-blocks\n1 tests, 0 failed\n"} -->
```manuscript {filename="pem-blocks.ms"}
import PemBlock, parse, encode_all from "@std/data/pem.ms"
import expect_equal from "@std/test/test.ms"

test "pem-blocks":
    let text = encode_all([PemBlock(label: "NOTE", data: "hi".to_bytes())])
    let blocks = try parse(text)
    try expect_equal(blocks.length(), 1)
    try expect_equal(blocks[0].label, "NOTE")
    try expect_equal(blocks[0].data.decode_utf8(), "hi")
```

```sh
ms test pem-blocks.ms
```

```text
RUN pem-blocks.ms::pem-blocks
PASS pem-blocks.ms::pem-blocks
1 tests, 0 failed
```

See the [API reference](../reference/data/pem.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
