# conform: tags=aliasing,alternatives,closures,faults,generics,lists,maps,match,modules,optional,records,sets,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/collection-prelude-support.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"

fn slice(values: List[Int]) List[Int]!CollectionError: values.slice(0, 1)

fn list_entries[T: Clonable](values: List[T]) List[ListEntry[T]]: values.entries()

fn map_entries[K: Hashable, V: Clonable](values: Map[K, V]) List[MapEntry[K, V]]: values.entries()

fn group[T: Clonable, K: Hashable](values: List[T], key: fn(T) K) Map[K, List[T]]: values.group_by(
    key
)

fn index[T: Equal](values: List[T], value: T) Int?: values.index_of(value)

fn first(values: List[Int]) Int!MissingValue: values.first().ok_or()

fn unique[T: Hashable & Clonable](values: List[T]) Set[T]: values.to_set()

fn explain(cause: CollectionError) String:
    let common: Error = cause
    return common.message()

test "public collection support types retain their standard runtime identities":
    let values = [3, 4]
    let entries: List[ListEntry[Int]] = list_entries(values)
    let entry: ListEntry[Int] = ListEntry(0, 3)
    try expect_equal(entries[0], entry)

    var map = Map[String, Int]()
    map.add("a", 3)

    let pairs: List[MapEntry[String, Int]] = map_entries(map)
    let pair: MapEntry[String, Int] = MapEntry("a", 3)
    let found: MapEntry[String, Int]? = map.find(
        fn(key: String, value: Int) Bool: (value == 3)
    )
    try expect_false(pairs[0] != pair or found.get() != pair)

    let selected: List[Int]!CollectionError = slice(values)
    try expect_equal(selected.get(), [3])

    let invalid: List[Int]!CollectionError = values.slice(0, 9)
    let cause: CollectionError = invalid.err()
    try expect_false(cause != CollectionError.OutOfRange or explain(cause).is_empty())

    match cause:
        OutOfRange: unit
        _: return fail("scrutinee directed pattern")

    let grouped: Map[Int, List[Int]] = group(values, fn(value: Int) Int: (value % 2))
    let distinct: Set[Int] = unique(values)
    try expect_false(grouped.get(1).get() != [3] or distinct.values() != [3, 4])
    try expect_equal(index(values, 4).get(), 1)

    let absent: Int!MissingValue = first([])
    let missing: MissingValue = absent.err()
    let common: Error = missing
    try expect_false(not common.message().contains("collection-prelude-support.ms:"))
    try expect_equal(first(values).get(), 3)

type OtherError:
    case OutOfRange

test "new ambient error cases retain scrutinee directed patterns":
    let other = OtherError.OutOfRange

    match other:
        OutOfRange: unit

    let cause = [1].slice(0, 2).err()

    match cause:
        OutOfRange: unit
        _: return fail("wrong standard case")
