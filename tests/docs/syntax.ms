# Parser fixture: lexical forms, independent of name resolution.
import {stdout, IoError} from "@std/io.ms"
import Sample from "./support.ms"

extern type Native

extern fn native_call(value: Int) Int

export type Box[T: Equal & Hashable = Int]:
    value: T

type State:
    case Ready
    case Data(value: Int)

interface Reader:
    fn text() ref String

type Document:
    value: String

impl Reader for Document:
    fn text() ref String:
        return self.value

impl Document:
    var fn replace(value: String) Unit:
        self.value = value

export fn identity[T](value: T) T:
    return value

let (
    MASK = 0xFF_FF
    FLAGS = 0b1010_0101
    COUNT = 1_000_000
    RATIO = 3.141_592e-2
    PRICE = 1_000.50_25E+2d
)

fn syntax(var items: List[Int], doc: Document, state: State) Int:
    let from = 1
    let as = from
    let borrowed = doc.value
    var exclusive = items[0]
    let [first, second] = [1, 2]
    let {value: label} = doc
    let callback = fn value: value + 1
    let typed: fn(Int) Int = fn(value: Int) Int: value * 2
    let specialized = identity[List[Int]](items)
    let mapping = {"count": COUNT, "ratio": RATIO}
    let plain = "Literal \{braces\}, # text, \"quote\", \\, \t, \r, \n, \u{1F642}"
    let message = "\{escaped\} {mapping.get("count")} {"{callback(1)}"} \u{41}"

    let selected = if true and not false or as == 0: first else: second

    var total = 0
    total += 1
    total -= 2
    total *= 3
    total /= 4
    total %= 5

    for item in 0..10:
        if item != selected:
            continue
        else if item >= 2:
            break
        else:
            total = item

    while total <= 10:
        total = total + 1
    if let value = items.first():
        total = value
    if var value = items.first():
        value += 1

    var resource = acquire()
    resource.read()
    resource.close()

    var guard = lock()
    guard.value = total
    guard.close()

    let result = match state:
        Ready: 0
        Data(value): value
        _: -1

    let parsed = "42" | try parse | normalize
    return result + parsed

test "fixture and unit":
    fixture.setup()

    let empty = unit
    check(empty)

fn runtime_bound() Unit: ...
