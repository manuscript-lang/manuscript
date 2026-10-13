import panic from "@std/faults.ms"
import List from "@std/collections.ms"

type Counter:
    value: Int = 0

fn bump(counter: Counter) -> Bool:
    counter.value = counter.value + 1
    return true

fn identity[T](value: T) -> T: value

fn combine(left: Int, right: Int = 3) -> Int: left * 10 + right

fn floatMath(a: Float, b: Float, c: Float) -> Float: a * (b + c)

test "structured lowering":
    let counter = Counter()
    let short = false and bump(counter) or true
    let effect = bump(counter) and false
    if not short or effect or counter.value != 1:
        return panic("short circuit changed")
    let escaped = "quote: \" slash: \\ newline: \n Unicode: λ"
    if escaped != identity(escaped): return panic("escaping changed")
    let minimum = -9223372036854775808
    if minimum >= 0: return panic("integer sign changed")
    if floatMath(a: 2.0, b: 3.0, c: 4.0) != 14.0:
        return panic("precedence changed")
    var original = 5
    let snapshot = fn(value: Int) -> Int: original + value
    original = 9
    if snapshot(2) != 7: return panic("capture changed")
    let values = [1, 2, 3]
    let [first, second, third] = values
    if combine(left: first) != 13: return panic("default changed")
    if combine(right: second, left: third) != 32:
        return panic("argument order changed")
    if values.at(0).unwrap() != 1: return panic("index changed")
    var total = 0
    for value in values:
        if value == 2: continue
        total = total + value
    var iterations = 0
    while iterations < 3:
        iterations = iterations + 1
        let selected: Optional[Int] = some(iterations)
        let unwrapped = match selected:
            some(value):
                if value == 2: continue
                value
            none: 0
        total = total + unwrapped
    if total != 8: return panic("loop exit changed")
