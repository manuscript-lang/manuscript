+++
title = "random"
+++

# @std/random.ms

Import each required symbol with `import Name from "@std/random.ms"`.

## Entropy

Kind: interface.

```manuscript
Entropy: Entropy
operation bytes: fn(count: Int)->Result[Bytes, LibraryError]
```

## secure_int

Kind: fn.

```manuscript
secure_int: fn(entropy: Entropy & Shareable, min: Int, max_exclusive: Int)->Result[Int, LibraryError]
```

## uuid_v4

Kind: fn.

```manuscript
uuid_v4: fn(entropy: Entropy & Shareable)->Result[String, LibraryError]
```

