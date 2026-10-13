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
    fn message() -> String:
```

## PathOperations {data-api-kind="Interface"}

```manuscript
interface PathOperations:
    fn basename(path: String) -> String
    fn basename_without(path: String, suffix: String) -> String
    fn dirname(path: String) -> String
    fn extension(path: String) -> String
    fn is_absolute(path: String) -> Bool
    fn join(parts: List[String]) -> String
    fn normalize(path: String) -> String
    fn relative(base: String, target: String) -> Result[String, PathError]
    fn resolve(base: String, parts: List[String]) -> Result[String, PathError]
    fn parse(path: String) -> PathParts
    fn format(parts: PathParts) -> String
    fn separator() -> String
    fn delimiter() -> String
    fn to_namespaced_path(path: String) -> String
    fn matches_glob(path: String, pattern: String) -> Result[Bool, PathError]
```

## PathParts {data-api-kind="Record"}

```manuscript
type PathParts:
    root: String
    directory: String
    base: String
    extension: String
    name: String
```

## basename {data-api-kind="Function"}

```manuscript
fn basename(path: String) -> String:
```

## basename_without {data-api-kind="Function"}

```manuscript
fn basename_without(path: String, suffix: String) -> String:
```

## delimiter {data-api-kind="Function"}

```manuscript
fn delimiter() -> String:
```

## dirname {data-api-kind="Function"}

```manuscript
fn dirname(path: String) -> String:
```

## extension {data-api-kind="Function"}

```manuscript
fn extension(path: String) -> String:
```

## format {data-api-kind="Function"}

```manuscript
fn format(parts: PathParts) -> String:
```

## is_absolute {data-api-kind="Function"}

```manuscript
fn is_absolute(path: String) -> Bool:
```

## join {data-api-kind="Function"}

```manuscript
fn join(parts: List[String]) -> String:
```

## matches_glob {data-api-kind="Function"}

```manuscript
fn matches_glob(path: String, pattern: String) -> Result[Bool, PathError]:
```

## normalize {data-api-kind="Function"}

```manuscript
fn normalize(path: String) -> String:
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(path: String) -> PathParts:
```

## posix {data-api-kind="Function"}

```manuscript
fn posix() -> PathOperations:
```

## relative {data-api-kind="Function"}

```manuscript
fn relative(base: String, target: String) -> Result[String, PathError]:
```

## resolve {data-api-kind="Function"}

```manuscript
fn resolve(base: String, parts: List[String]) -> Result[String, PathError]:
```

## separator {data-api-kind="Function"}

```manuscript
fn separator() -> String:
```

## to_namespaced_path {data-api-kind="Function"}

```manuscript
fn to_namespaced_path(path: String) -> String:
```

## win32 {data-api-kind="Function"}

```manuscript
fn win32() -> PathOperations:
```

