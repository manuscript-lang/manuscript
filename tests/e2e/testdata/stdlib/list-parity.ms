import {ListPair, ListPartition} from "@std/collections.ms"
import Equal from "@std/equality.ms"
import panic from "@std/faults.ms"

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) -> Bool:
        match other:
            Key(found): return self.id == found.id
            _: return false

fn compare_int(left: Int, right: Int) -> Int:
    if left < right: return -1
    if left > right: return 1

    return 0

fn compare_key(left: Key, right: Key) -> Int:
    return compare_int(left.id, right.id)

fn is_even(value: Int) -> Bool: value % 2 == 0

fn unique_values[T: Equal](values: List[T]) -> List[T]: values.distinct()

test "list queries partition values without changing input storage":
    let values = [1, 2, 3, 4]
    if values.count(is_even) != 2: return panic("matching count")

    let count = values.count
    if count(is_even) != 2: return panic("stored count")

    let split: ListPartition[Int] = values.partition(is_even)
    if split.matching != [2, 4] or split.remaining != [1, 3]:
        return panic("partition order")

    split.matching.set(0, 9)
    split.remaining.append(5)
    if values != [1, 2, 3, 4]: return panic("partition output aliases receiver storage")

test "zip returns typed fresh pairs and shallow payload references":
    let first = Key(1, "first")
    let second = Key(2, "second")
    let values = [first, second]
    let names = ["a", "b", "extra"]
    let pairs: List[ListPair[Key, String]] = values.zip(names)
    if (
        pairs.length() != 2
        or pairs[0].unwrap().first != first
        or pairs[1].unwrap().second != "b"
    ):
        return panic("zip shape or shortest length")

    let pair = pairs[0].unwrap()
    pair.second = "changed"
    if names != ["a", "b", "extra"] or pairs[1].unwrap().second != "b":
        return panic("zip pair storage is shared")

    pair.first.label = "shared"
    if first.label != "shared": return panic("zip copied a payload")

    let zipped = values.zip[String]
    if zipped(["only"]).length() != 1: return panic("stored generic zip")

test "distinct uses Equal and keeps the first shallow payload":
    let first = Key(1, "first")
    let values = [first, Key(1, "duplicate"), Key(2, "second")]
    let unique = values.distinct()
    if (
        unique.length() != 2
        or unique.first().unwrap().label != "first"
        or unique.last().unwrap().id != 2
    ):
        return panic("selected equality or first payload")

    unique.first().unwrap().label = "shared"
    if first.label != "shared": return panic("distinct cloned payload")

    unique.pop()
    if values.length() != 3: return panic("distinct output shares outer storage")

    let distinct = values.distinct
    if distinct().length() != 2: return panic("stored Equal receiver")
    if unique_values(values).length() != 2: return panic("forwarded Equal evidence")

test "list extrema keep first ties and retain values before comparator mutation":
    let first = Key(1, "first")
    let values = [Key(2, "later"), first, Key(1, "tie")]
    if (
        values.min(compare_key).unwrap().label != "first"
        or values.max(compare_key).unwrap().id != 2
    ):
        return panic("extrema order and ties")

    let minimum = values.min
    if minimum(compare_key).unwrap().label != "first": return panic("stored comparator")

    let changed = [3, 2]
    if (
        changed.min(
            fn(left: Int, right: Int) -> Int:
                changed.set(1, 99)
                return compare_int(left, right)
        ) != some(2)
    ): return panic("minimum reread after callback")

    let greater = [2, 3]
    if (
        greater.max(
            fn(left: Int, right: Int) -> Int:
                greater.set(1, 99)
                return compare_int(left, right)
        ) != some(3)
    ): return panic("maximum reread after callback")

test "count and partition follow captured header mutation and retained pop tail":
    let values = [1, 2, 3]
    let visits: List[Int] = []
    let count = values.count(
        fn(value: Int) -> Bool:
            visits.append(value)

            if visits.length() == 1:
                values.set(0, 9)
                values.pop()

            return value % 2 == 1
    )
    if (
        visits != [1, 2, 3]
        or count != 2
        or values != [9, 2]
    ):
        return panic("count lost captured pop tail")

    let changed = [1, 2, 3]
    let split = changed.partition(
        fn(value: Int) -> Bool:
            if value == 1:
                changed.set(0, 9)
                changed.pop()

            return value % 2 == 1
    )
    if (
        split.matching != [1, 3]
        or split.remaining != [2]
        or changed != [9, 2]
    ):
        return panic("partition reread callback payload or lost captured tail")

test "insert pop and stable sorting mutate receiver aliases":
    let values = [3, 1, 2]
    let alias = values
    values.insert(0, 4).insert(
        values.length(),
        5
    )
    if alias != [4, 3, 1, 2, 5]: return panic("insert positions")

    let pop = values.pop
    if pop() != some(5) or alias != [4, 3, 1, 2]: return panic("stored pop and alias")

    values.sort_in_place(compare_int).append(6)
    if alias != [1, 2, 3, 4, 6]: return panic("in-place sorting or receiver return")

    let first = Key(1, "first")
    let records = [Key(2, "last"), first, Key(1, "second")]
    records.sort_in_place(compare_key)
    if records[0].unwrap().label != "first" or records[1].unwrap().label != "second":
        return panic("stable tie order")

    records[0].unwrap().label = "shared"
    if first.label != "shared": return panic("sort cloned payload")

test "empty list query and mutator identities":
    let empty: List[Int] = []
    if empty.count(is_even) != 0 or not empty.distinct().is_empty():
        return panic("empty count or distinct")
    if (
        not empty.min(compare_int).is_none()
        or not empty.max(compare_int).is_none()
        or not empty.pop().is_none()
    ):
        return panic("empty extrema or pop")

    let partition = empty.partition(is_even)
    if not partition.matching.is_empty() or not partition.remaining.is_empty():
        return panic("empty partition")
    if not empty.zip(["unused"]).is_empty(): return panic("empty zip")

    empty.sort_in_place(compare_int).insert(0, 1)
    if empty != [1]: return panic("empty sorting lost receiver identity")
