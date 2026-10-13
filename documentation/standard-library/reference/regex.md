+++
title = "regex"
+++

# @std/regex.ms

Import each required symbol with `import Name from "@std/regex.ms"`.

## Regex {data-api-kind="Native type"}

A compiled regular expression that can be reused across input strings.

```manuscript
type Regex:
    fn matches(text: String) -> Bool:
    fn find_all(text: String, max_matches: Optional[Int] = none) -> Result[List[String], RegexError]:
    fn replace_all(text: String, replacement: String, max_bytes: Optional[Int] = none) -> Result[String, RegexError]:
    fn replace(text: String, replacement: String, max_bytes: Optional[Int] = none) -> Result[String, RegexError]:
```

### Regex.replace

Compatibility spelling for replace_all; replaces every match, with identical limits and errors.

```manuscript
fn replace(text: String, replacement: String, max_bytes: Optional[Int] = none) -> Result[String, RegexError]:
```

### Regex.replace_all

Replaces every nonoverlapping match with literal replacement text (no capture expansion).
max_bytes optionally bounds UTF-8 output; negatives return InvalidInput, exhaustion LimitExceeded.

```manuscript
fn replace_all(text: String, replacement: String, max_bytes: Optional[Int] = none) -> Result[String, RegexError]:
```

## RegexError {data-api-kind="Alternative"}

Errors returned for invalid patterns or configured result limits.

```manuscript
type RegexError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for RegexError:
    fn message() -> String:
```

## compile {data-api-kind="Function"}

Compiles a regular expression. Invalid pattern syntax is returned as an error.

```manuscript
fn compile(pattern: String) -> Result[Regex, RegexError]:
```

