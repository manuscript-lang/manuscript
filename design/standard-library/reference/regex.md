+++
title = "regex"
+++

# @std/regex.ms

Import each required symbol with `import Name from "@std/regex.ms"`.

## Regex

Kind: interface.

```text
Regex: Regex
operation find_all: fn(text: String, max_matches: Int)->Result[List[String], LibraryError]
operation matches: fn(text: String)->Bool
operation replace: fn(text: String, replacement: String, max_bytes: Int)->Result[String, LibraryError]
```

## compile

Kind: fn.

```text
compile: fn(pattern: String)->Result[Regex, LibraryError]
```

## find_all

Kind: fn.

```text
find_all: fn(pattern: Regex, text: String, max_matches: Int)->Result[List[String], LibraryError]
```

## matches

Kind: fn.

```text
matches: fn(pattern: Regex, text: String)->Bool
```

## replace

Kind: fn.

```text
replace: fn(pattern: Regex, text: String, replacement: String, max_bytes: Int)->Result[String, LibraryError]
```

