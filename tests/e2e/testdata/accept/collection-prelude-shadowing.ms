import panic from "@std/faults.ms"

type List[T]:
    value: T

type Map[K, V]:
    key: K
    value: V

type Set[T]:
    value: T

interface Add[V]:
    fn add(key: String, value: V) -> Int

impl Add[V] for Map[String, V]:
    fn add(key: String, value: V) -> Int: 42

test "local collection names and methods keep ordinary identities":
    let list = List(3)
    let map = Map("a", 4)
    let set = Set(5)
    if (
        list.value != 3
        or map.value != 4
        or set.value != 5
    ): return panic("local constructors")

    let bound = map.add
    if map.add("b", 9) != 42 or bound("c", 10) != 42: return panic(
        "local method dispatch"
    )
