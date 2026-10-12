# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Result from "@std/result.ms"
import Optional from "@std/optional.ms"

export type CollectionError:
    case InvalidInput
    case LimitExceeded

export type List[T]:
    fn clone() -> List[T]
    fn at(index: Int) -> Optional[T]
    fn contains(value: T) -> Bool
    fn index_of(value: T) -> Optional[Int]
    fn last_index_of(value: T) -> Optional[Int]
    fn first() -> Optional[T]
    fn last() -> Optional[T]
    fn is_empty() -> Bool
    fn prepend(value: T) -> List[T]
    fn with_value(index: Int, value: T) -> List[T]
    fn without(index: Int) -> List[T]
    fn slice(start: Int, end: Int) -> List[T]
    fn reverse() -> List[T]
    fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]
    fn filter(predicate: fn(value: T) -> Bool) -> List[T]
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]
    fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]
    fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]
    fn some(predicate: fn(value: T) -> Bool) -> Bool
    fn every(predicate: fn(value: T) -> Bool) -> Bool
    fn for_each(operation: fn(value: T) -> Unit) -> Unit
    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]
    fn map[U](transform: fn(value: T) -> U) -> List[U]
    fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A
    fn with_values(start: Int, delete_count: Int, replacement: List[T]) -> List[T]
    fn fill(value: T, start: Int, end: Int) -> List[T]
    fn copy_within(target: Int, start: Int, end: Int) -> List[T]
    fn to_set() -> Set[T]
    fn keys() -> List[Int]
    fn entries() -> List[ListEntry[T]]
    fn join(separator: String) -> String
    fn append(value: T) -> List[T]
    fn concat(values: List[T]) -> List[T]
    fn length() -> Int

export type Map[T: Hashable, U]:
    fn clone() -> Map[T, U]
    fn with_default(key: T, value: U) -> Map[T, U]
    fn with_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]
    fn clear() -> Map[T, U]
    fn keys() -> List[T]
    fn values() -> List[U]
    fn entries() -> List[MapEntry[T, U]]
    fn merge(other: Map[T, U]) -> Map[T, U]
    fn for_each(operation: fn(key: T, value: U) -> Unit) -> Unit
    fn contains(key: T) -> Bool
    fn get(key: T) -> Optional[U]
    fn length() -> Int
    fn with_entry(key: T, value: U) -> Map[T, U]
    fn without(key: T) -> Map[T, U]

export type MapEntry[T: Hashable, U]:
    key: T
    value: U

export type Set[T: Hashable]:
    fn clone() -> Set[T]
    fn union(right: Set[T]) -> Set[T]
    fn intersection(right: Set[T]) -> Set[T]
    fn difference(right: Set[T]) -> Set[T]
    fn symmetric_difference(right: Set[T]) -> Set[T]
    fn is_subset_of(right: Set[T]) -> Bool
    fn is_superset_of(right: Set[T]) -> Bool
    fn is_disjoint_from(right: Set[T]) -> Bool
    fn clear() -> Set[T]
    fn values() -> List[T]
    fn entries() -> List[List[T]]
    fn for_each(operation: fn(value: T) -> Unit) -> Unit
    fn contains(value: T) -> Bool
    fn length() -> Int
    fn with_value(value: T) -> Set[T]
    fn without(value: T) -> Set[T]

export type ListEntry[T]:
    index: Int
    value: T

export fn filled[T](value: T, count: Int, max_items: Optional[Int] = none) -> Result[List[T], CollectionError]

export fn range(start: Int, end: Int, step: Int, max_items: Optional[Int] = none) -> Result[List[Int], CollectionError]

export fn map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) -> Map[K, V]

impl Error for CollectionError:
    fn message() -> String

export type ListBuilder[T]:
    fn append(value: T) -> Unit
    fn freeze() -> List[T]

export type MapBuilder[T: Hashable, U]:
    fn freeze() -> Map[T, U]
    fn with_entry(key: T, value: U) -> Unit

export type SetBuilder[T: Hashable]:
    fn freeze() -> Set[T]
    fn with_value(value: T) -> Unit
