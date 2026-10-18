import range from "@std/collections.ms"
import panic from "@std/faults.ms"

test "List count calls the predicate once per element":
    let values = [1, 2, 3, 4]
    let seen: List[Int] = []
    let even = values.count(
        fn(value: Int) Bool:
            seen.append(value)
            return value % 2 == 0
    )
    if even != 2 or seen != values: return panic("count matches")

    let empty: List[Int] = []
    if empty.count(fn(value: Int) Bool: true) != 0: return panic("empty count")

test "List insert mutates in place and returns the same list":
    let values = [1, 3]
    let alias = values
    let returned = values.insert(1, 2)
    if (values != [1, 2, 3] or alias != [1, 2, 3] or returned != values): return panic(
        "middle insert"
    )

    returned.append(4)
    if values != [1, 2, 3, 4]: return panic("insert returned a copy")

    values.insert(0, 0).insert(5, 5)
    if values != [0, 1, 2, 3, 4, 5]: return panic("boundary insert")

    values.insert(-1, 9)
    if values != [0, 1, 2, 3, 4, 9, 5]: return panic("relative insert")

    values.insert(-7, 8)
    if values != [8, 0, 1, 2, 3, 4, 9, 5]: return panic("first relative insert")

    let empty: List[String] = []
    if empty.insert(0, "a") != ["a"]: return panic("empty insert")

test "List pop removes and returns the last element":
    let values = [1, 2, 3]
    let alias = values
    let last = values.pop()
    if (last != some(3) or values != [1, 2] or alias != [1, 2]): return panic(
        "pop last"
    )

    values.pop()
    values.pop()
    if values.pop().is_some() or not (values.is_empty()): return panic("pop empty")

type Box:
    value: Int

test "List pop and distinct retain payload references":
    let shared = Box(1)
    let boxes = [shared]
    boxes.pop().unwrap().value = 2
    if shared.value != 2: return panic("pop payload cloned")

    let nested = [1]
    let lists = [nested, [1], [2]]
    let unique = lists.distinct()
    unique.at(0).unwrap().append(3)
    if unique.length() != 2 or nested != [1, 3]: return panic("distinct payload cloned")

test "List distinct keeps the first equal element in order":
    let values = [3, 1, 3, 2, 1]
    let unique = values.distinct()
    if unique != [3, 1, 2] or values != [3, 1, 3, 2, 1]: return panic("distinct order")

    unique.append(4)
    if values.length() != 5: return panic("distinct storage alias")

    let words = ["b", "a", "b"]
    if words.distinct() != ["b", "a"]: return panic("distinct text")

    let empty: List[Int] = []
    let copy = empty.distinct()
    copy.append(1)
    if not (empty.is_empty()): return panic("empty distinct alias")

fn unique_count[T: Equal](values: List[T]) Int:
    return values.distinct().length()

test "List parity operations support generic and bound use":
    if unique_count([1, 1, 2]) != 2: return panic("generic distinct")

    var values = [1, 2]
    let insert = values.insert
    let pop: fn() Optional[Int] = values.pop
    let count = values.count
    values = [9]
    insert(index: 2, value: 3)
    if pop() != some(3) or count(fn(value: Int) Bool: value > 0) != 2: return panic(
        "bound receiver"
    )
    if values != [9]: return panic("bound receiver rebinding")

test "List distinct handles large Int and String lists":
    var numbers: List[Int] = []
    var words: List[String] = []

    for index in range(0, 60000):
        numbers.append(index % 30000)
        words.append("w{index % 20000}")

    let unique = numbers.distinct()
    if (
        unique.length() != 30000
        or unique.first() != some(0)
        or unique.last() != some(29999)
    ): return panic("distinct ints")

    let uniqueWords = words.distinct()
    if uniqueWords.length() != 20000 or uniqueWords.at(1) != some("w1"): return panic(
        "distinct strings"
    )
