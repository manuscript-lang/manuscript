import List from "@std/collections.ms"

type Counter:
    value: Int

fn construct(limit: Int) -> Int:
    let values: List[Counter] = []
    var index = 0
    while index < limit:
        values.append(Counter(index))
        index = index + 1
    return values.length()

fn access(limit: Int) -> Int:
    let counter = Counter(0)
    var index = 0
    while index < limit:
        counter.value = counter.value + 1
        index = index + 1
    return counter.value

fn alias_clone(limit: Int) -> Int:
    let original = Counter(1)
    let alias = original
    var total = 0
    var index = 0
    while index < limit:
        let copy = original.clone()
        copy.value = 2
        alias.value = 3
        total = total + copy.value + original.value
        index = index + 1
    return total
