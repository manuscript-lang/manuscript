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
    fn get(index: Int) -> Optional[T]
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

export type ListEntry[T]:
    index: Int
    value: T

export fn at[T](values: List[T], index: Int) -> Optional[T]

export fn first[T](values: List[T]) -> Optional[T]

export fn last[T](values: List[T]) -> Optional[T]

export fn is_empty[T](values: List[T]) -> Bool

export fn contains[T: Equal](values: List[T], value: T) -> Bool

export fn index_of[T: Equal](values: List[T], value: T) -> Optional[Int]

export fn last_index_of[T: Equal](values: List[T], value: T) -> Optional[Int]

export fn prepend[T](values: List[T], value: T) -> List[T]

export fn with_value[T](values: List[T], index: Int, value: T) -> List[T]

export fn without[T](values: List[T], index: Int) -> List[T]

export fn find[T](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[T]

export fn find_last[T](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[T]

export fn find_index[T](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[Int]

export fn find_last_index[T](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[Int]

export fn some[T](values: List[T], predicate: fn(value: T) -> Bool) -> Bool

export fn every[T](values: List[T], predicate: fn(value: T) -> Bool) -> Bool

export fn for_each[T](values: List[T], operation: fn(value: T) -> Unit) -> Unit

export fn flat_map[T, U](values: List[T], transform: fn(value: T) -> List[U]) -> List[U]

export fn flatten[T](values: List[List[T]]) -> List[T]

export fn fold_right[T, A](values: List[T], initial: A, step: fn(accumulator: A, value: T) -> A) -> A

export fn with_values[T](values: List[T], start: Int, delete_count: Int, replacement: List[T]) -> List[T]

export fn fill[T](values: List[T], value: T, start: Int, end: Int) -> List[T]

export fn copy_within[T](values: List[T], target: Int, start: Int, end: Int) -> List[T]

export fn list_keys[T](values: List[T]) -> List[Int]

export fn list_entries[T](values: List[T]) -> List[ListEntry[T]]

export fn to_set[T: Hashable](values: List[T]) -> Set[T]

export fn filled[T](value: T, count: Int, max_items: Int) -> Result[List[T], CollectionError]

export fn range(start: Int, end: Int, step: Int, max_items: Int) -> Result[List[Int], CollectionError]

export fn map_clear[K: Hashable, V](values: Map[K, V]) -> Map[K, V]

export fn map_entries[K: Hashable, V](values: Map[K, V]) -> List[MapEntry[K, V]]

export fn map_merge[K: Hashable, V](values: Map[K, V], other: Map[K, V]) -> Map[K, V]

export fn map_for_each[K: Hashable, V](values: Map[K, V], operation: fn(key: K, value: V) -> Unit) -> Unit

export fn map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) -> Map[K, V]

export fn set_clear[T: Hashable](values: Set[T]) -> Set[T]

export fn set_values[T: Hashable](values: Set[T]) -> List[T]

export fn set_entries[T: Hashable](values: Set[T]) -> List[List[T]]

export fn set_for_each[T: Hashable](values: Set[T], operation: fn(value: T) -> Unit) -> Unit

export fn symmetric_difference[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]

export fn is_subset_of[T: Hashable](left: Set[T], right: Set[T]) -> Bool

export fn is_superset_of[T: Hashable](left: Set[T], right: Set[T]) -> Bool

export fn is_disjoint_from[T: Hashable](left: Set[T], right: Set[T]) -> Bool

export fn group_by[T, K: Hashable](values: List[T], key: fn(value: T) -> K) -> Map[K, List[T]]

export fn map_with_default[K: Hashable, V](values: Map[K, V], key: K, value: V) -> Map[K, V]

export fn map_with_default_from[K: Hashable, V](values: Map[K, V], key: K, create: fn(key: K) -> V) -> Map[K, V]

impl Error for CollectionError:
    fn message() -> String
