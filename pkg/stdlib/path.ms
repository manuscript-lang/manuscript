# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type PathError:
    case InvalidInput

export fn basename(path: String) -> String:

export fn dirname(path: String) -> String:

export fn extension(path: String) -> String:

export fn is_absolute(path: String) -> Bool:

export fn join(parts: List[String]) -> String:

export fn normalize(path: String) -> String:

export fn relative(base: String, target: String) -> Result[String, PathError]:

export type PathParts:
    root: String
    directory: String
    base: String
    extension: String
    name: String

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

export fn posix() -> PathOperations:

export fn win32() -> PathOperations:

export fn basename_without(path: String, suffix: String) -> String:

export fn resolve(base: String, parts: List[String]) -> Result[String, PathError]:

export fn parse(path: String) -> PathParts:

export fn format(parts: PathParts) -> String:

export fn separator() -> String:

export fn delimiter() -> String:

export fn to_namespaced_path(path: String) -> String:

export fn matches_glob(path: String, pattern: String) -> Result[Bool, PathError]:

impl Error for PathError:
    fn message() -> String:
