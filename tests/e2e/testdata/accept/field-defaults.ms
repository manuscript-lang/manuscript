import {expect_equal, expect_false, expect_true} from "@std/testing.ms"

type Counter:
    value: Int = 0

fn mark(counter: Counter, value: Int) Int:
    counter.value = counter.value * 10 + value
    return value

type Ordered:
    counter: Counter
    first: Int = mark(counter: counter, value: 3)
    second: Int = mark(counter: counter, value: 4)
    third: Int = first + second

type Data:
    number: Int = 5
    values: List[Int] = [number]
    callback: fn() Int = (
        fn():
            return number
    )

type Box[T]:
    value: T
    copy: T = value

fn unit_default(calls: List[Int]) Unit:
    calls.append(1)

type Explicit:
    calls: List[Int]
    nothing: Unit = unit_default(calls)
    option: Optional[Int] = some(9)

test "record defaults and explicit overrides":
    let data = Data()
    (data.number != 5 or data.values.get(0) != 5 or data.callback() != 5) | try expect_false
    let changed = Data(number: 0)
    ((changed.number != 0 or changed.values.get(0) != 0 or changed.callback() != 0)) | try expect_false
    let calls: List[Int] = []
    let explicit = Explicit(calls: calls, nothing: unit, option: none)
    calls.is_empty() | try expect_true
    (explicit.option.is_none()) | try expect_true
    let box = Box(value: "text")
    box.copy | try expect_equal(expected: "text")
    let specified = Box[Int](value: 7, copy: 0)
    specified.copy | try expect_equal(expected: 0)

test "supplied fields precede defaults in field order":
    var counter = Counter()
    let ordered = Ordered(
        counter: counter,
        third: mark(counter: counter, value: 1),
        second: mark(counter: counter, value: 2)
    )
    (
        (
            counter.value != 123
            or ordered.first != 3
            or ordered.second != 2
            or ordered.third != 1
        )
    ) | try expect_false
    counter.value = 0
    let again = Ordered(counter: counter)
    (counter.value != 34 or again.third != 7) | try expect_false

test "mutable defaults have fresh storage":
    var first = Data()
    let second = Data()
    first.values.append(8)
    (first.values.length() != 2 or second.values.length() != 1) | try expect_false

interface ReadWithDefault:
    fn get(fallback: Optional[Int] = none) Int

type Reader:
    number: Int = 5

impl ReadWithDefault for Reader:
    fn get(fallback: Optional[Int]) Int:
        return fallback.get(self.number)

type Marker:

fn no_op() Unit:

test "ordinary empty declarations and interface omission":
    no_op()
    let marker = Marker()
    let view = ReadWithDefault(Reader())
    (view.get() != 5 or view.get(fallback: 7) != 7) | try expect_false
