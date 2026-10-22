import {expect_equal, expect_false} from "@std/testing.ms"

fn subtract(amount: Int, deduction: Int) Int: amount - deduction

fn first[T](left: T, right: T) T: left

fn pick[T](items: List[T], keep: fn(value: T) Bool) Optional[T]:
    for item in items:
        if keep(item): return some(item)
    return none

type Counter:
    value: Int = 0

fn mark(var counter: Counter, value: Int) Int:
    counter.value = counter.value * 10 + value
    return value

fn ordered(
    var counter: Counter, first: Int = mark(counter, 3), second: Int = mark(counter, 4),
    third: Int = 0
) Int:
    counter.value = counter.value * 10 + 5
    return first + second + third

type Record[T]:
    first: T
    second: T = first

type Choice[T]:
    case Pair(first: T, second: T)

interface Subtract:
    fn subtract(amount: Int, deduction: Int) Int

type Offset:
    value: Int

impl Subtract for Offset:
    fn subtract(amount: Int, deduction: Int = self.value) Int: amount - deduction

fn apply(callback: fn(left: Int, right: Int) Int, input: Int) Int: callback(input, 2)

fn optional(value: Optional[Int], fallback: Int = 0) Int: value.get(fallback)

fn default_before_required(first: Int = 9, second: Int) Int: first - second

test "positional labeled mixed and identifier calls":
    let amount = 10
    let deduction = 3
    try expect_false(
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
    )
    try expect_false(
        (
            default_before_required(second: 2) != 7
            or default_before_required(second: 2, 5) != 3
        )
    )

test "generic calls constructors and callback inference":
    try expect_false(first(3, 4) != 3 or first[Int](right: 4, 3) != 3)
    try expect_equal(pick([1, 2], fn(item): item > 1).get(0), 2)
    try expect_equal(pick(keep: fn(item): item > 1, [1, 2]).get(0), 2)
    let record = Record(3)
    let explicit = Record[Int](second: 4, 3)
    try expect_false(
        (record.second != 3 or explicit.first != 3 or explicit.second != 4)
    )
    let first = 4
    let second = 3
    let shorthand = Record(second, first)
    try expect_false(shorthand.first != 3 or shorthand.second != 4)

    match Choice.Pair(second: "right", "left"):
        Pair(left, right):
            try expect_false(left != "left" or right != "right")

    match Choice[Int].Pair(3, 4):
        Pair(left, right):
            try expect_false(left != 3 or right != 4)

    let sum = [1, 2, 3].fold(0, fn(total, item): total + item)
    let reordered_sum = [1, 2, 3].fold(step: fn(total, item): total + item, 0)
    let explicit_sum = [1, 2, 3].fold[Int](0, fn(total, item): total + item)
    try expect_false((sum != 6 or reordered_sum != 6 or explicit_sum != 6))
    try expect_false(optional(4) != 4 or optional(none, 2) != 2)

test "methods native APIs function values and contextual labels":
    let offset = Offset(3)
    let bound = offset.subtract
    let view = Subtract(offset)
    try expect_false(
        (
            offset.subtract(10) != 7
            or bound(10, 2) != 8
            or view.subtract(deduction: 2, 10) != 8
        )
    )
    let copied = subtract
    let typed: fn(amount: Int, deduction: Int) Int = copied
    var mutable = typed
    try expect_false(
        (
            copied(10, 3) != 7
            or typed(deduction: 3, 10) != 7
            or mutable(10, 3) != 7
        )
    )
    let contextual: fn(left: Int, right: Int) Int = fn(x, y): x - y
    try expect_false(
        (
            contextual(10, 3) != 7
            or contextual(right: 3, 10) != 7
            or apply(fn(x, y): x - y, 10) != 8
        )
    )
    var memo = Map[Int, Int]()
    memo.add(1, 7)
    let add = memo.add
    add(value: 8, 2)
    try expect_false(memo.get(1).get() != 7 or memo.get(2).get() != 8)
    try expect_equal("abcd".slice(1, 3).get(), "bc")

test "written order before omitted defaults and body":
    var counter = Counter()
    let total = ordered(var counter, third: mark(var counter, 1), mark(var counter, 2))
    try expect_false(total != 7 or counter.value != 1245)
    counter.value = 0
    let reordered = first(right: mark(var counter, 2), mark(var counter, 1))
    try expect_false(reordered != 1 or counter.value != 21)
    counter.value = 0
    let record = Record(second: mark(var counter, 2), mark(var counter, 1))
    try expect_false((record.first != 1 or record.second != 2 or counter.value != 21))
    var early = 7
    let selected = first(
        early,
        match some(0):
            some(_):
                early = 9
                0
            none: 0
    )
    try expect_equal(selected, 7)
    var receiver = Offset(3)
    let result = receiver.subtract(
        match some(0):
            some(_):
                receiver = Offset(9)
                10
            none: 10
    )
    try expect_equal(result, 7)

test "callable expression precedes positional arguments":
    var counter = Counter()
    let factory = fn() fn(amount: Int, deduction: Int) Int:
        mark(var counter, 1)
        return subtract
    let result = factory()(mark(var counter, 2), mark(var counter, 3))
    try expect_false(result != -1 or counter.value != 123)

test "mutable callable value is captured before arguments":
    var selected = subtract
    let result = selected(
        match some(0):
            some(_):
                selected = fn(amount: Int, deduction: Int) Int: amount + deduction
                10
            none: 10
        ,
        3
    )
    try expect_equal(result, 7)
