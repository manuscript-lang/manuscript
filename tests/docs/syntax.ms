# Parser fixture: lexical forms, independent of name resolution.
from "@std/io.ms" import (stdout, IoError)
from "./support.ms" import Sample

extern type Native

extern def native_call(value: Int) -> Int

export type Box[T: Equal & Hashable = Int]:
    value: T

type State:
    case Ready
    case Data(value: Int)

interface Reader:
    def text() -> ref String

type Document:
    value: String

impl Reader for Document:
    def text() -> ref String:
        return self.value

impl Document:
    var def replace(value: String) -> Unit:
        self.value = value

export def identity[T](value: T) -> T:
    return value

let (
    MASK = 0xFF_FF
    FLAGS = 0b1010_0101
    COUNT = 1_000_000
    RATIO = 3.141_592e-2
    PRICE = 1_000.50_25E+2d
)

def syntax(var items: List[Int], doc: Document, state: State) -> Int:
    let from = 1
    let as = from
    let borrowed = doc.value
    var exclusive = items[0]
    let [first, second] = [1, 2]
    let {value: label} = doc
    let callback = lambda value: value + 1
    let typed: Callable[[Int], Int] = lambda (value: Int) -> Int: value * 2
    let specialized = identity[List[Int]](items)
    let mapping = {"count": COUNT, "ratio": RATIO}
    let plain = "Literal {braces}, # text, \"quote\", \\, \t, \r, \n, \u{1F642}"
    let message = f"\{escaped\} {mapping.get("count")} {f"{callback(1)}"} \u{41}"

    let selected = first if True and not False or as == 0 else second

    var total = 0
    total += 1
    total -= 2
    total *= 3
    total /= 4
    total %= 5

    for item in 0..10:
        if item != selected:
            continue
        elif item >= 2:
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
        case Ready: 0
        case Data(value): value
        case _: -1

    let parsed = "42" | try parse | normalize
    return result + parsed

test "fixture and unit":
    fixture.setup()

    let empty = ()
    check(empty)

def runtime_bound() -> Unit: ...
