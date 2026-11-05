+++
title = "Parse a mail address"
+++

# Parse a mail address

Inspect the name and address extracted from a mailbox string. APIs may evolve during alpha.

## Parse a mailbox

<!-- manuscript-example: {"mode":"test","filename":"mail-address.ms","stdout":"RUN mail-address.ms::mail-address\nPASS mail-address.ms::mail-address\n1 tests, 0 failed\n"} -->
```manuscript {filename="mail-address.ms"}
import parse_address from "@std/net/mail.ms"
import expect_equal from "@std/test/test.ms"

test "mail-address":
    let sender = try parse_address("Ada Lovelace <ada@example.com>")
    try expect_equal(sender.name, "Ada Lovelace")
    try expect_equal(sender.address, "ada@example.com")
```

```sh
ms test mail-address.ms
```

```text
RUN mail-address.ms::mail-address
PASS mail-address.ms::mail-address
1 tests, 0 failed
```

See the [API reference](../reference/net/mail.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
