+++
title = "regex"
+++

# @std/regex.ms

Import each required symbol with `import Name from "@std/regex.ms"`.

## Regex

Kind: native.

```manuscript
Regex: Regex
```

## compile

Kind: fn.

```manuscript
compile: fn(pattern: String)->Result[Regex, LibraryError]
```

## find_all

Kind: fn.

```manuscript
find_all: fn(pattern: Regex, text: String, max_matches: Int)->Result[List[String], LibraryError]
```

## matches

Kind: fn.

```manuscript
matches: fn(pattern: Regex, text: String)->Bool
```

## replace

Kind: fn.

```manuscript
replace: fn(pattern: Regex, text: String, replacement: String, max_bytes: Int)->Result[String, LibraryError]
```

