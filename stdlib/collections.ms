# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"

export type List[T]:
    fn append(value: T) -> List[T]
    fn concat(values: List[T]) -> List[T]
    fn get(index: Int) -> Optional[T]
    fn length() -> Int

export type Map[T: Hashable, U]:
    fn contains(key: T) -> Bool
    fn get(key: T) -> Optional[U]
    fn length() -> Int
    fn with_entry(key: T, value: U) -> Map[T, U]
    fn without(key: T) -> Map[T, U]

export type MapEntry[T: Hashable, U]:
    key: T
    value: U

export type Set[T: Hashable]:
    fn contains(value: T) -> Bool
    fn length() -> Int
    fn with_value(value: T) -> Set[T]
    fn without(value: T) -> Set[T]

export fn difference[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]

export fn filter[T](values: List[T], predicate: fn(value: T) -> Bool) -> List[T]

export fn fold[T, A](values: List[T], initial: A, step: fn(accumulator: A, value: T) -> A) -> A

export fn intersection[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]

export fn map[T, U](values: List[T], transform: fn(value: T) -> U) -> List[U]

export fn map_keys[K: Hashable, V](values: Map[K, V]) -> List[K]

export fn map_values[K: Hashable, V](values: Map[K, V]) -> List[V]

export fn reverse[T](values: List[T]) -> List[T]

export fn slice[T](values: List[T], start: Int, end: Int) -> List[T]

export fn sort_ints(values: List[Int]) -> List[Int]

export fn sort_strings(values: List[String]) -> List[String]

export fn sorted[T](values: List[T], compare: fn(left: T, right: T) -> Int) -> List[T]

export fn union[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
