# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Optional from "@std/optional.ms"

export type Bytes:
    values: List[Int]
    fn concat(values: Bytes) -> Bytes
    fn get(index: Int) -> Optional[Int]
    fn length() -> Int
    fn to_text() -> Optional[String]

export fn contains(data: Bytes, value: Bytes) -> Bool

export fn slice(data: Bytes, start: Int, end: Int) -> Bytes

export fn values(data: Bytes) -> List[Int]
