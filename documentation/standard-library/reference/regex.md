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
    fn find(text: String) -> Optional[RegexMatch]:
    fn split(text: String, max_parts: Optional[Int] = none) -> Result[List[String], RegexError]:
    fn find_all(text: String, max_matches: Optional[Int] = none) -> Result[List[String], RegexError]:
    fn replace_all(text: String, replacement: String, max_bytes: Optional[Int] = none) -> Result[String, RegexError]:
    fn replace(text: String, replacement: String, max_bytes: Optional[Int] = none) -> Result[String, RegexError]:
```

### Regex.find

Returns the first full match, its scalar positions and optional capture groups, or none.

```manuscript
fn find(text: String) -> Optional[RegexMatch]:
```

### Regex.find_all

Returns nonoverlapping full-match text in occurrence order, excluding capture groups.
A supplied cap is a strict budget, not truncation; zero-width matches follow native regexp rules.

```manuscript
fn find_all(text: String, max_matches: Optional[Int] = none) -> Result[List[String], RegexError]:
```

### Regex.matches

Tests whether any match occurs; anchor the pattern explicitly to require a whole-string match.

```manuscript
fn matches(text: String) -> Bool:
```

### Regex.replace

Compatibility spelling for replace_all; replaces every match, with identical limits and errors.

```manuscript
fn replace(text: String, replacement: String, max_bytes: Optional[Int] = none) -> Result[String, RegexError]:
```

### Regex.replace_all

Replaces every nonoverlapping match with literal replacement text; $ and capture names are not expanded.
max_bytes optionally bounds UTF-8 output; negatives return InvalidInput, exhaustion LimitExceeded.

```manuscript
fn replace_all(text: String, replacement: String, max_bytes: Optional[Int] = none) -> Result[String, RegexError]:
```

### Regex.split

Splits at nonoverlapping full matches; capture groups are not returned.
Omitted/none max_parts is unlimited, zero returns no parts, negatives return InvalidInput.
A cap truncates parts rather than retaining the unsplit remainder; zero-width matches follow native regexp rules.

```manuscript
fn split(text: String, max_parts: Optional[Int] = none) -> Result[List[String], RegexError]:
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

### RegexError.InvalidData

Pattern syntax is invalid for the native RE2-compatible regular-expression engine.

```manuscript
case InvalidData
```

### RegexError.InvalidInput

A supplied match-count or output-byte budget is negative.

```manuscript
case InvalidInput
```

### RegexError.LimitExceeded

More matches exist than permitted, or replacement output exceeds its byte budget.

```manuscript
case LimitExceeded
```

### RegexError.Error.message

Returns a regular-expression-prefixed diagnostic without echoing pattern or input text.

```manuscript
fn message() -> String:
```

## RegexMatch {data-api-kind="Record"}

The first full match, with half-open Unicode scalar positions in the input.

```manuscript
type RegexMatch:
    text: String
    start: Int
    end: Int
    groups: List[Optional[String]]
```

### RegexMatch.end

Unicode scalar position immediately after the full match.

```manuscript
end: Int
```

### RegexMatch.groups

Capture groups only, in pattern order; unmatched groups are none, empty matches some("").

```manuscript
groups: List[Optional[String]]
```

### RegexMatch.start

Zero-based Unicode scalar position where the full match begins.

```manuscript
start: Int
```

### RegexMatch.text

Full matched text; an empty match contains empty text.

```manuscript
text: String
```

## compile {data-api-kind="Function"}

Compiles a regular expression. Invalid pattern syntax is returned as an error.

```manuscript
fn compile(pattern: String) -> Result[Regex, RegexError]:
```

