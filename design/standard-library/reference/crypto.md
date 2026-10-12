+++
title = "crypto"
+++

# @std/crypto.ms

Import each required symbol with `import Name from "@std/crypto.ms"`.

## constant_time_equal {data-api-kind="Function"}

```manuscript
constant_time_equal: fn(left: Bytes, right: Bytes)->Bool
```

## derive_key {data-api-kind="Function"}

```manuscript
derive_key: fn(password: Bytes, salt: Bytes, iterations: Int, length: Int)->Result[Bytes, LibraryError]
```

## hmac {data-api-kind="Function"}

```manuscript
hmac: fn(key: Bytes, data: Bytes, algorithm: String)->Result[Bytes, LibraryError]
```

## open {data-api-kind="Function"}

```manuscript
open: fn(key: Bytes, nonce: Bytes, ciphertext: Bytes, associated_data: Bytes)->Result[Bytes, LibraryError]
```

## public_key {data-api-kind="Function"}

```manuscript
public_key: fn(seed: Bytes)->Result[Bytes, LibraryError]
```

## seal {data-api-kind="Function"}

```manuscript
seal: fn(key: Bytes, nonce: Bytes, plaintext: Bytes, associated_data: Bytes)->Result[Bytes, LibraryError]
```

## sha256 {data-api-kind="Function"}

```manuscript
sha256: fn(data: Bytes)->Bytes
```

## sha384 {data-api-kind="Function"}

```manuscript
sha384: fn(data: Bytes)->Bytes
```

## sha512 {data-api-kind="Function"}

```manuscript
sha512: fn(data: Bytes)->Bytes
```

## sign {data-api-kind="Function"}

```manuscript
sign: fn(seed: Bytes, data: Bytes)->Result[Bytes, LibraryError]
```

## verify {data-api-kind="Function"}

```manuscript
verify: fn(key: Bytes, data: Bytes, signature: Bytes)->Bool
```

