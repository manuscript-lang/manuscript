import panic from "@std/faults.ms"

fn pair(a: Int, b: Int) -> Int: a * 10 + b

test "arguments":
    var value = 1
    let option: Optional[Int] = some(2)
    let result = pair(
        a: value,
        b: match option:
        some(i):
            value = 9
            i
        none: 0
    )
    if result != 12: return panic("argument order")

fn optional(value: Optional[Int]) -> Int: value.unwrap()

fn defaulted(value: Int = 3) -> Int: value

fn identity[T](value: T) -> T: value

test "source call dispatch contracts":
    if optional(4) != 4: return panic("optional argument")
    if defaulted(5) != 5: return panic("explicit default")
    if defaulted() != 3: return panic("omitted default")
    if pair(b: 2, a: 1) != 12: return panic("reordered arguments")

    let callback = pair
    if callback(a: 3, b: 4) != 34: return panic("callback")
    if identity(6) != 6: return panic("generic call")
