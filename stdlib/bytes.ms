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
    fn get(index: Int) -> Optional[Int]
    fn length() -> Int
    fn to_text() -> Optional[String]

export fn contains(data: Bytes, value: Bytes) -> Bool

export fn slice(data: Bytes, start: Int, end: Int) -> Bytes

export fn values(data: Bytes) -> List[Int]

export fn at(data: Bytes, index: Int) -> Optional[Int]

export fn index_of(data: Bytes, value: Bytes) -> Optional[Int]

export fn last_index_of(data: Bytes, value: Bytes) -> Optional[Int]

export fn starts_with(data: Bytes, value: Bytes) -> Bool

export fn ends_with(data: Bytes, value: Bytes) -> Bool

export fn reverse(data: Bytes) -> Bytes

export fn with_value(data: Bytes, index: Int, value: Int) -> Bytes

export fn is_empty(data: Bytes) -> Bool
