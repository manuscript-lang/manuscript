+++
title = "path"
+++

# @std/path.ms

Import each required symbol with `import Name from "@std/path.ms"`.

## basename {data-api-kind="Function"}

```manuscript
basename: fn(path: String)->String
```

## dirname {data-api-kind="Function"}

```manuscript
dirname: fn(path: String)->String
```

## extension {data-api-kind="Function"}

```manuscript
extension: fn(path: String)->String
```

## is_absolute {data-api-kind="Function"}

```manuscript
is_absolute: fn(path: String)->Bool
```

## join {data-api-kind="Function"}

```manuscript
join: fn(parts: List[String])->String
```

## normalize {data-api-kind="Function"}

```manuscript
normalize: fn(path: String)->String
```

## relative {data-api-kind="Function"}

```manuscript
relative: fn(base: String, target: String)->Result[String, LibraryError]
```

