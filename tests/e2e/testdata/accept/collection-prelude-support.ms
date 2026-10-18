import panic from "@std/faults.ms"

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
    if entries[0].unwrap() != entry: return panic("list entry")

    let map = Map[String, Int]().add("a", 3)
    let pairs: List[MapEntry[String, Int]] = map_entries(map)
    let pair: MapEntry[String, Int] = MapEntry("a", 3)
    let found: Optional[MapEntry[String, Int]] = map.find(
        fn(key: String, value: Int) -> Bool: (value == 3)
    )
    if pairs[0].unwrap() != pair or found.unwrap() != pair: return panic("map entry")

    let selected: Result[List[Int], CollectionError] = slice(values)
    if selected.unwrap() != [3]: return panic("slice success")

    let invalid: Result[List[Int], CollectionError] = values.slice(0, 9)
    let cause: CollectionError = invalid.unwrap_error()
    if cause != CollectionError.OutOfRange or explain(cause).is_empty(): return panic(
        "collection error"
    )

    match cause:
        OutOfRange: unit
        _: return panic("scrutinee directed pattern")

    let grouped: Map[Int, List[Int]] = group(values, fn(value: Int) -> Int: value % 2)
    let distinct: Set[Int] = unique(values)
    if grouped.get(1).unwrap() != [3] or distinct.values() != [3, 4]: return panic(
        "Hashable bounds"
    )
    if index(values, 4).unwrap() != 1: return panic("Equal receiver bound")

    let absent: Result[Int, MissingValue] = first([])
    let missing: MissingValue = absent.unwrap_error()
    let common: Error = missing
    if not common.message().contains("collection-prelude-support.ms:"): return panic(
        "default error location"
    )
    if first(values).unwrap() != 3: return panic("present default conversion")

type OtherError:
    case OutOfRange

test "new ambient error cases retain scrutinee directed patterns":
    let other = OtherError.OutOfRange

    match other:
        OutOfRange: unit

    let cause = [1].slice(0, 2).unwrap_error()

    match cause:
        OutOfRange: unit
        _: return panic("wrong standard case")
