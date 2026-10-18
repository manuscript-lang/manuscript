import panic from "@std/faults.ms"

fn apply[T, U](value: T, transform: fn(value: T) U) U: transform(value)

fn chain[T, U](first: fn() T, second: fn(value: T) U) U: second(first())

fn with_result[T](transform: fn() Result[T, String]) Result[T, String]: transform()

fn checked() Result[Int, String]: ok(3)

type Box[T]:
    value: T

type Callback[T, U]:
    transform: fn(value: T) U

interface Read:
    fn get() Int

impl Read for Box[Int]:
    fn get() Int: self.value

fn invoke(transform: Optional[fn(value: Int) Int] = none) Int:
    match transform:
        some(callback): return callback(4)
        none: return 0

test "contextual callbacks and inline returns":
    let offset = 3
    let strings = (
        [1, 2, 3]
        .filter(fn(item): item > 1)
        .map(fn(number): (number + offset).to_string())
    )
    if strings.join(",") != "5,6": return panic("callback inference")

    let result = apply(transform: fn(item): item + offset, value: 2)
    if result != 5: return panic("generic callback")
    if chain(second: fn(item): item + 2, first: fn(): 3) != 5: return panic(
        "deferred callback"
    )

    let callback = Callback(fn(item: Int): item + 1)
    if callback.transform(3) != 4: return panic("constructor inference")

    let view = Read(Box(7))
    if view.get() != 7: return panic("constructor payloads")
    if invoke() != 0 or invoke(fn(item): item + 1) != 5: return panic(
        "optional callback"
    )

    let functions: List[fn(value: Int) Int] = [fn(item): item + 4]
    if functions.at(0).unwrap()(2) != 6: return panic("list callback")

    let nested = fn(value: Int):
        let inner = fn(): "text"
        return value + inner().scalar_length()
    if nested(2) != 6: return panic("nested return inference")

    let success = with_result(fn(): ok(4))
    if success != Result[Int, String].ok(4): return panic("partial Result context")

    let propagated = with_result(
        fn():
            let value = try checked()
            return ok(value + 2)
    )
    if propagated != Result[Int, String].ok(5): return panic(
        "inferred Result propagation"
    )

    let failed = with_result(
        fn():
            if true: return error("expected")

            return ok(4)
    )
    if failed != Result[Int, String].error("expected"): return panic(
        "inferred Result error"
    )

    let subtract: fn(left: Int, right: Int) Int = fn(a, b): a - b
    if subtract(right: 2, left: 7) != 5: return panic("context labels and order")

    let defaulted: fn(value: Int) Int = fn(item: Int = 4): item + 1
    if defaulted(value: 8) != 9: return panic("context default parameter")

    let outer: fn(value: Int) fn(input: Int) Int = fn(base):
        return fn(extra): base + extra
    if outer(value: 3)(input: 4) != 7: return panic("nested context labels")
