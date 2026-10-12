+++
title = "random"
+++

# @std/random.ms

Import each required symbol with `import Name from "@std/random.ms"`.

## Entropy

Kind: interface.

```text
Entropy: Entropy
operation bytes: fn(count: Int)->Result[Bytes, RandomError]
```

## RandomError

Kind: alternative.

```text
RandomError: RandomError
implements: Error
case InvalidInput
case LimitExceeded
case Failed(message: String)
operation message: fn()->String
```

## secure_int

Kind: fn.

```text
secure_int: fn(entropy: Entropy & Shareable, min: Int, max_exclusive: Int)->Result[Int, RandomError]
```

## uuid_v4

Kind: fn.

```text
uuid_v4: fn(entropy: Entropy & Shareable)->Result[String, RandomError]
```

