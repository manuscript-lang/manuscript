+++
title = "crypto"
+++

# @std/crypto.ms

Import each required symbol with `import Name from "@std/crypto.ms"`.

## CryptoError {data-api-kind="Alternative"}

```manuscript
type CryptoError:
    case InvalidInput
    case Unsupported
    case AuthenticationFailed
```

```manuscript
impl Error for CryptoError:
    fn message() -> String
```

## constant_time_equal {data-api-kind="Function"}

```manuscript
fn constant_time_equal(left: Bytes, right: Bytes) -> Bool
```

## derive_key {data-api-kind="Function"}

```manuscript
fn derive_key(password: Bytes, salt: Bytes, iterations: Int, length: Int) -> Result[Bytes, CryptoError]
```

## hmac {data-api-kind="Function"}

```manuscript
fn hmac(key: Bytes, data: Bytes, algorithm: String) -> Result[Bytes, CryptoError]
```

## open {data-api-kind="Function"}

```manuscript
fn open(key: Bytes, nonce: Bytes, ciphertext: Bytes, associated_data: Bytes) -> Result[Bytes, CryptoError]
```

## public_key {data-api-kind="Function"}

```manuscript
fn public_key(seed: Bytes) -> Result[Bytes, CryptoError]
```

## seal {data-api-kind="Function"}

```manuscript
fn seal(key: Bytes, nonce: Bytes, plaintext: Bytes, associated_data: Bytes) -> Result[Bytes, CryptoError]
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
fn sign(seed: Bytes, data: Bytes) -> Result[Bytes, CryptoError]
```

## verify {data-api-kind="Function"}

```manuscript
fn verify(key: Bytes, data: Bytes, signature: Bytes) -> Bool
```

