import {List, Map} from "@std/collections.ms"
import panic from "@std/faults.ms"

fn subtract(amount: Int, deduction: Int) -> Int: amount - deduction

fn first[T](left: T, right: T) -> T: left

fn pick[T](items: List[T], keep: fn(value: T) -> Bool) -> Optional[T]:
    for item in items:
        if keep(item): return some(item)

    return none

type Counter:
    value: Int = 0

fn mark(counter: Counter, value: Int) -> Int:
    counter.value = counter.value * 10 + value
    return value

fn ordered(
    counter: Counter,
    first: Int = mark(counter, 3),
    second: Int = mark(counter, 4),
    third: Int = 0
) -> Int:
    counter.value = counter.value * 10 + 5
    return first + second + third

type Record[T]:
    first: T
    second: T = first

type Choice[T]:
    case Pair(first: T, second: T)

interface Subtract:
    fn subtract(amount: Int, deduction: Int) -> Int

type Offset:
    value: Int

impl Subtract for Offset:
    fn subtract(amount: Int, deduction: Int = self.value) -> Int: amount - deduction

fn apply(callback: fn(left: Int, right: Int) -> Int, input: Int) -> Int: callback(
    input,
    2
)

fn optional(value: Optional[Int], fallback: Int = 0) -> Int: value.unwrap_or(fallback)

fn default_before_required(first: Int = 9, second: Int) -> Int: first - second

test "positional labeled mixed and legacy shorthand calls":
    let amount = 10
    let deduction = 3
    if (
        subtract(10, 3) != 7
        or subtract(amount: 10, deduction: 3) != 7
        or subtract(deduction: 3, amount: 10) != 7
        or subtract(deduction: 3, 10) != 7
        or subtract(10, deduction: 3) != 7
        or subtract(deduction, amount) != 7
        or subtract((deduction), (amount)) != -7
        or subtract(amount + 1, deduction) != 8
    ): return panic("call binding")
    if (
        default_before_required(second: 2) != 7
        or default_before_required(second: 2, 5) != 3
    ):
        return panic("default slots are not skipped")

test "generic calls constructors and callback inference":
    if first(3, 4) != 3 or first[Int](right: 4, 3) != 3: return panic("generic call")
    if pick(
        [1, 2],
        fn(item): item > 1
    ).unwrap_or(0) != 2: return panic("generic callback")
    if pick(
        keep: fn(item): item > 1,
        [1, 2]
    ).unwrap_or(0) != 2: return panic("callback before inference input")

    let record = Record(3)
    let explicit = Record[Int](second: 4, 3)
    if (
        record.second != 3
        or explicit.first != 3
        or explicit.second != 4
    ): return panic("record defaults")

    let first = 4
    let second = 3
    let shorthand = Record(second, first)
    if shorthand.first != 4 or shorthand.second != 3: return panic(
        "constructor shorthand"
    )

    match Choice.Pair(second: "right", "left"):
        Pair(left, right):
            if left != "left" or right != "right": return panic("case field order")

    match Choice[Int].Pair(3, 4):
        Pair(left, right):
            if left != 3 or right != 4: return panic("explicit generic case")

    let sum = [1, 2, 3].fold(
        0,
        fn(total, item): total + item
    )
    let reordered_sum = [1, 2, 3].fold(
        step: fn(total, item): total + item,
        0
    )
    let explicit_sum = [1, 2, 3].fold[Int](
        0,
        fn(total, item): total + item
    )
    if (
        sum != 6
        or reordered_sum != 6
        or explicit_sum != 6
    ): return panic("native generic mixed callback inference")
    if optional(4) != 4 or optional(none, 2) != 2: return panic(
        "optional wrapping and omission"
    )

test "methods native APIs function values and contextual labels":
    let offset = Offset(3)
    let bound = offset.subtract
    let view = Subtract(offset)
    if (
        offset.subtract(10) != 7
        or bound(10, 2) != 8
        or view.subtract(deduction: 2, 10) != 8
    ):
        return panic("receiver and bound methods")

    let copied = subtract
    let typed: fn(amount: Int, deduction: Int) -> Int = copied
    var mutable = typed
    if (
        copied(10, 3) != 7
        or typed(deduction: 3, 10) != 7
        or mutable(10, 3) != 7
    ):
        return panic("function values")

    let contextual: fn(left: Int, right: Int) -> Int = fn(x, y): x - y
    if (
        contextual(10, 3) != 7
        or contextual(right: 3, 10) != 7
        or apply(
            fn(x, y): x - y,
            10
        ) != 8
    ):
        return panic("context labels and local callback names")

    let memo = Map[Int, Int]()
    let ignored = memo.with_entry(1, 7)
    let add = memo.with_entry
    let more = add(value: 8, 2)
    if memo.get(1).unwrap() != 7 or memo.get(2).unwrap() != 8: return panic(
        "native multi parameter methods"
    )
    if "abcd".slice(1, 3).unwrap() != "bc": return panic("native string arguments")

test "written order before omitted defaults and body":
    let counter = Counter()
    let total = ordered(
        counter,
        third: mark(counter, 1),
        mark(counter, 2)
    )
    if total != 7 or counter.value != 1245: return panic(
        "mixed supplied values before defaults"
    )

    counter.value = 0
    let reordered = first(
        right: mark(counter, 2),
        mark(counter, 1)
    )
    if reordered != 1 or counter.value != 21: return panic(
        "inference must not reorder or repeat arguments"
    )

    counter.value = 0
    let record = Record(
        second: mark(counter, 2),
        mark(counter, 1)
    )
    if (
        record.first != 1
        or record.second != 2
        or counter.value != 21
    ): return panic("constructor evaluation")

    var early = 7
    let selected = first(
        early,
        match some(0):
            some(_):
                early = 9
                0
            none: 0
    )
    if selected != 7: return panic("capture positional value before later argument")

    var receiver = Offset(3)
    let result = receiver.subtract(
        match some(0):
            some(_):
                receiver = Offset(9)
                10
            none: 10
    )
    if result != 7: return panic("capture receiver before arguments")

test "callable expression precedes positional arguments":
    let counter = Counter()
    let factory = fn() -> fn(amount: Int, deduction: Int) -> Int:
        let ignored = mark(counter, 1)
        return subtract
    let result = factory()(
        mark(counter, 2),
        mark(counter, 3)
    )
    if result != -1 or counter.value != 123: return panic("callable expression order")

test "mutable callable value is captured before arguments":
    var selected = subtract
    let result = selected(
        match some(0):
            some(_):
                selected = fn(amount: Int, deduction: Int) -> Int: amount + deduction
                10
            none: 10
        ,
        3
    )
    if result != 7: return panic("callable value captured after argument")
