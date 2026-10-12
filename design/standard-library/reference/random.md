+++
title = "random"
+++

# @std/random.ms

Import each required symbol with `import Name from "@std/random.ms"`.

## Entropy {data-api-kind="Interface"}

```manuscript
Entropy: Entropy
operation bytes: fn(count: Int)->Result[Bytes, LibraryError]
```

## secure_int {data-api-kind="Function"}

```manuscript
secure_int: fn(entropy: Entropy, min: Int, max_exclusive: Int)->Result[Int, LibraryError]
```

## uuid_v4 {data-api-kind="Function"}

```manuscript
uuid_v4: fn(entropy: Entropy)->Result[String, LibraryError]
```

