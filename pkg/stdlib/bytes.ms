# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Optional from "@std/optional.ms"

export type Bytes:
    fn clone() -> Bytes
    fn contains(value: Bytes) -> Bool
    fn slice(start: Int, end: Int) -> Bytes
    fn at(index: Int) -> Optional[Int]
    fn index_of(value: Bytes) -> Optional[Int]
    fn last_index_of(value: Bytes) -> Optional[Int]
    fn starts_with(value: Bytes) -> Bool
    fn ends_with(value: Bytes) -> Bool
    fn reverse() -> Bytes
    fn with_value(index: Int, value: Int) -> Bytes
    fn is_empty() -> Bool
    values: List[Int]
    fn concat(values: Bytes) -> Bytes
    fn length() -> Int
    fn to_text() -> Optional[String]

export fn values(data: Bytes) -> List[Int]

export type BytesBuilder:
    fn append(value: Int) -> Unit
    fn concat(values: Bytes) -> Unit
    fn freeze() -> Bytes
