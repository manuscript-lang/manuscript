# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Set from "@std/collections.ms"

export type BytesBuilder:
    fn append(value: Int) -> Unit
    fn concat(values: Bytes) -> Unit
    fn freeze() -> Bytes

export type ListBuilder[T: Shareable]:
    fn append(value: T) -> Unit
    fn freeze() -> List[T]

export type MapBuilder[T: Hashable, U: Shareable]:
    fn freeze() -> Map[T, U]
    fn with_entry(key: T, value: U) -> Unit

export type SetBuilder[T: Hashable]:
    fn freeze() -> Set[T]
    fn with_value(value: T) -> Unit

export type StringBuilder:
    fn append(value: String) -> Unit
    fn freeze() -> String
