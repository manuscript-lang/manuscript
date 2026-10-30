import expect_equal, expect_false, expect_true from "@std/test.ms"

type Counter:
    value: Int = 0

fn mark(var counter: Counter, value: Int) Int:
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
        fn:
            return number
    )

type Box[T]:
    value: T
    copy: T = value

fn unit_default(var calls: List[Int]) Unit:
    calls.append(1)

type Explicit:
    calls: List[Int]
    nothing: Unit = unit_default(calls)
    option: Int? = some(9)

test "record defaults and explicit overrides":
    let data = Data()
    (data.number != 5 or data.values.get(0) != 5 or data.callback() != 5) | try expect_false

    let changed = Data(number: 0)
    ((changed.number != 0 or changed.values.get(0) != 0 or changed.callback() != 0)) | try expect_false

    let calls: List[Int] = []
    let explicit = Explicit(calls: calls.clone(), nothing: unit, option: none)
    calls.is_empty() | try expect_true
    (explicit.option.is_none()) | try expect_true

    let box = Box(value: "text")
    box.copy | try expect_equal("text")

    let specified = Box[Int](value: 7, copy: 0)
    specified.copy | try expect_equal(0)

test "supplied fields precede defaults in field order":
    var log = Counter()
    let ordered = Ordered(
        counter: Counter(), third: mark(counter: var log, value: 1),
        second: mark(counter: var log, value: 2)
    )
    (
        (
            log.value != 12
            or ordered.first != 3
            or ordered.second != 2
            or ordered.third != 1
        )
    ) | try expect_false

    let again = Ordered(counter: Counter())
    (again.third != 7) | try expect_false

test "mutable defaults have fresh storage":
    var first = Data()
    let second = Data()
    first.values.append(8)
    (first.values.length() != 2 or second.values.length() != 1) | try expect_false

interface ReadWithDefault:
    fn get(fallback: Int?) Int

type Reader:
    number: Int = 5

impl ReadWithDefault for Reader:
    fn get(fallback: Int?) Int:
        return fallback.get(self.number)

type Marker: ...

fn no_op() Unit: ...

test "ordinary empty declarations and interface omission":
    no_op()

    let _marker = Marker()
    let view: ReadWithDefault = Reader()
    (view.get() != 5 or view.get(fallback: 7) != 7) | try expect_false
