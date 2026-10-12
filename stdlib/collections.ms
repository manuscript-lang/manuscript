# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import Result from "@std/result.ms"
import Optional from "@std/optional.ms"

export type List[T: Shareable]:
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
    fn map[U: Shareable](transform: fn(value: T) -> U) -> List[U]
    fn flat_map[U: Shareable](transform: fn(value: T) -> List[U]) -> List[U]
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

export type Map[T: Hashable, U: Shareable]:
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

export type MapEntry[T: Hashable, U: Shareable]:
    key: T
    value: U

export type Set[T: Shareable & Hashable]:
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

export fn filter[T: Shareable](values: List[T], predicate: fn(value: T) -> Bool) -> List[T]

export fn fold[T: Shareable, A](values: List[T], initial: A, step: fn(accumulator: A, value: T) -> A) -> A

export fn intersection[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]

export fn map[T: Shareable, U: Shareable](values: List[T], transform: fn(value: T) -> U) -> List[U]

export fn map_keys[K: Hashable, V: Shareable](values: Map[K, V]) -> List[K]

export fn map_values[K: Hashable, V: Shareable](values: Map[K, V]) -> List[V]

export fn reverse[T: Shareable](values: List[T]) -> List[T]

export fn slice[T: Shareable](values: List[T], start: Int, end: Int) -> List[T]

export fn sort_ints(values: List[Int]) -> List[Int]

export fn sort_strings(values: List[String]) -> List[String]

export fn sorted[T: Shareable](values: List[T], compare: fn(left: T, right: T) -> Int) -> List[T]

export fn union[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]

export type ListEntry[T: Shareable]:
    index: Int
    value: T

export fn at[T: Shareable](values: List[T], index: Int) -> Optional[T]

export fn first[T: Shareable](values: List[T]) -> Optional[T]

export fn last[T: Shareable](values: List[T]) -> Optional[T]

export fn is_empty[T: Shareable](values: List[T]) -> Bool

export fn contains[T: Shareable & Equal](values: List[T], value: T) -> Bool

export fn index_of[T: Shareable & Equal](values: List[T], value: T) -> Optional[Int]

export fn last_index_of[T: Shareable & Equal](values: List[T], value: T) -> Optional[Int]

export fn prepend[T: Shareable](values: List[T], value: T) -> List[T]

export fn with_value[T: Shareable](values: List[T], index: Int, value: T) -> List[T]

export fn without[T: Shareable](values: List[T], index: Int) -> List[T]

export fn find[T: Shareable](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[T]

export fn find_last[T: Shareable](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[T]

export fn find_index[T: Shareable](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[Int]

export fn find_last_index[T: Shareable](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[Int]

export fn some[T: Shareable](values: List[T], predicate: fn(value: T) -> Bool) -> Bool

export fn every[T: Shareable](values: List[T], predicate: fn(value: T) -> Bool) -> Bool

export fn for_each[T: Shareable](values: List[T], operation: fn(value: T) -> Unit) -> Unit

export fn flat_map[T: Shareable, U: Shareable](values: List[T], transform: fn(value: T) -> List[U]) -> List[U]

export fn flatten[T: Shareable](values: List[List[T]]) -> List[T]

export fn fold_right[T: Shareable, A](values: List[T], initial: A, step: fn(accumulator: A, value: T) -> A) -> A

export fn with_values[T: Shareable](values: List[T], start: Int, delete_count: Int, replacement: List[T]) -> List[T]

export fn fill[T: Shareable](values: List[T], value: T, start: Int, end: Int) -> List[T]

export fn copy_within[T: Shareable](values: List[T], target: Int, start: Int, end: Int) -> List[T]

export fn list_keys[T: Shareable](values: List[T]) -> List[Int]

export fn list_entries[T: Shareable](values: List[T]) -> List[ListEntry[T]]

export fn to_set[T: Shareable & Hashable](values: List[T]) -> Set[T]

export fn filled[T: Shareable](value: T, count: Int, max_items: Int) -> Result[List[T], LibraryError]

export fn range(start: Int, end: Int, step: Int, max_items: Int) -> Result[List[Int], LibraryError]

export fn map_clear[K: Hashable, V: Shareable](values: Map[K, V]) -> Map[K, V]

export fn map_entries[K: Hashable, V: Shareable](values: Map[K, V]) -> List[MapEntry[K, V]]

export fn map_merge[K: Hashable, V: Shareable](values: Map[K, V], other: Map[K, V]) -> Map[K, V]

export fn map_for_each[K: Hashable, V: Shareable](values: Map[K, V], operation: fn(key: K, value: V) -> Unit) -> Unit

export fn map_from_entries[K: Hashable, V: Shareable](entries: List[MapEntry[K, V]]) -> Map[K, V]

export fn set_clear[T: Hashable](values: Set[T]) -> Set[T]

export fn set_values[T: Hashable](values: Set[T]) -> List[T]

export fn set_entries[T: Hashable](values: Set[T]) -> List[List[T]]

export fn set_for_each[T: Hashable](values: Set[T], operation: fn(value: T) -> Unit) -> Unit

export fn symmetric_difference[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]

export fn is_subset_of[T: Hashable](left: Set[T], right: Set[T]) -> Bool

export fn is_superset_of[T: Hashable](left: Set[T], right: Set[T]) -> Bool

export fn is_disjoint_from[T: Hashable](left: Set[T], right: Set[T]) -> Bool

export fn group_by[T: Shareable, K: Hashable](values: List[T], key: fn(value: T) -> K) -> Map[K, List[T]]

export fn map_with_default[K: Hashable, V: Shareable](values: Map[K, V], key: K, value: V) -> Map[K, V]

export fn map_with_default_from[K: Hashable, V: Shareable](values: Map[K, V], key: K, create: fn(key: K) -> V) -> Map[K, V]
