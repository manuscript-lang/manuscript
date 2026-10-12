+++
title = "path"
+++

# @std/path.ms

Import each required symbol with `import Name from "@std/path.ms"`.

## PathError {data-api-kind="Alternative"}

```manuscript
type PathError:
    case InvalidInput
```

```manuscript
impl Error for PathError:
    fn message() -> String
```

## basename {data-api-kind="Function"}

```manuscript
fn basename(path: String) -> String
```

## dirname {data-api-kind="Function"}

```manuscript
fn dirname(path: String) -> String
```

## extension {data-api-kind="Function"}

```manuscript
fn extension(path: String) -> String
```

## is_absolute {data-api-kind="Function"}

```manuscript
fn is_absolute(path: String) -> Bool
```

## join {data-api-kind="Function"}

```manuscript
fn join(parts: List[String]) -> String
```

## normalize {data-api-kind="Function"}

```manuscript
fn normalize(path: String) -> String
```

## relative {data-api-kind="Function"}

```manuscript
fn relative(base: String, target: String) -> Result[String, PathError]
```

