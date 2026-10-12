+++
title = "crypto"
+++

# @std/crypto.ms

Import each required symbol with `import Name from "@std/crypto.ms"`.

## constant_time_equal

Kind: fn.

```manuscript
constant_time_equal: fn(left: Bytes, right: Bytes)->Bool
```

## derive_key

Kind: fn.

```manuscript
derive_key: fn(password: Bytes, salt: Bytes, iterations: Int, length: Int)->Result[Bytes, LibraryError]
```

## hmac

Kind: fn.

```manuscript
hmac: fn(key: Bytes, data: Bytes, algorithm: String)->Result[Bytes, LibraryError]
```

## open

Kind: fn.

```manuscript
open: fn(key: Bytes, nonce: Bytes, ciphertext: Bytes, associated_data: Bytes)->Result[Bytes, LibraryError]
```

## public_key

Kind: fn.

```manuscript
public_key: fn(seed: Bytes)->Result[Bytes, LibraryError]
```

## seal

Kind: fn.

```manuscript
seal: fn(key: Bytes, nonce: Bytes, plaintext: Bytes, associated_data: Bytes)->Result[Bytes, LibraryError]
```

## sha256

Kind: fn.

```manuscript
sha256: fn(data: Bytes)->Bytes
```

## sha384

Kind: fn.

```manuscript
sha384: fn(data: Bytes)->Bytes
```

## sha512

Kind: fn.

```manuscript
sha512: fn(data: Bytes)->Bytes
```

## sign

Kind: fn.

```manuscript
sign: fn(seed: Bytes, data: Bytes)->Result[Bytes, LibraryError]
```

## verify

Kind: fn.

```manuscript
verify: fn(key: Bytes, data: Bytes, signature: Bytes)->Bool
```

