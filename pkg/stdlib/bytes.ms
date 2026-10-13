# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# An immutable sequence of bytes. Indices and slice bounds are zero-based.
export type Bytes:
    fn clone() -> Bytes:
    fn contains(value: Bytes) -> Bool:
    # Returns bytes from `start` up to but excluding `end`.
    fn slice(start: Int, end: Int) -> Bytes:
    # Returns a byte at a zero-based index, or `none` when out of range.
    fn at(index: Int) -> Optional[Int]:
    fn index_of(value: Bytes) -> Optional[Int]:
    fn last_index_of(value: Bytes) -> Optional[Int]:
    fn starts_with(value: Bytes) -> Bool:
    fn ends_with(value: Bytes) -> Bool:
    fn reverse() -> Bytes:
    # Returns a copy with one byte replaced. Values must be between 0 and 255.
    fn with_value(index: Int, value: Int) -> Bytes:
    fn is_empty() -> Bool:
    values: List[Int]
    fn concat(values: Bytes) -> Bytes:
    # Returns the number of bytes, not the number of Unicode characters.
    fn length() -> Int:
    # Decodes valid UTF-8 as text, or returns `none` when the bytes are invalid.
    fn to_text() -> Optional[String]:

# Returns the byte values as integers in the range 0 through 255.
export fn values(data: Bytes) -> List[Int]:

# Builds a byte sequence efficiently before freezing it into an immutable value.
export type BytesBuilder:
    fn append(value: Int) -> Unit:
    fn concat(values: Bytes) -> Unit:
    fn freeze() -> Bytes:
