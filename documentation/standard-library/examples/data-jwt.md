+++
title = "Sign and verify a token"
+++

# Sign and verify a token

Follow token signing and verification with an explicit key and claims. APIs may evolve during alpha.

## Verify a signed token

<!-- manuscript-example: {"mode":"test","filename":"signed-token.ms","stdout":"RUN signed-token.ms::signed-token\nPASS signed-token.ms::signed-token\n1 tests, 0 failed\n"} -->
```manuscript {filename="signed-token.ms"}
import sign_token, verify_token, JwtCheck from "@std/data/jwt.ms"

type Session:
    sub: String
    exp: Int
import expect_equal from "@std/test/test.ms"

test "signed-token":
    let secret = "example-only-secret-use-random-keys".to_bytes()
    let token = try sign_token(Session(sub: "42", exp: 1900000000), secret)
    let session = try verify_token[Session](token, secret, JwtCheck(at: 1800000000))
    try expect_equal(session.sub, "42")
```

```sh
ms test signed-token.ms
```

```text
RUN signed-token.ms::signed-token
PASS signed-token.ms::signed-token
1 tests, 0 failed
```

See the [API reference](../reference/data/jwt.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
