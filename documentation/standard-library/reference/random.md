+++
title = "random"
+++

# @std/random.ms

Import each required symbol with `import Name from "@std/random.ms"`.

## Entropy {data-api-kind="Interface"}

```manuscript
interface Entropy:
    fn bytes(count: Int) -> Result[Bytes, RandomError]
```

## RandomError {data-api-kind="Alternative"}

```manuscript
type RandomError:
    case InvalidInput
    case LimitExceeded
    case Failed(message: String)
```

```manuscript
impl Error for RandomError:
    fn message() -> String
```

## entropy {data-api-kind="Function"}

```manuscript
fn entropy() -> Entropy
```

## secure_int {data-api-kind="Function"}

```manuscript
fn secure_int(entropy: Entropy, min: Int, max_exclusive: Int) -> Result[Int, RandomError]
```

## uuid_v4 {data-api-kind="Function"}

```manuscript
fn uuid_v4(entropy: Entropy) -> Result[String, RandomError]
```

