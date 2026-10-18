import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"

fn slice(values: List[Int]) -> Result[List[Int], CollectionError]: values.slice(0, 1)

fn list_entries[T](values: List[T]) -> List[ListEntry[T]]: values.entries()

fn map_entries[K: Hashable, V](values: Map[K, V]) -> List[MapEntry[K, V]]: values.entries()

fn group[T, K: Hashable](values: List[T], key: fn(value: T) -> K) -> Map[K, List[T]]: values.group_by(
    key
)

fn index[T: Equal](values: List[T], value: T) -> Optional[Int]: values.index_of(value)

fn first(values: List[Int]) -> Result[Int, MissingValue]: values.at(0).ok_or()

fn unique[T: Hashable](values: List[T]) -> Set[T]: values.to_set()

fn explain(cause: CollectionError) -> String:
    let common: Error = cause
    return common.message()

test "public collection support types retain their standard runtime identities":
    let values = [3, 4]
    let entries: List[ListEntry[Int]] = list_entries(values)
    let entry: ListEntry[Int] = ListEntry(0, 3)
    entries[0].unwrap() | try expect_equal(expected: entry)
    let map = Map[String, Int]().add("a", 3)
    let pairs: List[MapEntry[String, Int]] = map_entries(map)
    let pair: MapEntry[String, Int] = MapEntry("a", 3)
    let found: Optional[MapEntry[String, Int]] = map.find(
        fn(key: String, value: Int) -> Bool: (value == 3)
    )
    (pairs[0].unwrap() != pair or found.unwrap() != pair) | try expect_false
    let selected: Result[List[Int], CollectionError] = slice(values)
    selected.unwrap() | try expect_equal(expected: [3])
    let invalid: Result[List[Int], CollectionError] = values.slice(0, 9)
    let cause: CollectionError = invalid.unwrap_error()
    (cause != CollectionError.OutOfRange or explain(cause).is_empty()) | try expect_false

    match cause:
        OutOfRange: unit
        _: return fail("scrutinee directed pattern")

    let grouped: Map[Int, List[Int]] = group(values, fn(value: Int) -> Int: value % 2)
    let distinct: Set[Int] = unique(values)
    (grouped.get(1).unwrap() != [3] or distinct.values() != [3, 4]) | try expect_false
    index(values, 4).unwrap() | try expect_equal(expected: 1)
    let absent: Result[Int, MissingValue] = first([])
    let missing: MissingValue = absent.unwrap_error()
    let common: Error = missing
    (common.message().contains("collection-prelude-support.ms:")) | try expect_true
    first(values).unwrap() | try expect_equal(expected: 3)

type OtherError:
    case OutOfRange

test "new ambient error cases retain scrutinee directed patterns":
    let other = OtherError.OutOfRange

    match other:
        OutOfRange: unit

    let cause = [1].slice(0, 2).unwrap_error()

    match cause:
        OutOfRange: unit
        _: return fail("wrong standard case")
