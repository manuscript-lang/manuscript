import panic from "@std/faults.ms"

type Counter:
    value: Int

fn stamp(counter: Counter, value: Int) -> Int:
    counter.value = counter.value * 10 + value
    return value
fn combine(left: Int, right: Int = 3) -> Int: left * 10 + right
fn scalar_loop(limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = combine(right: index % 7, left: total)
        index = index + 1
        if index == 4: break
    return total
fn identity(value: Int) -> Int: value
fn recurse(value: Int) -> Int:
    if value == 0: return 0
    return recurse(value - 1) + 1
fn floating(limit: Int) -> Float:
    var total = 0.0
    var index = 0
    while index < limit:
        total = total + 0.25
        index = index + 1
    return total
fn logic(limit: Int) -> Bool:
    var active = true
    var index = 0
    while index < limit:
        active = not active
        index = index + 1
    return active

test "native source calls preserve order defaults recursion and captures":
    let counter = Counter(0)
    let result = combine(right: stamp(counter, 2), left: stamp(counter, 1))
    if result != 12 or counter.value != 21: return panic("reordered call effects")
    if combine(2) != 23 or combine(right: 4, left: 2) != 24: return panic("default boundary")
    if scalar_loop(100) != 123 or recurse(1000) != 1000: return panic("native loops and recursion")
    if floating(1000) != 250.0 or logic(1001): return panic("typed Float/Bool locals")
    var original = 1000
    let snapshot = fn() -> Int: original
    original = 2000
    if snapshot() != 1000: return panic("capture snapshot")
    let callback = identity
    if callback(1000) != 1000: return panic("first-class identity")
    var number = 1
    let total = number + (match some(1):
        some(value):
            number = number + 1
            value
        none: 0
    )
    if total != 2 or number != 2: return panic("left numeric read moved after right effect")
    var argument = 1
    let ordered = combine(argument, match some(2):
        some(value):
            argument = 9
            value
        none: 0
    )
    if ordered != 12 or argument != 9: return panic("left argument read moved after right effect")
    var shadow = 0
    while shadow < 3:
        let inner = shadow * 3
        if inner == 3:
            var shadow = 1000
            shadow = shadow + 1
            if shadow != 1001: return panic("binding identity")
        shadow = shadow + 1
    if shadow != 3: return panic("outer binding")
