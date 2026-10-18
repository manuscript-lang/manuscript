import panic from "@std/faults.ms"

type Counter:
    value: Int = 0

fn mark(counter: Counter, value: Int) Int:
    counter.value = counter.value * 10 + value
    return value

type Ordered:
    counter: Counter
    first: Int = mark(counter, 3)
    second: Int = mark(counter, 4)
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

type Explicit:
    nothing: Unit = panic("Unit default must be skipped")
    option: Optional[Int] = some(9)

test "record defaults and explicit overrides":
    let data = Data()
    if (data.number != 5 or data.values.at(0).unwrap() != 5 or data.callback() != 5):
        return panic("dependent field and closure defaults")

    let changed = Data(0)
    if (
        changed.number != 0
        or changed.values.at(0).unwrap() != 0
        or changed.callback() != 0
    ):
        return panic("explicit field overrides dependent defaults")

    let explicit = Explicit(unit, none)
    if not explicit.option.is_none():
        return panic("explicit none must override a default")

    let box = Box("text")
    if box.copy != "text":
        return panic("inferred generic record default")

    let specified = Box[Int](7, 0)
    if specified.copy != 0:
        return panic("explicit generic record override")

test "supplied fields precede defaults in field order":
    let counter = Counter()
    let ordered = Ordered(counter, third: mark(counter, 1), second: mark(counter, 2))
    if (
        counter.value != 123
        or ordered.first != 3
        or ordered.second != 2
        or ordered.third != 1
    ):
        return panic("constructor evaluation order")

    counter.value = 0
    let again = Ordered(counter)
    if counter.value != 34 or again.third != 7:
        return panic("defaults must evaluate on each construction")

test "mutable defaults have fresh storage":
    let first = Data()
    let second = Data()
    first.values.append(8)
    if first.values.length() != 2 or second.values.length() != 1:
        return panic("record defaults must not share collection storage")

interface ReadWithDefault:
    fn get(fallback: Optional[Int] = none) Int

type Reader:
    number: Int = 5

impl ReadWithDefault for Reader:
    fn get(fallback: Optional[Int]) Int:
        return fallback.unwrap_or(self.number)

type Marker:

fn no_op() Unit:

test "ordinary empty declarations and interface omission":
    no_op()
    let _marker = Marker()
    let view = ReadWithDefault(Reader())
    if view.get() != 5 or view.get(7) != 7:
        return panic("interface Optional defaults must reach source implementations")
