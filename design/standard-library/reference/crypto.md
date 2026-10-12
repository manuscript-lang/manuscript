+++
title = "crypto"
+++

# @std/crypto.ms

Import each required symbol with `import Name from "@std/crypto.ms"`.

## CryptoError

Kind: alternative.

```text
CryptoError: CryptoError
implements: Error
case InvalidInput
case Unsupported
case AuthenticationFailed
operation message: fn()->String
```

## constant_time_equal

Kind: fn.

```text
constant_time_equal: fn(left: Bytes, right: Bytes)->Bool
```

## derive_key

Kind: fn.

```text
derive_key: fn(password: Bytes, salt: Bytes, iterations: Int, length: Int)->Result[Bytes, CryptoError]
```

## hmac

Kind: fn.

```text
hmac: fn(key: Bytes, data: Bytes, algorithm: String)->Result[Bytes, CryptoError]
```

## open

Kind: fn.

```text
open: fn(key: Bytes, nonce: Bytes, ciphertext: Bytes, associated_data: Bytes)->Result[Bytes, CryptoError]
```

## public_key

Kind: fn.

```text
public_key: fn(seed: Bytes)->Result[Bytes, CryptoError]
```

## seal

Kind: fn.

```text
seal: fn(key: Bytes, nonce: Bytes, plaintext: Bytes, associated_data: Bytes)->Result[Bytes, CryptoError]
```

## sha256

Kind: fn.

```text
sha256: fn(data: Bytes)->Bytes
```

## sha384

Kind: fn.

```text
sha384: fn(data: Bytes)->Bytes
```

## sha512

Kind: fn.

```text
sha512: fn(data: Bytes)->Bytes
```

## sign

Kind: fn.

```text
sign: fn(seed: Bytes, data: Bytes)->Result[Bytes, CryptoError]
```

## verify

Kind: fn.

```text
verify: fn(key: Bytes, data: Bytes, signature: Bytes)->Bool
```

