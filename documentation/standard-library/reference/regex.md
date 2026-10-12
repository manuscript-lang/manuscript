+++
title = "regex"
+++

# @std/regex.ms

Import each required symbol with `import Name from "@std/regex.ms"`.

## Regex {data-api-kind="Native type"}

```manuscript
type Regex:
    fn matches(text: String) -> Bool
    fn find_all(text: String, max_matches: Int) -> Result[List[String], RegexError]
    fn replace(text: String, replacement: String, max_bytes: Int) -> Result[String, RegexError]
```

## RegexError {data-api-kind="Alternative"}

```manuscript
type RegexError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for RegexError:
    fn message() -> String
```

## compile {data-api-kind="Function"}

```manuscript
fn compile(pattern: String) -> Result[Regex, RegexError]
```

## find_all {data-api-kind="Function"}

```manuscript
fn find_all(pattern: Regex, text: String, max_matches: Int) -> Result[List[String], RegexError]
```

## matches {data-api-kind="Function"}

```manuscript
fn matches(pattern: Regex, text: String) -> Bool
```

## replace {data-api-kind="Function"}

```manuscript
fn replace(pattern: Regex, text: String, replacement: String, max_bytes: Int) -> Result[String, RegexError]
```

