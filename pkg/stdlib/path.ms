# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

# Errors returned when a path cannot be parsed or resolved.
export type PathError:
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
    root: String
    directory: String
    base: String
    extension: String
    name: String

# Path operations using either POSIX or Windows path conventions.
export interface PathOperations:
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
    fn message() -> String:
