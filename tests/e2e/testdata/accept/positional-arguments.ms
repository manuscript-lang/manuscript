import {expect_equal, expect_false} from "@std/testing.ms"

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

test "positional labeled mixed and identifier calls":
    let amount = 10
    let deduction = 3
    (
        (
            subtract(10, 3) != 7
            or subtract(amount: 10, deduction: 3) != 7
            or subtract(deduction: 3, amount: 10) != 7
            or subtract(deduction: 3, 10) != 7
            or subtract(10, deduction: 3) != 7
            or subtract(deduction, amount) != -7
            or subtract((deduction), (amount)) != -7
            or subtract(amount + 1, deduction) != 8
        )
    ) | try expect_false
    (
        (
            default_before_required(second: 2) != 7
            or default_before_required(second: 2, 5) != 3
        )
    ) | try expect_false

test "generic calls constructors and callback inference":
    (first(3, 4) != 3 or first[Int](right: 4, 3) != 3) | try expect_false
    try expect_equal(pick([1, 2], fn(item): item > 1).unwrap_or(0), 2)
    try expect_equal(pick(keep: fn(item): item > 1, [1, 2]).unwrap_or(0), 2)
    let record = Record(3)
    let explicit = Record[Int](second: 4, 3)
    (record.second != 3 or explicit.first != 3 or explicit.second != 4) | try expect_false
    let first = 4
    let second = 3
    let shorthand = Record(second, first)
    (shorthand.first != 3 or shorthand.second != 4) | try expect_false

    match Choice.Pair(second: "right", "left"):
        Pair(left, right):
            ((left != "left" or right != "right") | try expect_false)

    match Choice[Int].Pair(3, 4):
        Pair(left, right):
            ((left != 3 or right != 4) | try expect_false)

    let sum = [1, 2, 3].fold(0, fn(total, item): total + item)
    let reordered_sum = [1, 2, 3].fold(step: fn(total, item): total + item, 0)
    let explicit_sum = [1, 2, 3].fold[Int](0, fn(total, item): total + item)
    (sum != 6 or reordered_sum != 6 or explicit_sum != 6) | try expect_false
    (optional(4) != 4 or optional(none, 2) != 2) | try expect_false

test "methods native APIs function values and contextual labels":
    let offset = Offset(3)
    let bound = offset.subtract
    let view = Subtract(offset)
    (
        (
            offset.subtract(10) != 7
            or bound(10, 2) != 8
            or view.subtract(deduction: 2, 10) != 8
        )
    ) | try expect_false
    let copied = subtract
    let typed: fn(amount: Int, deduction: Int) -> Int = copied
    var mutable = typed
    (copied(10, 3) != 7 or typed(deduction: 3, 10) != 7 or mutable(10, 3) != 7) | try expect_false
    let contextual: fn(left: Int, right: Int) -> Int = fn(x, y): x - y
    try expect_false(
        (
            contextual(10, 3) != 7
            or contextual(right: 3, 10) != 7
            or apply(fn(x, y): x - y, 10) != 8
        )
    )
    let memo = Map[Int, Int]()
    let ignored = memo.add(1, 7)
    let add = memo.add
    let more = add(value: 8, 2)
    (memo.get(1).unwrap() != 7 or memo.get(2).unwrap() != 8) | try expect_false
    "abcd".slice(1, 3).unwrap() | try expect_equal(expected: "bc")

test "written order before omitted defaults and body":
    let counter = Counter()
    let total = ordered(counter, third: mark(counter, 1), mark(counter, 2))
    (total != 7 or counter.value != 1245) | try expect_false
    counter.value = 0
    let reordered = first(right: mark(counter, 2), mark(counter, 1))
    (reordered != 1 or counter.value != 21) | try expect_false
    counter.value = 0
    let record = Record(second: mark(counter, 2), mark(counter, 1))
    (record.first != 1 or record.second != 2 or counter.value != 21) | try expect_false
    var early = 7
    let selected = first(
        early,
        match some(0):
            some(_):
                early = 9
                0
            none: 0
    )
    selected | try expect_equal(expected: 7)
    var receiver = Offset(3)
    let result = receiver.subtract(
        match some(0):
            some(_):
                receiver = Offset(9)
                10
            none: 10
    )
    result | try expect_equal(expected: 7)

test "callable expression precedes positional arguments":
    let counter = Counter()
    let factory = fn() -> fn(amount: Int, deduction: Int) -> Int:
        let ignored = mark(counter, 1)
        return subtract
    let result = factory()(mark(counter, 2), mark(counter, 3))
    (result != -1 or counter.value != 123) | try expect_false

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
    result | try expect_equal(expected: 7)
