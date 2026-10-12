# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export fn contains(value: String, text: String) -> Bool

export fn ends_with(value: String, suffix: String) -> Bool

export fn from_scalars(values: List[Int]) -> Result[String, LibraryError]

export fn join(parts: List[String], separator: String) -> String

export fn lower(text: String) -> String

export fn repeat(text: String, count: Int, max_bytes: Int) -> Result[String, LibraryError]

export fn replace(text: String, old: String, new: String, max_replacements: Int) -> String

export fn scalar_length(text: String) -> Int

export fn scalar_values(text: String) -> List[Int]

export fn slice_scalars(text: String, start: Int, end: Int) -> Result[String, LibraryError]

export fn split(text: String, separator: String, max_parts: Int) -> List[String]

export fn starts_with(value: String, prefix: String) -> Bool

export fn trim(text: String) -> String

export fn upper(text: String) -> String
