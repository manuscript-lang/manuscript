+++
title = "crypto"
+++

# @std/crypto.ms

Import each required symbol with `import Name from "@std/crypto.ms"`.

## constant_time_equal {data-api-kind="Function"}

```manuscript
fn constant_time_equal(left: Bytes, right: Bytes) -> Bool
```

## derive_key {data-api-kind="Function"}

```manuscript
fn derive_key(password: Bytes, salt: Bytes, iterations: Int, length: Int) -> Result[Bytes, LibraryError]
```

## hmac {data-api-kind="Function"}

```manuscript
fn hmac(key: Bytes, data: Bytes, algorithm: String) -> Result[Bytes, LibraryError]
```

## open {data-api-kind="Function"}

```manuscript
fn open(key: Bytes, nonce: Bytes, ciphertext: Bytes, associated_data: Bytes) -> Result[Bytes, LibraryError]
```

## public_key {data-api-kind="Function"}

```manuscript
fn public_key(seed: Bytes) -> Result[Bytes, LibraryError]
```

## seal {data-api-kind="Function"}

```manuscript
fn seal(key: Bytes, nonce: Bytes, plaintext: Bytes, associated_data: Bytes) -> Result[Bytes, LibraryError]
```

## sha256 {data-api-kind="Function"}

```manuscript
fn sha256(data: Bytes) -> Bytes
```

## sha384 {data-api-kind="Function"}

```manuscript
fn sha384(data: Bytes) -> Bytes
```

## sha512 {data-api-kind="Function"}

```manuscript
fn sha512(data: Bytes) -> Bytes
```

## sign {data-api-kind="Function"}

```manuscript
fn sign(seed: Bytes, data: Bytes) -> Result[Bytes, LibraryError]
```

## verify {data-api-kind="Function"}

```manuscript
fn verify(key: Bytes, data: Bytes, signature: Bytes) -> Bool
```

