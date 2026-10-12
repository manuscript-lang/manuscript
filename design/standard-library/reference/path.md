+++
title = "path"
+++

# @std/path.ms

Import each required symbol with `import Name from "@std/path.ms"`.

## PathError

Kind: alternative.

```text
PathError: PathError
implements: Error
case InvalidInput
operation message: fn()->String
```

## basename

Kind: fn.

```text
basename: fn(path: String)->String
```

## dirname

Kind: fn.

```text
dirname: fn(path: String)->String
```

## extension

Kind: fn.

```text
extension: fn(path: String)->String
```

## is_absolute

Kind: fn.

```text
is_absolute: fn(path: String)->Bool
```

## join

Kind: fn.

```text
join: fn(parts: List[String])->String
```

## normalize

Kind: fn.

```text
normalize: fn(path: String)->String
```

## relative

Kind: fn.

```text
relative: fn(base: String, target: String)->Result[String, PathError]
```

