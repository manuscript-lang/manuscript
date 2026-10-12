# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type Regex:
    fn matches(text: String) -> Bool
    fn find_all(text: String, max_matches: Int) -> Result[List[String], LibraryError]
    fn replace(text: String, replacement: String, max_bytes: Int) -> Result[String, LibraryError]

export fn compile(pattern: String) -> Result[Regex, LibraryError]

export fn find_all(pattern: Regex, text: String, max_matches: Int) -> Result[List[String], LibraryError]

export fn matches(pattern: Regex, text: String) -> Bool

export fn replace(pattern: Regex, text: String, replacement: String, max_bytes: Int) -> Result[String, LibraryError]
