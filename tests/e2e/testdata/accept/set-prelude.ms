import panic from "@std/faults.ms"

fn insert[T: Hashable](values: Set[T], value: T) Set[T]: values.add(value)

test "set construction and methods need no import":
    let values: Set[Int] = Set()
    if not values.is_empty(): return panic("empty constructor")

    insert(values, 3).add(1).add(3)
    let add = values.add
    add(2)
    if values.length() != 3 or not values.contains(2): return panic("add and contains")
    if values.values() != [3, 1, 2]: return panic("deduplication and insertion order")

    let copy = values.clone()
    values.remove(1)
    if values.contains(1) or not copy.contains(1): return panic("remove and clone")

    let other = Set[Int]().add(4).add(2)
    if values.union(other).values() != [3, 2, 4]: return panic("union")
    if values.filter(fn(value: Int) Bool: value > 2).values() != [3]: return panic(
        "filter"
    )
    if values.map(fn(value: Int) Int: value * 2).values() != [6, 4]: return panic("map")

    let nested: List[Set[Int]] = [values]
    if nested[0].get().length() != 2: return panic("nested annotation")

    values.clear()
    if not values.is_empty() or copy.length() != 3: return panic("clear")
