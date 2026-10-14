+++
title = "path"
+++

# @std/path.ms

Import each required symbol with `import Name from "@std/path.ms"`.

## PathError {data-api-kind="Alternative"}

Errors returned when a path cannot be parsed or resolved.

```manuscript
type PathError:
    case InvalidInput
```

```manuscript
impl Error for PathError:
    fn message() -> String:
```

### PathError.InvalidInput

Invalid NUL input, a nonabsolute resolve/relative anchor or malformed glob syntax.

```manuscript
case InvalidInput
```

### PathError.Error.message

Returns a path-prefixed diagnostic without revealing the supplied paths or pattern.

```manuscript
fn message() -> String:
```

## PathOperations {data-api-kind="Interface"}

Path operations using either POSIX or Windows path conventions.

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

### PathOperations.basename

Returns the last component after ignoring trailing separators under this view's path rules.

```manuscript
fn basename(path: String) -> String
```

### PathOperations.basename_without

Removes an exact suffix under basename compatibility rules; it does not strip arbitrary extensions.

```manuscript
fn basename_without(path: String, suffix: String) -> String
```

### PathOperations.delimiter

Returns colon for POSIX or semicolon for Windows path-list entries.

```manuscript
fn delimiter() -> String
```

### PathOperations.dirname

Returns the directory component using the selected POSIX or Windows convention.

```manuscript
fn dirname(path: String) -> String
```

### PathOperations.extension

Returns the final dot extension, or empty text for extensionless names and simple dotfiles.

```manuscript
fn extension(path: String) -> String
```

### PathOperations.format

Builds a path with directory preferred over root, and base preferred over name plus extension.

```manuscript
fn format(parts: PathParts) -> String
```

### PathOperations.is_absolute

Tests absolute-root syntax; a Windows drive-relative spelling is not absolute.

```manuscript
fn is_absolute(path: String) -> Bool
```

### PathOperations.join

Joins nonempty parts and normalizes separators/dot segments without filesystem access.

```manuscript
fn join(parts: List[String]) -> String
```

### PathOperations.matches_glob

Tests one lexical path against the supported glob syntax; malformed patterns return InvalidInput.

```manuscript
fn matches_glob(path: String, pattern: String) -> Result[Bool, PathError]
```

### PathOperations.normalize

Cleans repeated separators and dot segments lexically; it does not resolve symlinks.

```manuscript
fn normalize(path: String) -> String
```

### PathOperations.parse

Splits the original spelling into root, directory, base, extension and name without filesystem access.

```manuscript
fn parse(path: String) -> PathParts
```

### PathOperations.relative

Computes a lexical relative path from absolute anchors; different roots return the original target.
Nonabsolute anchors or invalid NUL input return InvalidInput.

```manuscript
fn relative(base: String, target: String) -> Result[String, PathError]
```

### PathOperations.resolve

Resolves parts against an explicit absolute base; no process working directory is consulted.

```manuscript
fn resolve(base: String, parts: List[String]) -> Result[String, PathError]
```

### PathOperations.separator

Returns slash for POSIX or backslash for Windows path components.

```manuscript
fn separator() -> String
```

### PathOperations.to_namespaced_path

Returns a Windows namespaced absolute path when applicable; POSIX paths are unchanged.

```manuscript
fn to_namespaced_path(path: String) -> String
```

## PathParts {data-api-kind="Record"}

Parsed path components using the familiar root, directory, base, extension, and name fields.

```manuscript
type PathParts:
    root: String
    directory: String
    base: String
    extension: String
    name: String
```

### PathParts.base

Final component with extension; it takes precedence over name/extension during format.

```manuscript
base: String
```

### PathParts.directory

Directory portion, including the root when present; it takes precedence over root during format.

```manuscript
directory: String
```

### PathParts.extension

Final extension including its dot; simple dotfiles and dot/dot-dot components have no extension.

```manuscript
extension: String
```

### PathParts.name

Final component with its extension removed, retaining the original spelling.

```manuscript
name: String
```

### PathParts.root

Root prefix under the chosen path rules, including a POSIX slash or Windows drive/UNC root.

```manuscript
root: String
```

## basename {data-api-kind="Function"}

Returns the final path component, excluding trailing separators.

```manuscript
fn basename(path: String) -> String:
```

## basename_without {data-api-kind="Function"}

Returns the basename with the supplied suffix removed when it matches.

```manuscript
fn basename_without(path: String, suffix: String) -> String:
```

## delimiter {data-api-kind="Function"}

Returns the host's path-list delimiter.

```manuscript
fn delimiter() -> String:
```

## dirname {data-api-kind="Function"}

Returns the directory portion of a path.

```manuscript
fn dirname(path: String) -> String:
```

## extension {data-api-kind="Function"}

Returns the final extension, including its leading dot, or an empty string.

```manuscript
fn extension(path: String) -> String:
```

## format {data-api-kind="Function"}

Formats parsed path components as a path string.

```manuscript
fn format(parts: PathParts) -> String:
```

## is_absolute {data-api-kind="Function"}

Reports whether a path is absolute according to the host path rules.

```manuscript
fn is_absolute(path: String) -> Bool:
```

## join {data-api-kind="Function"}

Joins path parts using the host separator and normalizes the result.

```manuscript
fn join(parts: List[String]) -> String:
```

## matches_glob {data-api-kind="Function"}

Tests a path against a glob pattern.

```manuscript
fn matches_glob(path: String, pattern: String) -> Result[Bool, PathError]:
```

## normalize {data-api-kind="Function"}

Normalizes separators and dot segments without accessing the filesystem.

```manuscript
fn normalize(path: String) -> String:
```

## parse {data-api-kind="Function"}

Splits a path into its root, directory, base, extension, and name.

```manuscript
fn parse(path: String) -> PathParts:
```

## posix {data-api-kind="Function"}

Returns path operations using POSIX separators and parsing rules.

```manuscript
fn posix() -> PathOperations:
```

## relative {data-api-kind="Function"}

Computes a relative path from `base` to `target` using host path rules.

```manuscript
fn relative(base: String, target: String) -> Result[String, PathError]:
```

## resolve {data-api-kind="Function"}

Resolves path parts against a base using host path conventions.

```manuscript
fn resolve(base: String, parts: List[String]) -> Result[String, PathError]:
```

## separator {data-api-kind="Function"}

Returns the host's path separator.

```manuscript
fn separator() -> String:
```

## to_namespaced_path {data-api-kind="Function"}

Converts a path to the host's namespaced representation when applicable.

```manuscript
fn to_namespaced_path(path: String) -> String:
```

## win32 {data-api-kind="Function"}

Returns path operations using Windows separators and parsing rules.

```manuscript
fn win32() -> PathOperations:
```

