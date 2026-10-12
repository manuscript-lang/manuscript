+++
title = "random"
+++

# @std/random.ms

Import each required symbol with `import Name from "@std/random.ms"`.

## Entropy {data-api-kind="Interface"}

```manuscript
interface Entropy:
    fn bytes(count: Int) -> Result[Bytes, LibraryError]
```

## secure_int {data-api-kind="Function"}

```manuscript
fn secure_int(entropy: Entropy, min: Int, max_exclusive: Int) -> Result[Int, LibraryError]
```

## uuid_v4 {data-api-kind="Function"}

```manuscript
fn uuid_v4(entropy: Entropy) -> Result[String, LibraryError]
```

