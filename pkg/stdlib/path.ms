# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# Errors returned when a path cannot be parsed or resolved.
export type PathError:
    # Invalid NUL input, a nonabsolute resolve/relative anchor or malformed glob syntax.
    case InvalidInput

# Returns the final path component, excluding trailing separators.
export fn basename(path: String) -> String:

# Returns the directory portion of a path.
export fn dirname(path: String) -> String:

# Returns the final extension, including its leading dot, or an empty string.
export fn extension(path: String) -> String:

# Reports whether a path is absolute according to the host path rules.
export fn is_absolute(path: String) -> Bool:

# Joins path parts using the host separator and normalizes the result.
export fn join(parts: List[String]) -> String:

# Normalizes separators and dot segments without accessing the filesystem.
export fn normalize(path: String) -> String:

# Computes a relative path from `base` to `target` using host path rules.
export fn relative(base: String, target: String) -> Result[String, PathError]:

# Parsed path components using the familiar root, directory, base, extension, and name fields.
export type PathParts:
    # Root prefix under the chosen path rules, including a POSIX slash or Windows drive/UNC root.
    root: String
    # Directory portion, including the root when present; it takes precedence over root during format.
    directory: String
    # Final component with extension; it takes precedence over name/extension during format.
    base: String
    # Final extension including its dot; simple dotfiles and dot/dot-dot components have no extension.
    extension: String
    # Final component with its extension removed, retaining the original spelling.
    name: String

# Path operations using either POSIX or Windows path conventions.
export interface PathOperations:
    # Returns the last component after ignoring trailing separators under this view's path rules.
    fn basename(path: String) -> String
    # Removes an exact suffix under basename compatibility rules; it does not strip arbitrary extensions.
    fn basename_without(path: String, suffix: String) -> String
    # Returns the directory component using the selected POSIX or Windows convention.
    fn dirname(path: String) -> String
    # Returns the final dot extension, or empty text for extensionless names and simple dotfiles.
    fn extension(path: String) -> String
    # Tests absolute-root syntax; a Windows drive-relative spelling is not absolute.
    fn is_absolute(path: String) -> Bool
    # Joins nonempty parts and normalizes separators/dot segments without filesystem access.
    fn join(parts: List[String]) -> String
    # Cleans repeated separators and dot segments lexically; it does not resolve symlinks.
    fn normalize(path: String) -> String
    # Computes a lexical relative path from absolute anchors; different roots return the original target.
    # Nonabsolute anchors or invalid NUL input return InvalidInput.
    fn relative(base: String, target: String) -> Result[String, PathError]
    # Resolves parts against an explicit absolute base; no process working directory is consulted.
    fn resolve(base: String, parts: List[String]) -> Result[String, PathError]
    # Splits the original spelling into root, directory, base, extension and name without filesystem access.
    fn parse(path: String) -> PathParts
    # Builds a path with directory preferred over root, and base preferred over name plus extension.
    fn format(parts: PathParts) -> String
    # Returns slash for POSIX or backslash for Windows path components.
    fn separator() -> String
    # Returns colon for POSIX or semicolon for Windows path-list entries.
    fn delimiter() -> String
    # Returns a Windows namespaced absolute path when applicable; POSIX paths are unchanged.
    fn to_namespaced_path(path: String) -> String
    # Tests one lexical path against the supported glob syntax; malformed patterns return InvalidInput.
    fn matches_glob(path: String, pattern: String) -> Result[Bool, PathError]

# Returns path operations using POSIX separators and parsing rules.
export fn posix() -> PathOperations:

# Returns path operations using Windows separators and parsing rules.
export fn win32() -> PathOperations:

# Returns the basename with the supplied suffix removed when it matches.
export fn basename_without(path: String, suffix: String) -> String:

# Resolves path parts against a base using host path conventions.
export fn resolve(base: String, parts: List[String]) -> Result[String, PathError]:

# Splits a path into its root, directory, base, extension, and name.
export fn parse(path: String) -> PathParts:

# Formats parsed path components as a path string.
export fn format(parts: PathParts) -> String:

# Returns the host's path separator.
export fn separator() -> String:

# Returns the host's path-list delimiter.
export fn delimiter() -> String:

# Converts a path to the host's namespaced representation when applicable.
export fn to_namespaced_path(path: String) -> String:

# Tests a path against a glob pattern.
export fn matches_glob(path: String, pattern: String) -> Result[Bool, PathError]:

impl Error for PathError:
    # Returns a path-prefixed diagnostic without revealing the supplied paths or pattern.
    fn message() -> String:
