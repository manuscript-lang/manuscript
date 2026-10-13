+++
title = "crypto"
+++

# @std/crypto.ms

Import each required symbol with `import Name from "@std/crypto.ms"`.

## CryptoError {data-api-kind="Alternative"}

Errors returned when cryptographic input is invalid or an algorithm is unavailable.

```manuscript
type CryptoError:
    case InvalidInput
    case Unsupported
    case AuthenticationFailed
```

```manuscript
impl Error for CryptoError:
    fn message() -> String:
```

## constant_time_equal {data-api-kind="Function"}

Compares byte strings without making the comparison time depend on their contents.

```manuscript
fn constant_time_equal(left: Bytes, right: Bytes) -> Bool:
```

## derive_key {data-api-kind="Function"}

Derives a key with PBKDF2-HMAC-SHA-256 using the supplied iteration count and length.

```manuscript
fn derive_key(password: Bytes, salt: Bytes, iterations: Int, length: Int) -> Result[Bytes, CryptoError]:
```

## hmac {data-api-kind="Function"}

Computes an HMAC using exactly `sha256`, `sha384`, or `sha512` (case-sensitive).
Other algorithms return CryptoError.Unsupported.

```manuscript
fn hmac(key: Bytes, data: Bytes, algorithm: String) -> Result[Bytes, CryptoError]:
```

## open {data-api-kind="Function"}

Authenticates and decrypts a value produced by `seal` using AES-GCM.

```manuscript
fn open(key: Bytes, nonce: Bytes, ciphertext: Bytes, associated_data: Bytes) -> Result[Bytes, CryptoError]:
```

## public_key {data-api-kind="Function"}

Derives the Ed25519 public key corresponding to a 32-byte private seed.

```manuscript
fn public_key(seed: Bytes) -> Result[Bytes, CryptoError]:
```

## seal {data-api-kind="Function"}

Encrypts and authenticates plaintext with AES-GCM. The caller supplies a unique nonce.

```manuscript
fn seal(key: Bytes, nonce: Bytes, plaintext: Bytes, associated_data: Bytes) -> Result[Bytes, CryptoError]:
```

## sha256 {data-api-kind="Function"}

Returns the SHA-256 digest of the input.

```manuscript
fn sha256(data: Bytes) -> Bytes:
```

## sha384 {data-api-kind="Function"}

Returns the SHA-384 digest of the input.

```manuscript
fn sha384(data: Bytes) -> Bytes:
```

## sha512 {data-api-kind="Function"}

Returns the SHA-512 digest of the input.

```manuscript
fn sha512(data: Bytes) -> Bytes:
```

## sign {data-api-kind="Function"}

Signs data with an Ed25519 private seed.

```manuscript
fn sign(seed: Bytes, data: Bytes) -> Result[Bytes, CryptoError]:
```

## verify {data-api-kind="Function"}

Verifies an Ed25519 signature with a public key.

```manuscript
fn verify(key: Bytes, data: Bytes, signature: Bytes) -> Bool:
```

