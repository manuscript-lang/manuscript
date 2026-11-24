+++
title = "Hashes, IDs and random values"
weight = 9
+++

# Hashes, IDs and random values

Fingerprint data, make identifiers, and draw random numbers you can repeat in a test.

## Hash text and make identifiers

Save as `ids.ms`. `sha256` takes `Bytes`, so convert text with `to_bytes()`; `hex_encode` makes the digest printable. `uuid_v4` and `token` draw from the operating system's secure random source, so they return a `Result`.

<!-- manuscript-example: {"mode":"run","stdout":"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824\n36\n22\n"} -->
```manuscript
import (
    sha256 from "@std/crypto/crypto.ms",
    hex_encode from "@std/data/encoding.ms",
    uuid_v4 from "@std/data/uuid.ms",
    token from "@std/random.ms",
)

fn main() Void! {
    digest := sha256("hello".to_bytes())
    print(hex_encode(digest))

    id := uuid_v4()?
    print(id.length())

    secret := token(16)?
    print(secret.length())
}
```

- `token(16)` is 16 random bytes as unpadded URL-safe Base64, 22 characters; the default 32 bytes is 43. Use it for session ids and API keys.
- `uuid_v7` sorts by creation time, even for ids made in the same millisecond, which keeps database index writes together; `uuid_v5` gives the same id for the same name.
- A plain hash is not a password hash. For passwords use `derive_key` from `@std/crypto/crypto.ms` with a random salt.

## Random numbers you can repeat

`seeded(n)` returns a generator that gives the same sequence for the same seed, so a test that uses randomness stays reproducible. It is not secure: use `secure_int`, `token` and `random_bytes` for secrets. Draws change the generator, so it is a `var`.

<!-- manuscript-example: {"mode":"run","stdout":"true\n"} -->
```manuscript
import seeded from "@std/random.ms"

fn main() Void {
    var first = seeded(42)
    var second = seeded(42)
    print(first.int(1, 7) == second.int(1, 7))
}
```

`shuffle`, `choice` and `sample` exist on the generator as well as at module level.
