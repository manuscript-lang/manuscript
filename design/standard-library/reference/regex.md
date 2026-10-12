+++
title = "regex"
+++

# @std/regex.ms

Import each required symbol with `import Name from "@std/regex.ms"`.

## Regex

Kind: native.

```text
Regex: Regex
```

## RegexError

Kind: alternative.

```text
RegexError: RegexError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
operation message: fn()->String
```

## compile

Kind: fn.

```text
compile: fn(pattern: String)->Result[Regex, RegexError]
```

## find_all

Kind: fn.

```text
find_all: fn(pattern: Regex, text: String, max_matches: Int)->Result[List[String], RegexError]
```

## matches

Kind: fn.

```text
matches: fn(pattern: Regex, text: String)->Bool
```

## replace

Kind: fn.

```text
replace: fn(pattern: Regex, text: String, replacement: String, max_bytes: Int)->Result[String, RegexError]
```

