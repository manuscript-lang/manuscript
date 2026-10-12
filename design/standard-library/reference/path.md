+++
title = "path"
+++

# @std/path.ms

Import each required symbol with `import Name from "@std/path.ms"`.

## basename

Kind: fn.

```manuscript
basename: fn(path: String)->String
```

## dirname

Kind: fn.

```manuscript
dirname: fn(path: String)->String
```

## extension

Kind: fn.

```manuscript
extension: fn(path: String)->String
```

## is_absolute

Kind: fn.

```manuscript
is_absolute: fn(path: String)->Bool
```

## join

Kind: fn.

```manuscript
join: fn(parts: List[String])->String
```

## normalize

Kind: fn.

```manuscript
normalize: fn(path: String)->String
```

## relative

Kind: fn.

```manuscript
relative: fn(base: String, target: String)->Result[String, LibraryError]
```

